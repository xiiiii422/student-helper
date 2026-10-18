package com.example.studenthelper.core.network

import kotlinx.serialization.json.Json

/** 全局 JSON 配置：容忍未知字段、编码默认值、忽略 null 可省。 */
val AppJson = Json {
    ignoreUnknownKeys = true
    encodeDefaults = true
    isLenient = true
    explicitNulls = false
    coerceInputValues = true
}
