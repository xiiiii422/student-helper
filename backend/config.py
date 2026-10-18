"""环境变量与配置读取（多供应商：GLM 主模型 + GLM-V 多模态辅助，兼容任何 OpenAI 格式服务）。"""
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    # ── 文本主模型（例：智谱 glm-4.7-flash，免费）──
    chat_api_key: str
    chat_base_url: str = "https://open.bigmodel.cn/api/paas/v4"
    chat_model: str = "glm-4.7-flash"
    chat_max_tokens: int = 4000

    # ── 多模态辅助模型（例：智谱 glm-4v-flash，免费；KEY/URL 留空复用 chat 配置）──
    #     注意：glm-4v-flash 输出上限 1024
    vl_api_key: str = ""
    vl_base_url: str = ""
    vl_model: str = "glm-4v-flash"
    vl_max_tokens: int = 1024

    # App 端固定 Bearer Token
    backend_secret_token: str

    # 行为参数
    max_history_turns: int = 8        # 保留最近 8 对对话
    request_timeout: int = 120        # 秒
    max_retries: int = 4              # 429/5xx 退避重试次数（免费模型高峰限流常见）

    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    @property
    def effective_vl_api_key(self) -> str:
        return self.vl_api_key or self.chat_api_key

    @property
    def effective_vl_base_url(self) -> str:
        return self.vl_base_url or self.chat_base_url


settings = Settings()
