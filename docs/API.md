# API 契约

Base URL：`https://<你的后端域名>`
鉴权：除 `/health` 外，所有接口需 Header `Authorization: Bearer <BACKEND_SECRET_TOKEN>`

---

## GET /health

响应：
```json
{ "status": "ok", "model": "glm-4.7-flash+glm-4v-flash" }
```

---

## POST /api/chat

学科讲解，**SSE 流式**。

请求：
```json
{
  "subject": "math",              // chinese | math | english
  "text": "小明有5个苹果…",
  "image_base64": null,           // 可选，无 data: 前缀的纯 base64
  "history": [
    { "role": "user", "content": "..." },
    { "role": "assistant", "content": "..." }
  ],
  "stream": true
}
```

响应（`Content-Type: text/event-stream`），每条：
```
data: {"delta": "【题目在考什么】\n"}

data: {"delta": "这是一道分数应用题。"}

data: {"done": true}
```
出错时：
```
data: {"error": "DeepSeek 429: rate limit"}
```

App 端解析：逐行读 `data:`，`delta` 追加到当前气泡；`done` 结束；`error` 弹提示。

---

## POST /api/composition

作文批改，**非流式**，一次性返回结构化 JSON。

请求：
```json
{
  "title": "我的妈妈",
  "grade": "六年级",
  "content": "妈妈是我最爱的人…",   // 可为 null，则从图片识别
  "images_base64": ["<base64>", "..."],  // 最多 4 张
  "requirement": "写人记叙文，600字"
}
```

响应：
```json
{
  "ok": true,
  "feedback": {
    "总分": 85,
    "分项": {"内容":22,"结构":20,"语言":22,"书写":21},
    "总评": "...",
    "优点": [{"位置":"开头","内容":"...","为什么好":"..."}],
    "问题": [{"位置":"第2段","类型":"病句","原句":"...","问题说明":"...","修改建议":"..."}],
    "改进建议": ["...", "...", "..."],
    "好句升级": [{"原句":"...","改写":"...","为什么更好":"..."}],
    "同类范文片段": "..."
  },
  "raw": "<模型原始文本>"
}
```
解析失败时 `ok=false, feedback=null`，App 展示 `raw` 并提供重试。

---

## POST /api/composition/rewrite

段落改写，非流式。

请求：`{ "text": "<要改写的段落>" }`
响应：`{ "ok": true, "rewritten": "【改写后】\n...\n\n【改了哪里】\n- ...\n\n【为什么这样改】\n..." }`
