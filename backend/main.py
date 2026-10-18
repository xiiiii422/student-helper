"""FastAPI 入口：无状态代理，负责鉴权 + Prompt 拼装 + 流式转发。"""
import json

import structlog
from fastapi import FastAPI, Header, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse, StreamingResponse

from config import settings
from llm_client import stream_chat
from prompts import COMPOSITION_PROMPT, COMPOSITION_REWRITE_PROMPT, SYSTEM_PROMPTS
from schemas import (
    ChatRequest,
    CompositionRequest,
    HealthResponse,
    RewriteRequest,
)

app = FastAPI(title="StudentHelper Backend")
log = structlog.get_logger()

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)


def verify_token(authorization: str) -> None:
    if authorization != f"Bearer {settings.backend_secret_token}":
        raise HTTPException(401, "invalid token")


@app.get("/health", response_model=HealthResponse)
async def health():
    return {"status": "ok", "model": f"{settings.chat_model}+{settings.vl_model}"}


@app.post("/api/chat")
async def chat(req: ChatRequest, authorization: str = Header(...)):
    verify_token(authorization)

    system = SYSTEM_PROMPTS[req.subject]
    history = req.history[-settings.max_history_turns * 2:]  # 截断（N 对 = 2N 条）

    messages = [{"role": "system", "content": system}]
    messages += [m.model_dump() for m in history]
    messages.append({"role": "user", "content": req.text})

    async def sse():
        images = [req.image_base64] if req.image_base64 else None
        try:
            async for delta in stream_chat(messages, images):
                yield f"data: {json.dumps({'delta': delta}, ensure_ascii=False)}\n\n"
            yield f"data: {json.dumps({'done': True})}\n\n"
        except Exception as e:  # noqa: BLE001
            log.error("chat_error", err=str(e))
            yield f"data: {json.dumps({'error': str(e)}, ensure_ascii=False)}\n\n"

    return StreamingResponse(sse(), media_type="text/event-stream")


@app.post("/api/composition")
async def composition(req: CompositionRequest, authorization: str = Header(...)):
    verify_token(authorization)

    content = req.content or "（图片形式提交，请先识别图中作文内容）"
    user_msg = f"作文标题：{req.title}\n年级：{req.grade}\n"
    if req.requirement:
        user_msg += f"题目要求：{req.requirement}\n"
    if len(req.images_base64) > 1:
        user_msg += (f"说明：作者共上传了 {len(req.images_base64)} 页手稿图片，按页码顺序排列，"
                     "请通读全部页面后再批改，引用时注明第几页。\n")
    user_msg += f"作文正文：\n{content}"

    messages = [
        {"role": "system", "content": COMPOSITION_PROMPT},
        {"role": "user", "content": user_msg},
    ]
    # 多页手稿全部上传（最多 4 页）
    images = req.images_base64[:4] or None

    # 作文批改不流式，一次性收完整文本再解析
    full_text = ""
    try:
        async for delta in stream_chat(messages, images):
            full_text += delta
    except Exception as e:  # noqa: BLE001
        log.error("composition_error", err=str(e))
        return JSONResponse({"ok": False, "feedback": None, "raw": f"调用失败: {e}"})

    parsed = _safe_json(full_text)
    if parsed is None:
        return JSONResponse({"ok": False, "feedback": None, "raw": full_text})
    return JSONResponse({"ok": True, "feedback": parsed, "raw": full_text})


@app.post("/api/composition/rewrite")
async def rewrite(req: RewriteRequest, authorization: str = Header(...)):
    verify_token(authorization)
    messages = [
        {"role": "system", "content": COMPOSITION_REWRITE_PROMPT},
        {"role": "user", "content": req.text},
    ]
    full_text = ""
    async for delta in stream_chat(messages, temperature=0.7):
        full_text += delta
    return {"ok": True, "rewritten": full_text}


def _safe_json(text: str):
    """稳健解析：剥掉 ```json 包裹、截取首个 { 到最后一个 }。"""
    if not text:
        return None
    cleaned = text.strip()
    # 不用 removeprefix/removesuffix，兼容 Python 3.8
    if cleaned.startswith("```"):
        cleaned = cleaned[7:] if cleaned.startswith("```json") else cleaned[3:]
        if cleaned.endswith("```"):
            cleaned = cleaned[:-3]
        cleaned = cleaned.strip()
    start, end = cleaned.find("{"), cleaned.rfind("}")
    if start == -1 or end == -1:
        return None
    try:
        return json.loads(cleaned[start:end + 1])
    except json.JSONDecodeError:
        return None
