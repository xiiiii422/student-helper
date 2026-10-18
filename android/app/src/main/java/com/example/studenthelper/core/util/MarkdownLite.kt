package com.example.studenthelper.core.util

import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.withStyle

/**
 * 轻量 Markdown 处理（无第三方依赖）：
 * 模型偶尔输出 **加粗**、### 标题、- 列表、`代码`、--- 分隔线，
 * 直接显示很粗糙。三种输出形态：
 * - strip：流式期间用，纯文本快速预览（去掉符号）
 * - toAnnotated：定稿气泡用，加粗/标题转 Span
 * - toHtml：KaTeX WebView 用，转 <b>/<br> 后再交给 KaTeX 渲染公式
 * 注意：所有转换都不触碰 LaTeX 定界符 \( \) \[ \] 与反斜杠命令。
 */
object MarkdownLite {

    private val BOLD = Regex("""\*\*(.+?)\*\*""")
    private val HEADING = Regex("""^\s{0,3}#{1,4}\s+(.*)$""")
    private val BULLET = Regex("""^\s*[-*•]\s+""")
    private val RULE = Regex("""^\s*(-{3,}|\*{3,})\s*$""")
    private val CODE = Regex("""`([^`]+)`""")

    /** 【题目在考什么】这类分节标题，单独成行时加粗，方便学生扫读。 */
    private val SECTION = Regex("""^\s*(【[^】]{2,14}】)\s*$""")

    /**
     * 中文行首标点：模型常在 LaTeX 公式后断开，导致“。”孤零零占一行。
     * 只含收尾类标点；故意不含“（”，因为“（1）xxx”是常见的合法换行项。
     */
    private val ORPHAN_PUNCT = Regex(
        """^[\u3002\uff0c\u3001\uff1b\uff1a\uff1f\uff01\u201d\u2019\u2014\u2026\uff09\u3011\u300b,;?!]"""
    )

    /** 公式与收尾标点之间多一个空格，浏览器就会把“。”单独折到下一行。 */
    private val SPACE_BEFORE_CLOSE = Regex("""\s+(?=[\u3002\uff0c\uff1b\uff1a\uff01\uff1f\uff09\u3011\u300b])""")

    /**
     * 中文禁则（标点不得出现在行首）不能指望渲染端：
     * WebView 实测 lang="zh-CN" + line-break:strict 无效，公式又是 atomic inline，禁则更管不到；
     * 本项目的 Compose 版本也没有 Text 的 lineBreak=LineBreak.Strict。
     * 这里直接把「前一个词 + 收尾标点」包成 nowrap，标点永远跟着前面的字走。
     *
     * 公式那段必须写成 `(?:(?!\\\().){1,40}?`：只写 `\\\(.{1,40}?\\\)` 的话，非贪婪只是优先短匹配，
     * 为了让后面的标点成立，引擎会一路扩到本行最后一个 `\)`，把整句锁成一个不可断的块，
     * 行首那一长串塞不下就整体挪到下一行，留下大片空白（真机踩过）。
     * 40 字封顶：再长的算式宁可让它可以断，也别把整行顶到下一行。
     */
    private val PUNCT_GLUE = Regex(
        """(\\\((?:(?!\\\().){1,40}?\\\)|[0-9A-Za-z.%\-]{1,24}|[\u4e00-\u9fff])""" +
            """([\u3002\uff0c\u3001\uff1b\uff1a\uff01\uff1f\u201d\u2019\u2014\u2026\uff09\u3011\u300b\)\]]+)"""
    )

    /**
     * 行规范化：丢弃分隔线，并把以标点开头的行并回上一行末尾。
     * 三种渲染形态共用，保证流式预览 / 定稿气泡 / KaTeX WebView 表现一致。
     */
    fun normalizedLines(text: String): List<String> {
        val out = ArrayList<String>(16)
        for (raw in text.lineSequence()) {
            if (RULE.matches(raw)) continue
            val trimmed = raw.trimStart().replace(SPACE_BEFORE_CLOSE, "")
            if (out.isNotEmpty() && trimmed.isNotEmpty() && ORPHAN_PUNCT.matches(trimmed)) {
                out[out.lastIndex] = out.last().trimEnd() + trimmed
            } else {
                out.add(trimmed)
            }
        }
        return out
    }

    fun containsMarkdown(text: String): Boolean =
        BOLD.containsMatchIn(text) || text.lineSequence().any {
            HEADING.matches(it) || BULLET.containsMatchIn(it) || RULE.matches(it)
        }

    fun containsLatex(text: String): Boolean =
        text.contains("\\(") || text.contains("\\[")

    /** 纯文本化（流式预览用）。 */
    fun strip(text: String): String = normalizedLines(text).joinToString("\n") { line ->
        var l = HEADING.find(line)?.groupValues?.get(1) ?: line
        l = BULLET.replaceFirst(l, "• ")
        l = BOLD.replace(l) { it.groupValues[1] }
        l = CODE.replace(l) { it.groupValues[1] }
        l
    }

    /** 转 Compose 富文本（定稿气泡用）。 */
    fun toAnnotated(text: String): AnnotatedString = buildAnnotatedString {
        val lines = normalizedLines(text)
        lines.forEachIndexed { idx, raw ->
            if (idx > 0) append("\n")
            val heading = HEADING.find(raw)
            val section = SECTION.matches(raw)
            val line = heading?.groupValues?.get(1) ?: raw
            val bullet = BULLET.containsMatchIn(line)
            val body = BULLET.replaceFirst(line, "")
            if (bullet) append("• ")
            val style = if (heading != null || section) {
                SpanStyle(fontWeight = FontWeight.Bold)
            } else null
            appendWithBold(body, style)
        }
    }

    private fun androidx.compose.ui.text.AnnotatedString.Builder.appendWithBold(
        text: String,
        baseStyle: SpanStyle?,
    ) {
        var cursor = 0
        val cleaned = CODE.replace(text) { it.groupValues[1] }
        // CODE 替换会移动索引，简化处理：先清 code 再找 bold
        for (m in BOLD.findAll(cleaned)) {
            if (m.range.first > cursor) {
                appendPlain(cleaned.substring(cursor, m.range.first), baseStyle)
            }
            withStyle(baseStyle?.merge(SpanStyle(fontWeight = FontWeight.Bold))
                ?: SpanStyle(fontWeight = FontWeight.Bold)) {
                append(m.groupValues[1])
            }
            cursor = m.range.last + 1
        }
        if (cursor < cleaned.length) appendPlain(cleaned.substring(cursor), baseStyle)
    }

    private fun androidx.compose.ui.text.AnnotatedString.Builder.appendPlain(
        text: String,
        style: SpanStyle?,
    ) {
        if (style != null) withStyle(style) { append(text) } else append(text)
    }

    /** 转 HTML 片段（KaTeX WebView 用；先转义再还原标记，公式反斜杠不受影响）。 */
    fun toHtml(text: String): String = normalizedLines(text).joinToString("<br>") { raw ->
        val heading = HEADING.find(raw)
        val section = SECTION.matches(raw)
        var line = escapeHtml(heading?.groupValues?.get(1) ?: raw)
        line = BULLET.replaceFirst(line, "• ")
        line = BOLD.replace(line) { "<b>${it.groupValues[1]}</b>" }
        line = CODE.replace(line) { "<code>${it.groupValues[1]}</code>" }
        // 实体（&lt; &#39;）里的分号会被误当成标点，所以转义之后再包、且禁则集不含 ASCII 分号
        line = PUNCT_GLUE.replace(line) { m -> "<span class=\"nw\">${m.value}</span>" }
        if (heading != null || section) "<b>$line</b>" else line
    }

    private fun escapeHtml(s: String): String = s
        .replace("&", "&amp;")
        .replace("<", "&lt;")
        .replace(">", "&gt;")
}
