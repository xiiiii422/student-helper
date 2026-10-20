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
        <meta charset="utf-8">
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
          /* 行内公式后面紧跟的中文收尾标点会被挤到下一行行首（真机截图确认过）。
             纯 CSS 的可靠做法：让行内公式本身成为一个不可断的原子，
             同时把紧随其后的标点拉回来——用 inline-block + 负的 margin-right 做不到，
             所以改成给行内公式的容器一个 nowrap 的伪元素占位不现实。
             最终采用：行内公式设 vertical-align，并让 body 允许在标点前断行的规则失效。 */
          .katex-display{margin:8px 0;overflow-x:auto;overflow-y:hidden;padding:2px 0;}
          /* 关键修复：中文禁则——句末标点不允许出现在行首。
             用 line-break:strict 太激进（会把整句断点吞掉），
             这里只针对「标点紧跟行内公式」这一种情况：把公式和它后面的标点
             用 CSS 的 nowrap 上下文包起来，由 JS 打标记 .nw-math。 */
          .nw-math{white-space:nowrap;}
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

          // KaTeX 渲染后 .katex 是 inline-block，浏览器会在它和紧跟的标点之间断行，
          // 结果「3.14」留在行尾、「）。」被挤到下一行开头（真机截图确认过）。
          // 这里遍历所有文本节点，把「以标点开头」的那一段连同前一个元素一起包进 nowrap。
          (function(){
            var PUNCT = /^[ \t]*[。，、；：！？”’—…）】》)\]]+/;
            var walker = document.createTreeWalker(
              document.body, NodeFilter.SHOW_TEXT, null, false
            );
            var targets = [];
            var n;
            while ((n = walker.nextNode())) {
              if (n.nodeValue && PUNCT.test(n.nodeValue)) targets.push(n);
            }
            targets.forEach(function(textNode){
              var prev = textNode.previousSibling;
              if (!prev || prev.nodeType !== 1) return;
              // 只处理「前面是公式」的情况，普通中文由 .nw 处理
              var mathEl = prev.classList && prev.classList.contains('katex')
                ? prev
                : (prev.querySelector && prev.querySelector('.katex'));
              if (!mathEl) return;
              var m = PUNCT.exec(textNode.nodeValue);
              if (!m) return;
              var punct = m[0].replace(/^[ \t]+/, '');
              textNode.nodeValue = textNode.nodeValue.slice(m[0].length);
              var wrap = document.createElement('span');
              wrap.className = 'nw-math';
              var parent = mathEl.parentNode;
              parent.insertBefore(wrap, mathEl);
              wrap.appendChild(mathEl);
              wrap.appendChild(document.createTextNode(punct));
            });
          })();
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
