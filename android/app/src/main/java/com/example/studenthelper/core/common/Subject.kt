package com.example.studenthelper.core.common

/** 学科枚举，字符串值与后端 /api/chat 的 subject 字段一致。 */
enum class Subject(val apiValue: String, val label: String) {
    CHINESE("chinese", "语文"),
    MATH("math", "数学"),
    ENGLISH("english", "英语"),
    ;

    companion object {
        fun fromApi(value: String): Subject =
            entries.firstOrNull { it.apiValue == value } ?: MATH

        fun fromRoute(route: String): Subject? =
            entries.firstOrNull { it.apiValue == route }
    }
}
