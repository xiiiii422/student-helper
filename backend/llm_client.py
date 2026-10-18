"""LLM API 封装（OpenAI 兼容，多供应商）：
- 无图 → chat 模型（glm-4.7-flash）
- 有图 → vl 模型（glm-4.6v-flash）
- 429/5xx/智谱 1305 高峰拥塞 → 指数退避重试
"""
import asyncio
import json
from typing import AsyncIterator, List, Optional

import httpx

from config import settings

RETRY_STATUS = {429, 500, 502, 503, 504}


def _pick_endpoint(has_image: bool):
    if has_image:
        return (
            settings.effective_vl_base_url,
            settings.effective_vl_api_key,
            settings.vl_model,
            settings.vl_max_tokens,
        )
    return settings.chat_base_url, settings.chat_api_key, settings.chat_model, settings.chat_max_tokens


def _body_says_busy(body_text: str) -> bool:
    """智谱免费模型高峰返回 HTTP 200 但 body 里带 1305/拥塞错误，也要重试。"""
    return '"1305"' in body_text or "拥塞" in body_text or "稍后再试" in body_text


async def stream_chat(
    messages: List[dict],
    images: Optional[List[str]] = None,
    temperature: float = 0.3,
) -> AsyncIterator[str]:
    """流式调用，yield 增量文本（只转发 content，忽略 reasoning_content）。

    images 非空时把最后一条 user 消息改造成多模态 content 数组（文字在前，多张图按顺序在后）。
    """
    base_url, api_key, model, max_tokens = _pick_endpoint(bool(images))
    url = f"{base_url}/chat/completions"
    headers = {"Authorization": f"Bearer {api_key}", "Content-Type": "application/json"}

    msgs = [dict(m) for m in messages]
    if images:
        for i in range(len(msgs) - 1, -1, -1):
            if msgs[i]["role"] == "user":
                msgs[i]["content"] = [
                    {"type": "text", "text": _to_plain_text(msgs[i]["content"])},
                ] + [
                    {"type": "image_url", "image_url": {
                        "url": f"data:image/jpeg;base64,{img}"
                    }}
                    for img in images
                ]
                break

    payload = {
        "model": model,
        "messages": msgs,
        "stream": True,
        "temperature": temperature,
        "max_tokens": max_tokens,
    }

    last_error = "未知错误"
    async with httpx.AsyncClient(timeout=settings.request_timeout) as client:
        for attempt in range(1, settings.max_retries + 1):
            emitted = False  # 已开始吐字则不重试，避免重复内容
            try:
                async with client.stream("POST", url, headers=headers, json=payload) as resp:
                    if resp.status_code in RETRY_STATUS:
                        body = await resp.aread()
                        last_error = f"{resp.status_code}: {body.decode('utf-8', 'ignore')[:160]}"
                        if attempt < settings.max_retries:
                            await asyncio.sleep(min(2 ** attempt, 15))
                            continue
                        raise RuntimeError(f"模型服务繁忙（{last_error}），请稍后再试")

                    if resp.status_code != 200:
                        body = await resp.aread()
                        raise RuntimeError(
                            f"HTTP {resp.status_code}: {body.decode('utf-8', 'ignore')[:200]}"
                        )

                    async for line in resp.aiter_lines():
                        if not line.startswith("data:"):
                            continue
                        data = line[5:].strip()
                        if data == "[DONE]":
                            return
                        try:
                            chunk = json.loads(data)
                        except json.JSONDecodeError:
                            continue

                        # body 级拥塞错误（可能是 200 + error 字段）
                        if chunk.get("error"):
                            err_text = json.dumps(chunk["error"], ensure_ascii=False)
                            if _body_says_busy(err_text) and attempt < settings.max_retries and not emitted:
                                last_error = err_text[:160]
                                await asyncio.sleep(min(2 ** attempt, 15))
                                break
                            raise RuntimeError(f"模型返回错误: {err_text[:200]}")

                        delta = (chunk.get("choices") or [{}])[0].get("delta", {}).get("content", "")
                        if delta:
                            emitted = True
                            yield delta
                    else:
                        return  # 正常读完
            except httpx.TimeoutException:
                last_error = "请求超时"
                if attempt < settings.max_retries and not emitted:
                    await asyncio.sleep(min(2 ** attempt, 15))
                    continue
                raise RuntimeError("模型响应超时，请重试")


def _to_plain_text(content) -> str:
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        parts = [c.get("text", "") for c in content if isinstance(c, dict) and c.get("type") == "text"]
        return "\n".join(parts)
    return str(content)
