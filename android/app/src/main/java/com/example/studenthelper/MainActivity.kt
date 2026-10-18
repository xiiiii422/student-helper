package com.example.studenthelper

import android.Manifest
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.runtime.getValue
import androidx.compose.runtime.collectAsState
import androidx.hilt.navigation.compose.hiltViewModel
import com.example.studenthelper.ui.me.SettingsViewModel
import com.example.studenthelper.ui.navigation.StudentHelperRoot
import com.example.studenthelper.ui.theme.StudentHelperTheme
import dagger.hilt.android.AndroidEntryPoint

@AndroidEntryPoint
class MainActivity : ComponentActivity() {

    private val notificationPermissionLauncher =
        registerForActivityResult(ActivityResultContracts.RequestPermission()) { }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        requestCameraIfNeeded()
        setContent {
            val vm: SettingsViewModel = hiltViewModel()
            val mode by vm.themeMode.collectAsState()
            val systemDark = isSystemInDarkTheme()
            val dark = when (mode) {
                1 -> false
                2 -> true
                else -> systemDark
            }
            StudentHelperTheme(darkTheme = dark) {
                StudentHelperRoot()
            }
        }
    }

    private fun requestCameraIfNeeded() {
        // 拍照用 TakePicture intent；首次启动申请一次相机权限，无权限时自动降级相册选图。
        notificationPermissionLauncher.launch(Manifest.permission.CAMERA)
    }
}
