# ============================================================
#  StudentHelper - One-click Debug APK build (no Android Studio)
#  Usage (PowerShell):
#      ./build_apk.ps1                        # unit tests + assembleDebug
#      ./build_apk.ps1 -Tasks assembleDebug   # skip tests
#  Output: release\StudentHelper-debug.apk
#
#  API keys are NOT in this repo. Put them in android\secrets.properties
#  (gitignored, see secrets.properties.example); they are passed to Gradle
#  as -P properties below. Without them the app still builds, it just has
#  no pre-buried key and you paste one in "Model service settings".
#
#  NOTE: keep this file ASCII-only; Windows PowerShell 5.1 reads
#        .ps1 as GBK when there is no BOM, which breaks CJK strings.
# ============================================================

param(
    [string[]]$Tasks = @("testDebugUnitTest", "assembleDebug")
)

$ErrorActionPreference = "Stop"

# --- Dependency paths (edit if yours differ) ---
$Jdk      = "C:\Program Files\Microsoft\jdk-17.0.20.101-hotspot"
$Android  = "C:\Android\Sdk"
$Gradle   = "C:\tools\gradle-8.9\bin\gradle.bat"
# AGP refuses to build under non-ASCII paths, so copy to an ASCII temp dir.
$SrcProj  = Join-Path $PSScriptRoot "android"
$BuildDir = "C:\shbuild"
$WorkProj = Join-Path $BuildDir "android"

Write-Host "==> Copy project to ASCII path $WorkProj ..." -ForegroundColor Cyan
# Only refresh the copied project, keep other files in $BuildDir (screenshots etc.)
if (Test-Path $WorkProj) { Remove-Item -Recurse -Force $WorkProj }
New-Item -ItemType Directory -Force -Path $BuildDir | Out-Null
Copy-Item $SrcProj $WorkProj -Recurse -Force

# Write SDK location
"sdk.dir=C\:\\Android\\Sdk" | Out-File -Encoding ascii (Join-Path $WorkProj "local.properties")

# Read local secrets and hand them to Gradle as -P properties.
# (local.properties gets rewritten above, so secrets must not live there.)
$secretArgs = @()
$secretFile = Join-Path $SrcProj "secrets.properties"
if (Test-Path $secretFile) {
    $map = @{}
    Get-Content $secretFile -Encoding UTF8 | ForEach-Object {
        $line = $_.Trim()
        if ($line -and -not $line.StartsWith("#")) {
            $i = $line.IndexOf("=")
            if ($i -gt 0) { $map[$line.Substring(0, $i).Trim()] = $line.Substring($i + 1).Trim() }
        }
    }
    foreach ($k in @("glmApiKey", "deepseekApiKey", "defaultProvider")) {
        if ($map.ContainsKey($k) -and $map[$k]) { $secretArgs += "-P$k=$($map[$k])" }
    }
    Write-Host "==> Loaded $($secretArgs.Count) key(s) from android\secrets.properties" -ForegroundColor Cyan
} else {
    Write-Host "==> android\secrets.properties not found; building without pre-buried keys" -ForegroundColor Yellow
}

$env:JAVA_HOME     = $Jdk
$env:ANDROID_HOME  = $Android
$env:JAVA_TOOL_OPTIONS = "-Duser.language=en -Duser.country=US"

Write-Host "==> Running gradle tasks: $($Tasks -join ', ')" -ForegroundColor Cyan
Push-Location $WorkProj
try {
    & $Gradle @Tasks @secretArgs --no-daemon --console=plain
    $code = $LASTEXITCODE
} finally { Pop-Location }

if ($code -ne 0) {
    Write-Host "Build FAILED, see log above." -ForegroundColor Red
    exit $code
}

$apk = Join-Path $WorkProj "app\build\outputs\apk\debug\app-debug.apk"
$outDir = Join-Path $PSScriptRoot "release"
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
Copy-Item $apk (Join-Path $outDir "StudentHelper-debug.apk") -Force

Write-Host "==> Done: release\StudentHelper-debug.apk" -ForegroundColor Green
