package com.example.studenthelper.domain.composition

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Test

/** 纯逻辑单测：FeedbackParser 对各种模型返回形态的稳健解析。 */
class FeedbackParserTest {

    private val valid = """
        {
          "总分": 88,
          "分项": {"内容": 23, "结构": 22, "语言": 22, "书写": 21},
          "总评": "叙事真挚。",
          "优点": [{"位置": "开头", "内容": "点题快", "为什么好": "开门见山"}],
          "问题": [{"位置": "第2段", "类型": "病句", "原句": "很美丽的花", "问题说明": "多余", "修改建议": "美丽的花"}],
          "改进建议": ["加入外貌描写", "结尾呼应开头"],
          "好句升级": [{"原句": "妈妈笑了", "改写": "妈妈笑开了花", "为什么更好": "更生动"}],
          "同类范文片段": "她系着围裙忙碌着。"
        }
    """.trimIndent()

    @Test
    fun `纯 JSON 正常解析`() {
        val fb = FeedbackParser.parse(valid)
        assertNotNull(fb)
        assertEquals(88, fb!!.totalScore)
        assertEquals(23, fb.breakdown.content)
        assertEquals(1, fb.strengths.size)
        assertEquals("病句", fb.issues[0].type)
        assertEquals(2, fb.suggestions.size)
        assertEquals("妈妈笑了", fb.rewrites[0].original)
    }

    @Test
    fun `剥离三反引号json围栏`() {
        val fenced = "```json\n$valid\n```"
        val fb = FeedbackParser.parse(fenced)
        assertNotNull(fb)
        assertEquals(88, fb!!.totalScore)
    }

    @Test
    fun `容忍前后夹杂说明文字`() {
        val noisy = "好的，以下是批改结果：\n$valid\n希望对你有帮助！"
        val fb = FeedbackParser.parse(noisy)
        assertNotNull(fb)
        assertEquals(88, fb!!.totalScore)
    }

    @Test
    fun `缺字段用默认值不崩溃`() {
        val partial = """{"总分": 70}"""
        val fb = FeedbackParser.parse(partial)
        assertNotNull(fb)
        assertEquals(70, fb!!.totalScore)
        assertEquals(0, fb.breakdown.content)
        assertEquals(0, fb.strengths.size)
    }

    @Test
    fun `空串与无花括号返回null`() {
        assertNull(FeedbackParser.parse(""))
        assertNull(FeedbackParser.parse("这完全不是JSON"))
    }

    @Test
    fun `坏JSON返回null`() {
        assertNull(FeedbackParser.parse("这显然不是JSON {{{ 乱七八糟"))
    }
}
