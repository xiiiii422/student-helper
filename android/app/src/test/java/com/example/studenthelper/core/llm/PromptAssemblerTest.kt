package com.example.studenthelper.core.llm

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** 直连版消息组装纯逻辑测试。 */
class PromptAssemblerTest {

    @Test
    fun `三科选对System Prompt`() {
        val c = PromptAssembler.chatMessages("chinese", "题", emptyList())
        assertTrue(c[0].content.startsWith("你是一位耐心温柔的小学六年级语文老师"))
        val m = PromptAssembler.chatMessages("math", "题", emptyList())
        assertTrue(m[0].content.startsWith("你是一位耐心温柔的小学六年级数学老师"))
        val e = PromptAssembler.chatMessages("english", "题", emptyList())
        assertTrue(e[0].content.startsWith("你是一位耐心温柔的小学六年级英语老师"))
    }

    @Test
    fun `历史截断为最近8对且顺序保持`() {
        val history = (1..20).map { Msg(if (it % 2 == 1) "user" else "assistant", "msg$it") }
        val out = PromptAssembler.chatMessages("math", "新题", history)
        // 1 system + 16 history + 1 user = 18
        assertEquals(18, out.size)
        assertEquals("system", out[0].role)
        assertEquals("msg5", out[1].content)   // 保留最近16条的第一条
        assertEquals("msg20", out[16].content) // 历史最后一条
        assertEquals("新题", out[17].content)
        assertEquals("user", out[17].role)
    }

    @Test
    fun `语文答案先行与图片优先规则在场`() {
        val c = PromptAssembler.chatMessages("chinese", "题", emptyList())[0].content
        assertTrue(c.contains("【答案】"))
        assertTrue(c.contains("【讲一讲】"))
        assertTrue(c.contains("【图片优先规则】"))
        assertTrue(c.contains("禁止只引导不给答案"))
    }

    @Test
    fun `数学Prompt含LaTeX与答行要求`() {
        val c = PromptAssembler.chatMessages("math", "题", emptyList())[0].content
        assertTrue(c.contains("""\frac{3}{4}"""))
        assertTrue(c.contains("答："))
    }

    @Test
    fun `作文消息拼装含标题正文与要求`() {
        val msgs = PromptAssembler.compositionMessages("我的妈妈", "六年级", "正文内容", "600字")
        assertEquals(2, msgs.size)
        assertTrue(msgs[0].content.contains("JSON"))
        assertTrue(msgs[1].content.contains("作文标题：我的妈妈"))
        assertTrue(msgs[1].content.contains("题目要求：600字"))
        assertTrue(msgs[1].content.contains("正文内容"))
    }

    @Test
    fun `作文空正文时用占位说明`() {
        val u = PromptAssembler.compositionUserMessage("t", "六年级", null, null)
        assertTrue(u.contains("图片形式提交"))
    }

    @Test
    fun `多页手稿附加页码顺序说明单图不加`() {
        val two = PromptAssembler.compositionUserMessage("t", "六年级", "正文", null, imageCount = 2)
        assertTrue(two.contains("共上传了 2 页手稿"))
        assertTrue(two.contains("注明第几页"))
        val one = PromptAssembler.compositionUserMessage("t", "六年级", "正文", null, imageCount = 1)
        assertTrue(!one.contains("页手稿"))
    }

    @Test
    fun `改写消息与温度`() {
        val msgs = PromptAssembler.rewriteMessages("一段作文")
        assertEquals("system", msgs[0].role)
        assertEquals("一段作文", msgs[1].content)
        assertEquals(0.7, PromptAssembler.temperatureFor(PromptAssembler.Kind.REWRITE), 0.0001)
        assertEquals(0.3, PromptAssembler.temperatureFor(PromptAssembler.Kind.CHAT), 0.0001)
    }

    @Test
    fun `多模态 content 数组文字在前图片按顺序在后`() {
        val parts = PromptAssembler.buildUserContent("两页作文", listOf("AAA", "BBB"))
        assertEquals(3, parts.size)
        assertEquals("text", parts[0].type)
        assertEquals("两页作文", parts[0].text)
        assertEquals("image_url", parts[1].type)
        assertTrue(parts[1].imageUrl!!.startsWith("data:image/jpeg;base64,AAA"))
        assertTrue(parts[2].imageUrl!!.startsWith("data:image/jpeg;base64,BBB"))
    }

    @Test
    fun `无图时返回空列表降级纯文本`() {
        assertTrue(PromptAssembler.buildUserContent("题", emptyList()).isEmpty())
    }
}
