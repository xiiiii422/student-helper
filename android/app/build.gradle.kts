import java.util.Properties

plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.android)
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.kotlin.serialization)
    alias(libs.plugins.ksp)
    alias(libs.plugins.hilt)
}

/*
 * 大模型 Key 的取值顺序：-P 参数 → 环境变量 → local.properties → 空。
 *
 * 之前 Key 直接写死在这里，自用版是省事，但仓库一旦推到 GitHub，
 * 就算后来删掉，Key 也永久留在 git 历史里。现在源码里只剩一个空默认值，
 * 真 Key 放在被 .gitignore 排除的 android/secrets.properties（build_apk.ps1 会自动读）。
 */
val localProps = Properties().apply {
    val f = rootProject.file("local.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}

fun secret(name: String): String {
    val fromGradle = project.findProperty(name) as String?
    if (!fromGradle.isNullOrEmpty()) return fromGradle
    val fromEnv = System.getenv(name)
    if (!fromEnv.isNullOrEmpty()) return fromEnv
    return localProps.getProperty(name) ?: ""
}

android {
    namespace = "com.example.studenthelper"
    compileSdk = 35

    defaultConfig {
        applicationId = "com.example.studenthelper"
        minSdk = 26
        targetSdk = 35
        versionCode = 1
        versionName = "1.0.0"

        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"

        // 直连大模型配置（Key 从本地不入库的文件注入；App 内“模型服务设置”可改）
        buildConfigField("String", "DEFAULT_PROVIDER", "\"${secret("defaultProvider").ifBlank { "glm" }}\"")
        buildConfigField("String", "DEFAULT_API_BASE_URL", "\"https://open.bigmodel.cn/api/paas/v4\"")
        buildConfigField("String", "DEFAULT_API_KEY", "\"${secret("glmApiKey")}\"")
        buildConfigField("String", "DEEPSEEK_API_KEY", "\"${secret("deepseekApiKey")}\"")
        buildConfigField("String", "DEFAULT_CHAT_MODEL", "\"glm-4.7-flash\"")
        buildConfigField("String", "DEFAULT_VL_MODEL", "\"glm-4v-flash\"")
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
        debug {
            isMinifyEnabled = false
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions {
        jvmTarget = "17"
    }
    buildFeatures {
        compose = true
        buildConfig = true
    }
    testOptions {
        unitTests.isReturnDefaultValues = true
        unitTests.all {
            it.useJUnit()
        }
    }
    packaging {
        resources {
            excludes += "/META-INF/{AL2.0,LGPL2.1}"
        }
    }
}

ksp {
    arg("room.schemaLocation", "$projectDir/schemas")
}

dependencies {
    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.exifinterface)
    implementation(libs.androidx.lifecycle.runtime.ktx)
    implementation(libs.androidx.activity.compose)

    // Compose
    implementation(platform(libs.compose.bom))
    implementation(libs.compose.ui)
    implementation(libs.compose.ui.graphics)
    implementation(libs.compose.ui.tooling.preview)
    implementation(libs.compose.material3)
    implementation(libs.compose.material.icons)
    implementation(libs.compose.runtime)
    implementation(libs.navigation.compose)

    // Hilt
    implementation(libs.hilt.android)
    ksp(libs.hilt.compiler)
    implementation(libs.hilt.navigation.compose)

    // Room
    implementation(libs.room.runtime)
    implementation(libs.room.ktx)
    ksp(libs.room.compiler)

    // Network
    implementation(libs.retrofit)
    implementation(libs.okhttp)
    implementation(libs.okhttp.sse)
    implementation(libs.okhttp.logging)
    implementation(libs.retrofit.serialization)
    implementation(libs.kotlinx.serialization.json)
    implementation(libs.kotlinx.coroutines.android)

    // OCR (ML Kit Chinese, bundled 版打包进 APK)
    implementation(libs.mlkit.text.chinese)

    // CameraX
    implementation(libs.camera.core)
    implementation(libs.camera.camera2)
    implementation(libs.camera.lifecycle)
    implementation(libs.camera.view)

    // Image loading / WebView / DataStore / Permissions
    implementation(libs.coil.compose)
    implementation(libs.androidx.webkit)
    implementation(libs.datastore.preferences)
    implementation(libs.accompanist.permissions)

    // Test
    testImplementation(libs.junit)
    androidTestImplementation(libs.espresso.core)
    debugImplementation(libs.compose.ui.tooling)
    debugImplementation(libs.compose.ui.test.manifest)
}
