# iOS 版（iPhone 14）

安卓版的原生移植：SwiftUI + 本地 KaTeX + 直连大模型，界面与功能对齐 `android/`，
另加三项 iOS 特性：**答完朗读**、**语文生成作文**、**Key 存钥匙串**。

## 目录结构

```
ios/
├─ project.yml            XcodeGen 工程描述（.xcodeproj 不入库，现生成）
├─ Secrets.example.xcconfig  复制成 Secrets.xcconfig 填 Key（已 gitignore）
├─ Core/                  纯逻辑 Swift Package，只 import Foundation
│  └─ Sources/SHCore/     MarkdownLite / Prompts / LlmPolicy / SseParser /
│                         SpeechText / CompositionFeedback / AppStore / Zip
└─ App/StudentHelper/     SwiftUI 界面 + 网络 + 语音 + OCR
```

**Core 单独成包的原因**：这台开发机是 Windows，没有 Xcode。排版、SSE 解析、
提示词、批改 JSON、zip 备份这些纯逻辑在 Windows/Linux 上都能 `swift test`，
于是错误能在花 macOS 构建额度之前就被挡掉；界面才交给云端模拟器验证。

## 没有 Mac 时的三条命令

```bash
# 1. 纯逻辑单测（本机 Linux 容器，免费额度）
cd ios/Core && swift test

# 2. 生成工程并构建（需要 macOS + Xcode 15+）
brew install xcodegen
cd ios && xcodegen generate
xcodebuild -project StudentHelper.xcodeproj -scheme StudentHelper \
  -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 14' build

# 3. 逐屏截图（CI 里自动做，见 .github/workflows/ios.yml）
xcrun simctl launch <UDID> com.example.studenthelper -uiTestScreen chatMath
xcrun simctl io <UDID> screenshot chatMath.png
```

## 装到 iPhone（无 Mac）

云端 `ipa` job 产出**未签名**包，本机签名有两条路：

| 方式 | 成本 | 有效期 | 需要电脑 |
|---|---|---|---|
| 付费开发者账号 + TestFlight | ¥688/年 | 90 天 | 不需要 |
| Sideloadly / AltServer + 免费 Apple ID | 0 | 7 天，到期重签 | 需要，且要装 Apple 设备驱动 |

免费账号的硬限制：同时最多 3 个自签 App；装完要在
「设置 → 通用 → VPN 与设备管理」里信任自己的 Apple ID；iOS 17+ 还要开「开发者模式」。

## 为什么没有手写板

早期版本有一个「手指写题」的手写板（还为此接了 ML Kit Digital Ink 做离线手写识别）。
实际使用后判掉了：小学生搜题就是拿起来拍一张，在手机屏上比划写字又慢又不准。
现在输入栏只保留**拍照**和**相册**两个入口，相关代码、CocoaPods 依赖和 ML Kit 框架已全部移除，
包体从 11 MB 回到 2 MB 以内，构建链也退回纯 XcodeGen + SwiftPM。


## 与安卓的差异

| 项目 | 安卓 | iOS |
|---|---|---|
| 存储 | Room | 单文件 JSON（`AppStore`），字段逐列对齐 |
| OCR | ML Kit | Vision（`zh-Hans` + `en-US`） |
| 公式 | WebView + 本地 KaTeX | WKWebView + 同一份 KaTeX 资源与 CSS |
| Key | 源码常量（历史遗留） | Keychain，`AfterFirstUnlockThisDeviceOnly` |
| 朗读 | 无 | `AVSpeechSynthesizer`，分句 + 中英切换音色 |
| 生成作文 | 无 | 语文页入口，见 `EssayViews.swift` |
| 长按 | 直接删除 | 上下文菜单（复制/朗读/收藏/删除） |

排版规则（中文禁则、公式行高、字重）两端共用 `Core/MarkdownLite` 与
`Core/MathHtml` 的同一份实现，改一处两边同时生效。
