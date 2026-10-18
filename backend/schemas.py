"""Pydantic 请求/响应模型，与 Android DTO 对齐。"""
from typing import Literal, Optional, List
from pydantic import BaseModel, Field

Subject = Literal["chinese", "math", "english"]
Role = Literal["user", "assistant"]


class ChatMessage(BaseModel):
    role: Role
    content: str


class ChatRequest(BaseModel):
    subject: Subject
    text: str = Field(..., description="用户输入或 OCR 识别后的文本")
    image_base64: Optional[str] = Field(None, description="无 base64 前缀的纯数据")
    history: List[ChatMessage] = Field(default_factory=list)
    stream: bool = True


class CompositionRequest(BaseModel):
    title: Optional[str] = ""
    grade: str = "六年级"
    content: Optional[str] = Field(None, description="作文文字，若为空则从图片识别")
    images_base64: List[str] = Field(default_factory=list, description="作文照片列表")
    requirement: Optional[str] = Field(None, description="作文题目要求，可选")


class RewriteRequest(BaseModel):
    text: str = Field(..., description="需要改写的段落")


class HealthResponse(BaseModel):
    status: str
    model: str
