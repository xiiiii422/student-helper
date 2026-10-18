package com.example.studenthelper.ui.chinese

import androidx.compose.runtime.Composable
import androidx.compose.ui.res.stringResource
import com.example.studenthelper.R
import com.example.studenthelper.ui.shared.ChatScreen
import com.example.studenthelper.ui.theme.ChineseAccent

@Composable
fun ChineseScreen() {
    ChatScreen(accent = ChineseAccent, title = stringResource(R.string.tab_chinese))
}
