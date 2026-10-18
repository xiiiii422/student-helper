"""协议级 E2E 测试：本地 mock OpenAI 兼容服务 + 真实后端 HTTP 全链路。

用法（需后端 venv 依赖）：
    python tests/e2e_test.py
无需真实 API Key；全部断言通过时输出 ALL PASS 并退出码 0。
"""
import json
import os
import sys
import threading
import time
from pathlib import Path

BACKEND_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(BACKEND_DIR))

MOCK_PORT = 18001
BACKEND_PORT = 18000
TEST_TOKEN = "e2e-secret-token"

# ---- 必须在 import main 之前设置环境（与 config.py 字段同名）----
os.environ.update({
    "CHAT_API_KEY": "key-e2e-fake",
    "CHAT_BASE_URL": f"http://127.0.0.1:{MOCK_PORT}",
    "CHAT_MODEL": "glm-e2e-chat",
    "VL_MODEL": "glm-e2e-vl",
    "BACKEND_SECRET_TOKEN": TEST_TOKEN,
    "MAX_HISTORY_TURNS": "8",
})

import httpx  # noqa: E402
import uvicorn  # noqa: E402
from fastapi import FastAPI  # noqa: E402
from fastapi.responses import JSONResponse, StreamingResponse  # noqa: E402

# ─────────────────────────── mock LLM ───────────────────────────
MOCK_STATE = {"last": None, "bad_json": False}

FEEDBACK_FIXTURE = {
    "总分": 85,
    "分项": {"内容": 22, "结构": 20, "语言": 22, "书写": 21},
    "总评": "叙事真挚，细节动人。",
    "优点": [{"位置": "开头", "内容": "点题快", "为什么好": "开门见山"}],
    "问题": [{"位置": "第2段", "类型": "病句", "原句": "很美丽的花", "问题说明": "多余的很", "修改建议": "美丽的花"}],
    "改进建议": ["第2段加入外貌描写"],
    "好句升级": [{"原句": "妈妈笑了", "改写": "妈妈的笑像春天的风", "为什么更好": "用了比喻"}],
    "同类范文片段": "她系着围裙在厨房忙碌。",
}

CHAT_CHUNKS = ["【题目在考什么】\n", "这是一道分数应用题。", "【完】"]
REWRITE_CHUNKS = ["【改写后】\n她笑起来像春天的风。", "  ", "【改了哪里】\n- 用了比喻"]

mock_app = FastAPI()


@mock_app.get("/health")
async def mock_health():
    return {"mock": "ok"}


@mock_app.get("/__last__")
async def last_request():
    return JSONResponse(MOCK_STATE["last"] or {})


@mock_app.post("/__mode__")
async def set_mode(body: dict):
    MOCK_STATE["bad_json"] = bool(body.get("bad_json", False))
    return {"mode": MOCK_STATE["bad_json"]}


@mock_app.post("/chat/completions")
async def completions(req: dict):
    MOCK_STATE["last"] = req
    system_txt = ""
    for m in req.get("messages", []):
        if m["role"] == "system":
            system_txt = m["content"] if isinstance(m["content"], str) else ""
            break

    if "批改六年级作文" in system_txt:
        chunks = [json.dumps(FEEDBACK_FIXTURE, ensure_ascii=False)]
        if MOCK_STATE["bad_json"]:
            chunks = ["这显然不是JSON {{{", "乱七八糟"]
    elif "一段作文" in system_txt:
        chunks = REWRITE_CHUNKS
    else:
        chunks = CHAT_CHUNKS

    async def sse():
        for c in chunks:
            payload = {"choices": [{"delta": {"content": c}, "index": 0}]}
            yield "data: " + json.dumps(payload, ensure_ascii=False) + "\n\n"
        yield "data: [DONE]\n\n"

    return StreamingResponse(sse(), media_type="text/event-stream")


# ─────────────────────────── 测试执行 ───────────────────────────
RESULTS = []


def check(name: str, cond: bool, detail: str = ""):
    RESULTS.append((name, cond, detail))
    mark = "PASS" if cond else "FAIL"
    print(f"[{mark}] {name}" + (f"  <- {detail}" if (not cond and detail) else ""))


def wait_health(base: str, timeout_s: float = 30.0) -> bool:
    deadline = time.time() + timeout_s
    while time.time() < deadline:
        try:
            if httpx.get(base + "/health", timeout=2).status_code == 200:
                return True
        except Exception:
            pass
        time.sleep(0.3)
    return False


def sse_collect(payload: dict, token: str = TEST_TOKEN):
    text, done, err = "", False, None
    with httpx.stream(
        "POST", f"http://127.0.0.1:{BACKEND_PORT}/api/chat",
        json=payload, headers={"Authorization": f"Bearer {token}"}, timeout=30,
    ) as r:
        if r.status_code != 200:
            r.read()
            return "", False, f"HTTP {r.status_code}", r.status_code
        for line in r.iter_lines():
            if not line.startswith("data:"):
                continue
            d = line[5:].strip()
            obj = json.loads(d)
            if obj.get("delta"):
                text += obj["delta"]
            if obj.get("done"):
                done = True
            if obj.get("error"):
                err = obj["error"]
    return text, done, err, r.status_code


def mock_last() -> dict:
    return httpx.get(f"http://127.0.0.1:{MOCK_PORT}/__last__", timeout=5).json()


def main():
    mock_cfg = uvicorn.Config(mock_app, host="127.0.0.1", port=MOCK_PORT, log_level="warning")
    mock_server = uvicorn.Server(mock_cfg)
    threading.Thread(target=mock_server.run, daemon=True).start()

    import main as backend_main  # noqa: WPS433
    be_cfg = uvicorn.Config(backend_main.app, host="127.0.0.1", port=BACKEND_PORT, log_level="warning")
    be_server = uvicorn.Server(be_cfg)
    threading.Thread(target=be_server.run, daemon=True).start()

    if not wait_health(f"http://127.0.0.1:{BACKEND_PORT}"):
        print("FATAL: 后端未能启动")
        sys.exit(2)
    if not wait_health(f"http://127.0.0.1:{MOCK_PORT}"):
        print("FATAL: mock 未能启动")
        sys.exit(2)
    print("── 服务就绪，开始断言 ──")

    # T1 鉴权
    r = httpx.post(
        f"http://127.0.0.1:{BACKEND_PORT}/api/chat",
        json={"subject": "math", "text": "1+1"},
        headers={"Authorization": "Bearer wrong"}, timeout=10,
    )
    check("T1 错误Token → 401", r.status_code == 401, f"got {r.status_code}")

    # T2 非法 subject → 422
    r = httpx.post(
        f"http://127.0.0.1:{BACKEND_PORT}/api/chat",
        json={"subject": "biology", "text": "x"},
        headers={"Authorization": f"Bearer {TEST_TOKEN}"}, timeout=10,
    )
    check("T2 非法学科 → 422", r.status_code == 422, f"got {r.status_code}")

    # T3 纯文字流式 + Prompt/历史截断
    hist = [{"role": "user" if i % 2 == 0 else "assistant", "content": f"msg{i}"} for i in range(20)]
    text, done, err, _ = sse_collect({"subject": "math", "text": "小红有3个苹果", "history": hist})
    check("T3a 流式内容与 mock 拼接一致", text == "".join(CHAT_CHUNKS), f"got {text!r} err={err}")
    check("T3b 收到 done 帧", done)
    last = mock_last()
    msgs = last["messages"]
    check("T3c system=数学老师Prompt", msgs[0]["role"] == "system" and msgs[0]["content"].startswith("你是一位耐心温柔的小学六年级数学老师"))
    check("T3d 历史截断至16条(总18=1sys+16hist+1user)", len(msgs) == 18, f"got {len(msgs)}")
    check("T3e user 为最新消息", msgs[-1]["role"] == "user" and msgs[-1]["content"] == "小红有3个苹果")
    check("T3f 文本模型+temperature0.3", last["model"] == "glm-e2e-chat" and last["temperature"] == 0.3)

    # T4 多模态改造：单图
    _, _, _, _ = sse_collect({"subject": "math", "text": "看图解题", "image_base64": "AAAA1234"})
    last = mock_last()
    um = last["messages"][-1]
    check("T4a 多模态 model 切换", last["model"] == "glm-e2e-vl", f"got {last['model']}")
    check("T4b content 为数组", isinstance(um["content"], list) and len(um["content"]) == 2)
    if isinstance(um["content"], list):
        parts = um["content"]
        check("T4c text+image_url 结构正确",
              parts[0]["type"] == "text" and parts[0]["text"] == "看图解题"
              and parts[1]["type"] == "image_url"
              and parts[1]["image_url"]["url"].startswith("data:image/jpeg;base64,AAAA1234"))

    # T5 三科 Prompt 选择
    for subj, head in [("chinese", "小语"), ("english", "小英")]:
        sse_collect({"subject": subj, "text": "题"})
        last = mock_last()
        check(f"T5 {subj} 使用对应老师Prompt", head in last["messages"][0]["content"])

    # T6 作文批改：结构化 JSON 解析成功
    r = httpx.post(
        f"http://127.0.0.1:{BACKEND_PORT}/api/composition",
        json={"title": "我的妈妈", "content": "妈妈很爱我" * 20},
        headers={"Authorization": f"Bearer {TEST_TOKEN}"}, timeout=30,
    )
    body = r.json()
    check("T6a 批改 ok", body["ok"] is True)
    fb = body["feedback"] or {}
    check("T6b 中文字段完整", fb.get("总分") == 85 and len(fb.get("优点", [])) == 1 and len(fb.get("问题", [])) == 1
          and fb.get("分项", {}).get("内容") == 22)
    last = mock_last()
    check("T6c 作文 user 含标题/正文", "作文标题：我的妈妈" in last["messages"][1]["content"] and "作文正文" in last["messages"][1]["content"])

    # T6d 多图：4 页手稿全部出现在 content 数组（多图回归）
    r = httpx.post(
        f"http://127.0.0.1:{BACKEND_PORT}/api/composition",
        json={"title": "两页作文", "images_base64": ["IMG1", "IMG2", "IMG3", "IMG4"]},
        headers={"Authorization": f"Bearer {TEST_TOKEN}"}, timeout=30,
    )
    last = mock_last()
    user_content = last["messages"][1]["content"]
    ok_multi = (
        isinstance(user_content, list)
        and sum(1 for p in user_content if p.get("type") == "image_url") == 4
        and [p["image_url"]["url"] for p in user_content if p.get("type") == "image_url"][0]
            .endswith("base64,IMG1")
    )
    check("T6d 作文多图全部上传(4张)", ok_multi, f"got {str(user_content)[:120]}")

    # T7 作文坏 JSON 降级
    httpx.post(f"http://127.0.0.1:{MOCK_PORT}/__mode__", json={"bad_json": True}, timeout=5)
    r = httpx.post(
        f"http://127.0.0.1:{BACKEND_PORT}/api/composition",
        json={"title": "t", "content": "c"},
        headers={"Authorization": f"Bearer {TEST_TOKEN}"}, timeout=30,
    )
    body = r.json()
    check("T7 坏JSON → ok=false 且 raw 保留", body["ok"] is False and body["feedback"] is None and "乱七八糟" in body["raw"])
    httpx.post(f"http://127.0.0.1:{MOCK_PORT}/__mode__", json={"bad_json": False}, timeout=5)

    # T8 段落改写：temperature 0.7
    r = httpx.post(
        f"http://127.0.0.1:{BACKEND_PORT}/api/composition/rewrite",
        json={"text": "妈妈笑了"},
        headers={"Authorization": f"Bearer {TEST_TOKEN}"}, timeout=30,
    )
    body = r.json()
    check("T8a 改写返回文本", body["ok"] is True and "【改写后】" in body["rewritten"])
    last = mock_last()
    check("T8b 改写 temperature=0.7", last["temperature"] == 0.7, f"got {last['temperature']}")
    check("T8c 改写使用专用Prompt", "一段作文" in last["messages"][0]["content"])

    # 汇总
    failed = [n for n, ok, _ in RESULTS if not ok]
    print("─" * 42)
    print(f"共 {len(RESULTS)} 项断言，失败 {len(failed)} 项")
    if failed:
        for n in failed:
            print("  FAILED:", n)
        sys.exit(1)
    print("ALL PASS")


if __name__ == "__main__":
    main()
