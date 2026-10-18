# Android · StudentHelper

Kotlin + Jetpack Compose 客户端。单人自用，无账号；历史、作文、错题全部存本机 Room。

## 环境

- Android Studio Ladybug (2024.2) 或更新
- JDK 17
- 真机：小米 18 Pro（Android 15），minSdk 26

## 首次打开步骤

1. **用 Android Studio 打开 `android/` 目录**，等待 Gradle Sync。
   - 若提示缺少 Gradle Wrapper（`gradle-wrapper.jar`），在 Android Studio 里
     `File > Sync`，或命令行运行 `gradle wrapper --gradle-version 8.9` 生成。
2. **下载 KaTeX 资源**（数学公式渲染，可选但推荐）：
   ```powershell
   cd app/src/main/assets
   ./fetch_katex.ps1
   ```
   产物落在 `assets/katex/`。跳过则数学公式显示原始 `\( \)` 文本但不崩溃。
3. **配置后端地址与 Token**（二选一）：
   - 编译期：改 `app/build.gradle.kts` 里的 `DEFAULT_BACKEND_URL` / `DEFAULT_BACKEND_TOKEN`
   - 运行期：启动 App →「我的」→「后端地址设置」填入并保存（DataStore 覆盖默认值）
4. **构建运行**：
   ```bash
   ./gradlew assembleDebug
   adb install -r app/build/outputs/apk/debug/app-debug.apk
   ```

## 模块结构

```
com.example.studenthelper
├── core/           # common(Subject/Dispatcher), network(BackendClient/SSE/Settings), util(Bitmap/File/Date)
├── data/           # local(Room 实体/DAO/DB), repository(Chat/Composition/Favorite)
├── domain/         # ocr(OcrRouter/MlKit), composition(FeedbackParser), usecase(BackupManager)
├── di/             # CoreModule/DatabaseModule
└── ui/             # theme, navigation, components, {chinese,math,english}, shared(ChatScreen/VM), composition, favorites, me
```

## 关键实现点

- **OCR 路由**（`domain/ocr/OcrRouter`）：置信度 ≥0.9 且无公式特征 → 只发文字；
  0.6–0.9 → 文字+图片兜底；<0.6 → 纯图片多模态。数学学科额外检测公式/稀疏文本。
- **SSE 流式**（`core/network/BackendClient`）：OkHttp 手动按行解析 `data:` 前缀，
  逐段回调 UI 做打字机效果，边收边写 Room。
- **KaTeX**（`ui/components/MathText`）：WebView 加载本地 assets，`auto-render` 识别 `\( \)`。
- **数据备份**（`domain/usecase/BackupManager`）：zip 打包 db + images，导入后重启进程生效。

## ML Kit bundled 说明

依赖 `com.google.mlkit:text-recognition-chinese:16.0.1` 是 **bundled** 变体：
模型直接打进 APK（约 +15MB），**无需 Google Play Services**，国行小米可用。
不要误用 `com.google.android.gms:play-services-mlkit-*`（那是 unbundled，依赖 GMS）。

## 权限

INTERNET / CAMERA / READ_MEDIA_IMAGES。拍照用 `TakePicture` + FileProvider，
相册用 `PickVisualMedia`（照片选择器，无需全量存储权限）。
