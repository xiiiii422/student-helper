package com.example.studenthelper.ui.english

import androidx.compose.runtime.Composable
import androidx.compose.ui.res.stringResource
import com.example.studenthelper.R
import com.example.studenthelper.ui.shared.ChatScreen
import com.example.studenthelper.ui.theme.EnglishAccent

@Composable
fun EnglishScreen() {
    ChatScreen(accent = EnglishAccent, title = stringResource(R.string.tab_english))
}
