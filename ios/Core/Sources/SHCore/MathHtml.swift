import Foundation

/// KaTeX 渲染页的 HTML 外壳，与安卓 `ui/components/MathText.kt` 的 buildHtml 同一份模板。
///
/// 两端共用一个模板而不是各写一份，是因为这里的每条 CSS 都对应一次真机回归：
/// 行高、字重、nowrap、overflow-wrap 任何一处不一致，iOS 和安卓的同一条答案就会长得不一样。
public enum MathHtml {

    /// `colorHex` 形如 "#1D2129"，由调用方从语义色板换算，避免把颜色写死在模板里。
    public static func document(content: String, colorHex: String) -> String {
        let body = MarkdownLite.toHtml(content)
        return #"""
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
          body{font-size:16px;line-height:1.85;color:\#(colorHex);
            font-family:-apple-system,"PingFang SC","Heiti SC",sans-serif;-webkit-text-size-adjust:100%;}
          /* KaTeX 默认 1.21em 会把行高撑开、中文标点挤到下一行，收敛到接近正文字号 */
          .katex{font-size:1.06em;line-height:1.1;}
          .katex-display{margin:8px 0;overflow-x:auto;overflow-y:hidden;padding:2px 0;}
          code{font-family:ui-monospace,Menlo,monospace;font-size:0.94em;overflow-wrap:break-word;}
          /* MarkdownLite 把「前一个词 + 收尾标点」包进这个 span，避免“。”单独成行 */
          .nw{white-space:nowrap;}
          /* 600 比 SwiftUI .bold(700) 弱，两条渲染路径同一句话字重会不一致 */
          b,strong{font-weight:700;}
          p{margin:0 0 2px 0;}
        </style>
        </head><body>\#(body)
        <script>
          renderMathInElement(document.body, {delimiters:[
            {left:"\\[", right:"\\]", display:true},
            {left:"\\(", right:"\\)", display:false}
          ]});
        </script>
        </body></html>
        """#
    }

    /// 回读内容高度用的 JS。WebView 不会自己撑高，量到 0（页面未就绪）时调用方要保持原样，
    /// 不能把自己压成一条线。
    public static let heightProbe =
        "(function(){var b=document.body;return b?Math.ceil(b.scrollHeight):0;})();"

    /// SRGB 颜色 → "#RRGGBB"，与安卓 String.format("#%06X", ...) 同结果。
    public static func hexColor(red: Double, green: Double, blue: Double) -> String {
        let r = Int((max(0, min(1, red)) * 255).rounded())
        let g = Int((max(0, min(1, green)) * 255).rounded())
        let b = Int((max(0, min(1, blue)) * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
