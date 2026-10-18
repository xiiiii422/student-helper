# Optional: expose the local backend to the internet via a Cloudflare quick tunnel
# (no account needed). Use this when the phone is NOT on the same Wi-Fi as the PC.
# The App URL becomes the printed https://xxxx.trycloudflare.com address.
# Keep this file ASCII only (Windows PowerShell 5.1).
$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

$exe = ".\tools\cloudflared.exe"
if (-not (Test-Path $exe)) {
    New-Item -ItemType Directory -Force -Path ".\tools" | Out-Null
    Write-Host "Downloading cloudflared (one time, about 45 MB) ..." -ForegroundColor Cyan
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-windows-amd64.exe" -OutFile $exe
}

if (-not (Test-Path ".venv\Scripts\python.exe")) {
    Write-Host "Run start_backend.bat once first (creates venv and .env)." -ForegroundColor Yellow
    exit 1
}

# Ensure .env exists so the backend can boot.
if (-not (Test-Path ".env")) {
    Write-Host "Missing .env - run start_backend.bat once and fill in the API key." -ForegroundColor Yellow
    exit 1
}

# Start backend quietly in the background, then open the tunnel in this console.
Start-Process -FilePath ".\.venv\Scripts\python.exe" `
    -ArgumentList "-m","uvicorn","main:app","--host","127.0.0.1","--port","8000" `
    -WindowStyle Minimized
Start-Sleep 3

Write-Host "Tunnel starting - copy the https://...trycloudflare.com URL printed below" -ForegroundColor Green
Write-Host "into the App settings (Me - Backend settings). Leave this window open." -ForegroundColor Green
& $exe tunnel --url http://127.0.0.1:8000 --no-autoupdate
