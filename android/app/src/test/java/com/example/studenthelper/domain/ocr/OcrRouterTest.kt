package com.example.studenthelper.domain.ocr

import com.example.studenthelper.core.common.Subject
import org.junit.Assert.assertEquals
import org.junit.Test

/** 纯逻辑单测：覆盖 OcrRouter.decide 的置信度 × 学科 × 公式特征矩阵。 */
class OcrRouterTest {

    private fun mode(text: String, conf: Float, subject: Subject) =
        OcrRouter.decide(text, conf, subject)

    @Test
    fun `高置信度普通文本走纯文字`() {
        assertEquals(OcrMode.TEXT_ONLY, mode("小明有5个苹果，吃了2个还剩几个", 0.95f, Subject.MATH))
        assertEquals(OcrMode.TEXT_ONLY, mode("请用「忽然」造句", 0.92f, Subject.CHINESE))
        assertEquals(OcrMode.TEXT_ONLY, mode("apple 是什么意思", 0.99f, Subject.ENGLISH))
    }

    @Test
    fun `高置信度但含数学算式仍走图文兜底`() {
        // 含分数 3/4 -> 命中 MATH_PATTERN
        assertEquals(OcrMode.TEXT_AND_IMAGE, mode("计算 3/4 + 1/8 的值", 0.95f, Subject.MATH))
        // 含四则等式
        assertEquals(OcrMode.TEXT_AND_IMAGE, mode("12 + 7 =", 0.97f, Subject.MATH))
        // 含几何符号
        assertEquals(OcrMode.TEXT_AND_IMAGE, mode("求这个△的面积", 0.99f, Subject.MATH))
    }

    @Test
    fun `数学题有效字符过少走图文兜底`() {
        // 稀疏文本（<12 个非空白字符）即便高置信度也不纯文字
        assertEquals(OcrMode.TEXT_AND_IMAGE, mode("5 × 3", 0.99f, Subject.MATH))
    }

    @Test
    fun `非数学学科不触发公式与稀疏规则`() {
        // 语文出现 "/" 或短文本仍按置信度判定
        assertEquals(OcrMode.TEXT_ONLY, mode("3/4", 0.95f, Subject.CHINESE))
    }

    @Test
    fun `语文多行阅读版式强制带图`() {
        val passage = "春天的花园里开满了桃花。\n小明说：春天真美。\n请回答：这段话写的是什么季节？\n为什么小明觉得春天美？"
        assertEquals(OcrMode.TEXT_AND_IMAGE, mode(passage, 0.97f, Subject.CHINESE))
    }

    @Test
    fun `英语多行阅读同样强制带图`() {
        val passage = "Tom gets up at six.\nHe has breakfast at seven.\nQuestion: What time does Tom get up?\nAnswer it."
        assertEquals(OcrMode.TEXT_AND_IMAGE, mode(passage, 0.95f, Subject.ENGLISH))
    }

    @Test
    fun `数学多行短题干不受阅读规则影响`() {
        // 数学三行算式：命中公式特征走图文，不因行数规则变化
        val text = "3/4 + 1/8 =\n1/2 x 6 =\n5/6 - 1/3 ="
        assertEquals(OcrMode.TEXT_AND_IMAGE, mode(text, 0.95f, Subject.MATH))
    }

    @Test
    fun `中置信度走图文兜底`() {
        assertEquals(OcrMode.TEXT_AND_IMAGE, mode("识别不太确定的题目内容", 0.75f, Subject.CHINESE))
        assertEquals(OcrMode.TEXT_AND_IMAGE, mode("刚好压线的置信度", 0.60f, Subject.ENGLISH))
    }

    @Test
    fun `低置信度走纯图片多模态`() {
        assertEquals(OcrMode.IMAGE_ONLY, mode("乱码识别结果", 0.30f, Subject.MATH))
        assertEquals(OcrMode.IMAGE_ONLY, mode("", 0.0f, Subject.CHINESE))
    }

    @Test
    fun `边界值九十分无公式为纯文字`() {
        assertEquals(OcrMode.TEXT_ONLY, mode("这是一道足够长的六年级语文题目描述", 0.90f, Subject.CHINESE))
    }
}
