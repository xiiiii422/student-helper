package com.example.studenthelper.ui.components

import android.annotation.SuppressLint
import android.graphics.Color as AndroidColor
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.compose.foundation.layout.height
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import com.example.studenthelper.core.util.MarkdownLite

/**
 * 使用本地 assets/katex/ 资源渲染含 LaTeX 的数学文本。
 * 行内公式 \( ... \)，独立公式 \[ ... \]。
 *
 * 依赖：app/src/main/assets/katex/ 下需放置 katex.min.css、katex.min.js、
 * auto-render.min.js 与 fonts/ 目录（见 assets/katex/README.md 与 fetch_katex.ps1）。
 *
 * 高度：WebView 不会按内容撑高，交给 Compose 会按视口截断（长答案最后一行被切一半）。
 * 这里页面加载完再回读 body.scrollHeight，把 CSS px 原样当 dp 用（viewport 是 device-width，1:1）。
 */
@SuppressLint("SetJavaScriptEnabled")
@Composable
fun MathText(
    content: String,
    modifier: Modifier = Modifier,
    color: androidx.compose.ui.graphics.Color = androidx.compose.ui.graphics.Color(0xFF2D3142),
) {
    val context = LocalContext.current
    val html = remember(content) { buildHtml(content, color.toArgb()) }
    var cssHeight by remember(html) { mutableIntStateOf(0) }

    AndroidView(
        modifier = modifier.then(if (cssHeight > 0) Modifier.height(cssHeight.dp) else Modifier),
        factory = { ctx ->
            HeightWebView(ctx).apply {
                settings.javaScriptEnabled = true
                settings.allowFileAccess = true
                settings.allowContentAccess = true
                settings.domStorageEnabled = true
                setBackgroundColor(AndroidColor.TRANSPARENT)
                isVerticalScrollBarEnabled = false
                settings.useWideViewPort = true
                settings.loadWithOverviewMode = true
                webViewClient = object : WebViewClient() {
                    override fun onPageFinished(view: WebView, url: String?) {
                        // KaTeX 字体是异步换的，首帧高度会偏小，量两次
                        view.postDelayed({ (view as HeightWebView).measureHeight() }, 120)
                        view.postDelayed({ (view as HeightWebView).measureHeight() }, 420)
                    }
                }
            }
        },
        update = { webView ->
            // factory 只跑一次，而 cssHeight 随 content 换了一个新 state，所以回调得每次重新接
            webView.onHeight = { cssHeight = it }
            // AndroidView 的 update 会随父级重组反复触发，而 loadDataWithBaseURL 是整页重载，
            // 列表回滚/滚动时会造成白屏闪一下。同一份 HTML 只加载一次。
            if (webView.tag != html) {
                webView.tag = html
                webView.lastHeight = 0
                cssHeight = 0
                webView.loadDataWithBaseURL(
                    "file:///android_asset/katex/", html, "text/html", "utf-8", null
                )
            }
        },
    )
}

/** 会把自身内容高度回传给 Compose 的 WebView（WebView 不会自己撑高，长答案会被截一截）。 */
private class HeightWebView(context: android.content.Context) : WebView(context) {
    var onHeight: ((Int) -> Unit)? = null
    var lastHeight = 0

    /** 回读 CSS px；量到 0（页面未就绪）时保持原样，不把自己压成一条线。 */
    fun measureHeight() {
        evaluateJavascript(
            "(function(){var b=document.body;return b?Math.ceil(b.scrollHeight):0;})();"
        ) { value ->
            val px = value?.trim('"')?.toIntOrNull() ?: 0
            if (px > 0 && px != lastHeight) {
                lastHeight = px
                onHeight?.invoke(px)
            }
        }
    }
}

private fun buildHtml(content: String, argb: Int): String {
    val cssColor = String.format("#%06X", 0xFFFFFF and argb)
    val htmlBody = MarkdownLite.toHtml(content)
    // 中文禁则（标点不许出现在行首）在 Blink 里只有识别到 CJK 语言才生效，所以 lang 必须写
    return """
        <!DOCTYPE html>
        <html lang="zh-CN"><head>
        <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
        <link rel="stylesheet" href="katex.min.css">
        <script src="katex.min.js"></script>
        <script src="auto-render.min.js"></script>
        <style>
          html,body{margin:0;padding:0;background:transparent;}
          /* 不给 body 设 overflow-wrap：它会为了塞下长词而硬拆，把“）。”这类收尾标点甩到行首；
             中文本来每两个字之间都有断点，只有 code 这种长串才需要强行可断。
             line-break:strict 实测不生效，反而会把整句的断点吞掉（行尾留一大块空白），禁则改由 MarkdownLite 保证 */
          body{font-size:16px;line-height:1.85;color:$cssColor;
            font-family:sans-serif;-webkit-text-size-adjust:100%;}
          /* KaTeX 默认 1.21em 会把行高撑开、中文标点挤到下一行，收敛到接近正文字号 */
          .katex{font-size:1.06em;line-height:1.1;}
          .katex-display{margin:8px 0;overflow-x:auto;overflow-y:hidden;padding:2px 0;}
          code{font-family:monospace;font-size:0.94em;overflow-wrap:break-word;}
          /* MarkdownLite 把「前一个词 + 收尾标点」包进这个 span，避免“。”单独成行 */
          .nw{white-space:nowrap;}
          /* 600 比 Compose 侧 FontWeight.Bold(700) 弱，两条渲染路径同一句话字重会不一致 */
          b,strong{font-weight:700;}
          p{margin:0 0 2px 0;}
        </style>
        </head><body>$htmlBody
        <script>
          renderMathInElement(document.body, {delimiters:[
            {left:"\\[", right:"\\]", display:true},
            {left:"\\(", right:"\\)", display:false}
          ]});
        </script>
        </body></html>
    """.trimIndent()
}
