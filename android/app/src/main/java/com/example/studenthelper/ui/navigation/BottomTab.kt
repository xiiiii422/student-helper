package com.example.studenthelper.ui.navigation

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.MenuBook
import androidx.compose.material.icons.automirrored.outlined.MenuBook
import androidx.compose.material.icons.filled.Calculate
import androidx.compose.material.icons.filled.EditNote
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.Translate
import androidx.compose.material.icons.outlined.Calculate
import androidx.compose.material.icons.outlined.EditNote
import androidx.compose.material.icons.outlined.Person
import androidx.compose.material.icons.outlined.Translate
import androidx.compose.ui.graphics.vector.ImageVector
import com.example.studenthelper.R
import com.example.studenthelper.core.common.Subject

/** 底部 5 个主 Tab：SF 风双态图标（未选中细线 / 选中填充）。 */
enum class BottomTab(
    val route: String,
    val labelRes: Int,
    val iconSelected: ImageVector,
    val iconUnselected: ImageVector,
) {
    CHINESE(Subject.CHINESE.apiValue, R.string.tab_chinese, Icons.AutoMirrored.Filled.MenuBook, Icons.AutoMirrored.Outlined.MenuBook),
    MATH(Subject.MATH.apiValue, R.string.tab_math, Icons.Filled.Calculate, Icons.Outlined.Calculate),
    ENGLISH(Subject.ENGLISH.apiValue, R.string.tab_english, Icons.Filled.Translate, Icons.Outlined.Translate),
    COMPOSITION("composition", R.string.tab_composition, Icons.Filled.EditNote, Icons.Outlined.EditNote),
    ME("me", R.string.tab_me, Icons.Filled.Person, Icons.Outlined.Person),
    ;

    companion object {
        fun fromRoute(route: String): BottomTab? =
            entries.firstOrNull { it.route == route.substringBefore("/") }
    }
}

/** 非 Tab 的子路由常量。 */
object Routes {
    const val COMPOSITION_NEW = "composition/new"
    const val COMPOSITION_DETAIL = "composition/detail"
    fun compositionDetail(id: Long) = "$COMPOSITION_DETAIL/$id"
    const val FAVORITES = "favorites"
    const val SETTINGS = "settings"
}
