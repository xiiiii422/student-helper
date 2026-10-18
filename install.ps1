# One-click install to a USB-connected phone (keep this file ASCII only).
# Usage: plug phone in with USB debugging, then run  .\install.ps1
$ErrorActionPreference = "Stop"
$adb = "C:\Android\Sdk\platform-tools\adb.exe"
$apk = Join-Path $PSScriptRoot "release\StudentHelper-debug.apk"

if (-not (Test-Path $adb)) { Write-Host "adb not found at $adb" -ForegroundColor Red; exit 1 }
if (-not (Test-Path $apk)) { Write-Host "APK missing - run build_apk.ps1 first." -ForegroundColor Red; exit 1 }

Write-Host "Waiting for device (accept the USB debugging popup on the phone)..." -ForegroundColor Cyan
& $adb wait-for-device

Write-Host "Installing..." -ForegroundColor Cyan
& $adb install -r $apk
if ($LASTEXITCODE -ne 0) { Write-Host "Install failed." -ForegroundColor Red; exit 1 }

Write-Host "Launching app..." -ForegroundColor Cyan
& $adb shell monkey -p com.example.studenthelper -c android.intent.category.LAUNCHER 1 | Out-Null
Write-Host "Done. Grant camera permission when prompted." -ForegroundColor Green
