# 常见问题排查

## 后端

**Q: /health 返回 404 / 连不上**
- 确认服务已启动、端口映射正确、防火墙放行
- App 填的地址要含 `https://` 且末尾不带 `/`

**Q: 模型 401 / key 无效**
- 检查 `.env` 的 `CHAT_API_KEY`（智谱格式为 `xxxx.yyyy` 两段式）
- 重启容器使新 env 生效

**Q: 返回“模型服务繁忙，请稍后再试”**
- 免费模型（glm-4.7-flash / glm-4v-flash）高峰拥塞，已内置 4 次指数退避重试仍失败时触发
- 稍后重试，或在 `.env` 调大 `MAX_RETRIES`；也可换付费模型名

**Q: 流式无输出 / 一直转圈**
- 用 `curl -N` 直接打 `/api/chat` 看是否返回 `data:` 行
- Cloudflare Workers 免费版会缓冲，考虑 VPS 方案

**Q: 作文返回 ok=false**
- 模型没按 JSON 返回。看 `raw` 字段确认；已内置剥 ```` ```json ```` 与截取 `{...}` 兜底
- 提高 Prompt 约束或换更稳定模型

## Android

**Q: Gradle Sync 失败，缺 gradle-wrapper.jar**
- Android Studio 里 `File > Sync Project`，或终端 `gradle wrapper --gradle-version 8.9`

**Q: ML Kit 无法初始化 / 中文识别为空**
- 确认用的是 `com.google.mlkit:text-recognition-chinese`（bundled），非 play-services 版
- 首次识别会加载模型，稍等；低置信度会自动走图片兜底

**Q: 数学公式显示成 \( \) 原样文本**
- 没跑 `fetch_katex.ps1`，`assets/katex/` 缺文件。跑一次或手动放 KaTeX dist

**Q: 拍照崩溃 FileProvider 相关**
- 确认 `androidx.core.content.FileProvider` 已注册，`file_paths.xml` 的 `<files-path name="images" path="images/">`
  与实际保存目录一致（都在 `filesDir/images/`）

**Q: 换了后端地址不生效**
- 「我的」→「后端地址设置」保存后，DataStore 值优先于编译期默认值
- 确认地址末尾无斜杠（保存时已 removeSuffix("/")）

**Q: 导入 zip 后数据没变**
- 导入是覆盖 db 文件，**必须重启进程**才生效；点「导入完成·点我重启生效」

**Q: 图片越积越多占空间**
- 已按长边 1600px / JPEG 82% 压缩；「清空所有数据」会连带删除 images/

## 数据与备份

- 所有业务数据：`/data/data/com.example.studenthelper/databases/student_helper.db` + `files/images/`
- 导出 zip 落在 `files/exports/`，通过系统分享面板发到微信/网盘
- 卸载 App 会删除全部本机数据，**换机前先导出**
