package com.example.studenthelper.ui.theme

import androidx.compose.ui.graphics.Color

// ── 小米澎湃 OS（HyperOS）色板 ──
val MiBlue = Color(0xFF0A59F7)          // 小米品牌蓝（主强调）
val MiOrange = Color(0xFFFF6900)        // 小米品牌橙（次强调）
val MiPurple = Color(0xFF722ED1)        // 生态紫

val HyperBackground = Color(0xFFF5F5F5) // 页面灰底
val HyperCard = Color(0xFFFFFFFF)       // 分组白卡
val HyperFill = Color(0xFFF2F3F5)       // 输入胶囊 / AI 气泡填充
val HyperDivider = Color(0xFFE5E6EB)    // 分隔线

val HyperText = Color(0xFF1D2129)       // 一级文本
val HyperTextSecondary = Color(0xFF4E5969) // 二级文本
val HyperTextTertiary = Color(0xFF86909C)  // 三级文本/未选中图标

// ── 深色模式 token（澎湃 OS Dark）──
val MiBlueDark = Color(0xFF409CFF)      // 深色下提亮品牌蓝
val HyperBackgroundDark = Color(0xFF171717)
val HyperCardDark = Color(0xFF1F1F1F)
val HyperFillDark = Color(0xFF2C2C2E)  // AI 气泡/输入胶囊/填充
val HyperDividerDark = Color(0xFF38383A)
val HyperTextDark = Color(0xFFF5F5F7)
val HyperTextDarkSecondary = Color(0xFF98989F)

// 学科强调色（克制、小面积点睛）
val ChineseAccent = Color(0xFFF53F3F)   // 语文·红
val MathAccent = MiBlue                 // 数学·小米蓝
val EnglishAccent = Color(0xFF00B42A)   // 英语·绿
val CompositionAccent = MiOrange        // 作文·小米橙
// “我的”不是学科，不参与红/蓝/绿/橙那套身份色；再用紫会退化成 Material 默认紫的观感
val MeAccent = HyperTextSecondary       // 我的·中性石板灰

// 分数配色
val ScoreExcellent = Color(0xFF00B42A)  // >=90 绿
val ScoreGood = MiBlue                  // >=80 蓝
val ScoreFair = Color(0xFFFF7D00)       // >=70 橙
val ScorePoor = Color(0xFFF53F3F)       // <70 红

// 批改详情语义色（深浅各一套，避免深底上几乎看不清）
val NoteOriginal = Color(0xFFB45309)
val NoteOriginalDark = Color(0xFFFFB84D)
val NoteBetter = Color(0xFF0E9F5B)
val NoteBetterDark = Color(0xFF65D18A)

// ── 兼容旧引用（原 iOS 命名，值已切换为澎湃 OS 色板）──
val IosBlue = MiBlue
val IosGray5 = HyperFill
val IosGray6 = HyperBackground
val IosBubbleGray = HyperFill
val Label = HyperText
val SecondaryLabel = HyperTextSecondary
val TertiaryLabel = HyperTextTertiary
val SurfaceWhite = HyperCard
val Background = HyperBackground
val TextPrimary = HyperText
val TextSecondary = HyperTextTertiary

// 状态指示（连接测试这类“通/不通”小圆点，不用学科身份色）
val StatusOk = Color(0xFF00B42A)
const val HAIRLINE_ALPHA = 0.18f
