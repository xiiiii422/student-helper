# KaTeX 本地资源

`MathText` 组件通过 `WebView` 加载本目录下的 KaTeX 资源来离线渲染数学公式（LaTeX）。

## 放置步骤

在本目录（`app/src/main/assets/`）运行：

```powershell
./fetch_katex.ps1
```

脚本会把以下文件下载到 `assets/katex/`：

```
assets/katex/
├── katex.min.css
├── katex.min.js
├── auto-render.min.js
└── fonts/            # CSS 里引用的所有字体
```

## 手动方式

也可以从 https://github.com/KaTeX/KaTeX/releases 下载 `katex.tar.gz`，
解压后把 `dist/` 里的内容放进 `assets/katex/`。

## 许可证

KaTeX 采用 MIT 许可证，随库分发的 `LICENSE` 需一并保留。

> 若不需要数学公式渲染（例如暂时跳过 M3），可先不放置这些资源，
> `MathText` 会显示原始 `\( \)` 文本但不崩溃。
