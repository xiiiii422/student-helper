# Backend · StudentHelper

FastAPI 无状态代理：保管 DeepSeek API Key、拼装三科/作文 Prompt、流式（SSE）转发。
**不落任何数据库**，重启不丢数据（因为本就不存）。

## 文件

| 文件 | 职责 |
|---|---|
| `main.py` | 路由：`/health` `/api/chat` `/api/composition` `/api/composition/rewrite` |
| `config.py` | 环境变量读取（pydantic-settings） |
| `schemas.py` | Pydantic 请求/响应模型 |
| `prompts.py` | 语文/数学/英语 System Prompt + 作文批改 + 段落改写 |
| `llm_client.py` | 多供应商 LLM 流式调用（OpenAI 格式，双通道+退避重试） |
| `Dockerfile` | 容器化构建 |

## 本地运行

要求 Python 3.11+。

```bash
python -m venv .venv
source .venv/bin/activate          # Windows: .venv\Scripts\activate
pip install -r requirements.txt
cp .env.example .env                # 编辑 .env 填入真实值
uvicorn main:app --reload --port 8000
```

健康检查：

```bash
curl http://localhost:8000/health
# {"status":"ok","model":"glm-4.7-flash+glm-4v-flash"}
```

## 环境变量

| 变量 | 说明 |
|---|---|
| `CHAT_API_KEY` | 文本主模型密钥，**只存后端** |
| `CHAT_BASE_URL` | 默认 `https://open.bigmodel.cn/api/paas/v4` |
| `CHAT_MODEL` | 文本模型名，默认 `glm-4.7-flash`（免费） |
| `CHAT_MAX_TOKENS` | 文本通道输出上限，默认 4000 |
| `VL_MODEL` | 多模态模型名，默认 `glm-4v-flash`（免费，输出上限 1024） |
| `VL_MAX_TOKENS` | 视觉通道输出上限，默认 1024（glm-4v-flash 硬限制） |
| `VL_API_KEY` / `VL_BASE_URL` | 可选；留空则复用 CHAT 配置（同账号双模型） |
| `MAX_RETRIES` | 429/5xx/智谱1305拥塞退避重试次数，默认 4 |
| `BACKEND_SECRET_TOKEN` | App 端固定 Bearer Token，务必改成随机长串 |
| `MAX_HISTORY_TURNS` | 传给模型的对话轮数上限，默认 8 |
| `REQUEST_TIMEOUT` | 秒，默认 120 |

## 多模态与双通道

`llm_client.stream_chat` 在 `image_base64` 非空时自动切到 VL 通道（glm-4v-flash），
把最后一条 user 消息改造成 OpenAI 兼容的 `content` 数组（text + image_url data URL）；
纯文字请求走 CHAT 通道（glm-4.7-flash，推理型，思考内容 reasoning_content 不会转发到 UI）。
免费模型高峰拥塞（429/1305）会自动指数退避重试。换回 DeepSeek 只需改 `.env` 三项 base URL/KEY/模型名。

## Docker

```bash
docker build -t student-helper-backend .
docker run --rm -p 8000:8000 --env-file .env student-helper-backend
```
