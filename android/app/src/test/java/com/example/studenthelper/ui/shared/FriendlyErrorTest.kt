package com.example.studenthelper.ui.shared

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class FriendlyErrorTest {

    @Test
    fun `401 映射为检查Key提示`() {
        val out = ChatViewModel.friendlyError("HTTP 401: {\"error\":{\"message\":\"AuthenticationError\"}}")
        assertTrue(out!!.contains("API Key"))
    }

    @Test
    fun `拥塞映射为重试提示`() {
        val out = ChatViewModel.friendlyError("模型服务繁忙（429 rate limit），请稍后再试")
        assertTrue(out!!.contains("重试"))
    }

    @Test
    fun `网络失败映射`() {
        val out = ChatViewModel.friendlyError("Unable to resolve host open.bigmodel.cn")
        assertTrue(out!!.contains("联网"))
    }

    @Test
    fun `空消息兜底且未知错误原样透出`() {
        assertEquals("网络异常，请重试", ChatViewModel.friendlyError(null))
        assertEquals("自定义错误", ChatViewModel.friendlyError("自定义错误"))
    }
}
