# 学习小助手 · StudentHelper

面向**小学六年级**学生的自用版学习辅助 App：语文 / 数学 / 英语三科试题讲解 + 作文批改。
本地 OCR（Google ML Kit 中文 bundled 版）+ 直连免费大模型（智谱 GLM，可切 DeepSeek），数据全部存本机，不依赖电脑。

## 目录结构

```
小学做题agent/
├── android/          # Kotlin + Jetpack Compose 客户端（直连大模型，Room 本地存储）
└── backend/          # 可选：FastAPI 中转代理（仅在分发 APK 给他人时需要，藏 Key 防滥用）
```

## 核心特性

- **三科独立分栏**：语文 / 数学 / 英语各自聊天历史，互不干扰
- **作文独立专栏**：多图提交 → 结构化批改（评分/优点/问题/建议/好句升级/范文）
- **本地 OCR + 视觉模型兜底**：ML Kit 先识别，多行阅读版式/低置信/含公式时自动带图走视觉模型
- **手写板**：屏幕手写题目 → 走同一套 OCR 路由
- **错题本**：一键收藏，按学科筛选
- **LaTeX 渲染**：数学公式用 KaTeX 离线渲染
- **数据导出/导入**：zip 打包 db + 图片，换机不丢数据
- **无账号、直连大模型**：单人自用，装上即用，电脑可关机

## 快速开始（直连模式，装上即用）

App 已预埋免费模型配置（智谱 glm-4.7-flash 讲题 + glm-4v-flash 看图），**不依赖电脑、不需同 Wi-Fi、4G 也能用**。

### 第 1 步：安装
手机开 USB 调试连线，运行：
```powershell
.\install.ps1
```
（改过代码后先 `./build_apk.ps1` 重新打包）

### 第 2 步（可选）：换模型
「我的 → 模型服务设置」：预设芯片一键切换 智谱 GLM / DeepSeek（两个 Key 都已内置），或自定义任意 OpenAI 兼容接口；「连接测试」可验证。

### 第 3 步：使用
直接拍照/打字/手写提问。数据全部存手机本地，可在「我的」导出 zip 备份。

<details>
<summary>可选：自建后端中转（仅分发 APK 给他人时需要）</summary>

`backend/` 保留完整 FastAPI 代理（含 docs/DEPLOY.md 部署文档）。
当前 App 为直连架构；如需恢复中转模式，把 App「模型服务设置」的 Base URL 指向自建后端即可（后端已兼容 OpenAI 格式转发）。
</details>

## 架构总览

```
Android (Compose + Room 本地存)
   │  本地 ML Kit OCR（离线）→ 置信度/版式路由
   │
   ├─ 纯文字题 ─────────▶ glm-4.7-flash（免费文本）
   └─ 拍照/手写题 ───────▶ glm-4v-flash（免费视觉）
        （OpenAI 兼容接口，拥塞自动退避重试；可在 App 内切换 DeepSeek）
```

> `backend/` 为可选的 FastAPI 中转代理，仅在分发 APK 给他人时需要（藏 Key）。

## 文档

- [后端部署](docs/DEPLOY.md)
- [API 契约](docs/API.md)
- [常见问题排查](docs/TROUBLESHOOTING.md)

## 免责

自用项目，API Key 明文存于本机与 APK（自用版设计），请勿公开分发 APK。
