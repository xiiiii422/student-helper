package com.example.studenthelper.ui.math

import androidx.compose.runtime.Composable
import androidx.compose.ui.res.stringResource
import com.example.studenthelper.R
import com.example.studenthelper.ui.shared.ChatScreen
import com.example.studenthelper.ui.theme.MathAccent

@Composable
fun MathScreen() {
    ChatScreen(accent = MathAccent, title = stringResource(R.string.tab_math))
}
