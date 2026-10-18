package com.example.studenthelper.core.util

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class MarkdownLiteTest {

    /** 禁则包装会插进 <span class="nw">，测加粗/转义时先把它去掉，只看排版语义。 */
    private fun plain(html: String): String =
        html.replace("<span class=\"nw\">", "").replace("</span>", "")

    @Test
    fun `strip 去除加粗标题代码与分隔线`() {
        val md = "### 第一题\n**答案**是 `3/8`\n- 要点一\n---\n结束"
        val out = MarkdownLite.strip(md)
        assertEquals("第一题\n答案是 3/8\n• 要点一\n结束", out)
    }

    @Test
    fun `strip 不触碰 LaTeX`() {
        val latex = "面积公式 \\( S = \\pi r^2 \\)\n独立公式 \\[ \\frac{3}{4} \\]"
        assertEquals(latex, MarkdownLite.strip(latex))
    }

    @Test
    fun `toHtml 转换加粗标题并转义尖括号`() {
        val html = MarkdownLite.toHtml("### 标题\n**重点** <脚本> 内容")
        assertTrue(html.contains("<b>标题</b>"))
        assertTrue(html.contains("<b>重点</b>"))
        assertTrue(html.contains("&lt;脚本&gt;"))
        assertTrue(html.contains("<br>"))
    }

    @Test
    fun `toHtml 保留 LaTeX 反斜杠`() {
        val html = MarkdownLite.toHtml("答案是 \\( \\frac{3}{8} \\)")
        assertTrue(html.contains("\\( \\frac{3}{8} \\)"))
    }

    @Test
    fun `toAnnotated 输出纯文本内容一致`() {
        val a = MarkdownLite.toAnnotated("### 标题\n**重点**普通\n- 项目")
        assertEquals("标题\n重点普通\n• 项目", a.text)
    }

    @Test
    fun `公式后的孤立句号并回上一行`() {
        val raw = "第2步：把 1/2 变成 4 分母。 \\( \\frac{1\\times2}{2\\times2} = \\frac{2}{4} \\)\n。\n第3步：相加"
        val out = MarkdownLite.strip(raw)
        assertEquals(
            "第2步：把 1/2 变成 4 分母。 \\( \\frac{1\\times2}{2\\times2} = \\frac{2}{4} \\)。\n第3步：相加",
            out,
        )
        assertEquals(2, MarkdownLite.normalizedLines(raw).size)
    }

    @Test
    fun `行首括号不并行（避免打乱（1）（2）列点）`() {
        val raw = "【答案】\n（1）对\n（2）错"
        assertEquals(3, MarkdownLite.normalizedLines(raw).size)
    }

    @Test
    fun `收尾标点与前面的词锁在一起`() {
        // 公式后带空格再接句号：空格先被消掉，再把「公式。」锁成不折行整体
        val html = MarkdownLite.toHtml("写成 \\( \\frac{2}{5} \\) 。")
        assertTrue(html.contains("<span class=\"nw\">\\( \\frac{2}{5} \\)。</span>"))
        // 数字接全角括号：不能把“）。”单独甩到下一行
        assertTrue(MarkdownLite.toHtml("答：28.26 平方厘米（ 取 3.14）。").contains("<span class=\"nw\">3.14）。</span>"))
        // 只锁一个词，不会把整句吞进 nowrap
        assertFalse(MarkdownLite.toHtml("第1题考圆的面积公式。").contains("<span class=\"nw\">第1题考圆的面积公式。</span>"))
    }

    @Test
    fun `禁则不能把整句锁成一个不折行块`() {
        // 真机踩过：非贪婪的 \\(..\\) 会为了凑出后面的“）。”一路扩到行尾，
        // 整句变成 nowrap 后塞不下，被整体挤到下一行，行首留一大片空白。
        val line = "第1题：答：\\( 28.26 \\) 平方厘米（\\( \\pi \\) 取 \\( 3.14 \\)）。"
        val html = MarkdownLite.toHtml(line)
        html.split("<span class=\"nw\">").drop(1).forEach { piece ->
            val span = piece.substringBefore("</span>")
            assertTrue("nowrap 块过长：$span", span.length <= 20)
        }
        // 句号（连同一个全角右括号）仍跟着前面的公式，没被甩到行首
        assertTrue(html.contains("<span class=\"nw\">\\( 3.14 \\)）。</span>"))
        // 长算式保持可断：不把 40 字以上的公式包进 nowrap
        val long = "第3步：\\( S = 3.14 \\times 3 \\times 3 = 3.14 \\times 9 = 28.26 \\) 平方厘米。"
        assertFalse(MarkdownLite.toHtml(long).contains("<span class=\"nw\">\\( S ="))
    }

    @Test
    fun `禁则不破坏 LaTeX 与实体`() {
        val latex = "面积 \\( S = \\pi r^2 \\) 平方厘米"
        assertTrue(MarkdownLite.toHtml(latex).contains("\\( S = \\pi r^2 \\)"))
        assertTrue(plain(MarkdownLite.toHtml("a < b 与 & 符号")).contains("&lt;"))
    }

    @Test
    fun `分节标题单独成行时加粗`() {
        val html = MarkdownLite.toHtml("【答案】\n答：7/8\n【解题思路】")
        assertTrue(plain(html).contains("<b>【答案】</b>"))
        assertTrue(plain(html).contains("<b>【解题思路】</b>"))
        assertFalse(plain(html).contains("<b>答：7/8</b>"))
        val annotated = MarkdownLite.toAnnotated("【答案】\n答：7/8")
        assertTrue(
            annotated.spanStyles.any {
                it.item.fontWeight == androidx.compose.ui.text.font.FontWeight.Bold &&
                    annotated.text.substring(it.start, it.end) == "【答案】"
            }
        )
    }

    @Test
    fun `判别函数`() {
        assertTrue(MarkdownLite.containsMarkdown("**加粗**"))
        assertTrue(MarkdownLite.containsMarkdown("### 标题"))
        assertFalse(MarkdownLite.containsMarkdown("【答案】普通文本"))
        assertTrue(MarkdownLite.containsLatex("公式 \\( x \\)"))
        assertFalse(MarkdownLite.containsLatex("无公式文本"))
    }
}
