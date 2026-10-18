# Start the local backend (Windows PowerShell 5.1 safe: keep this file ASCII only).
# First run: creates venv, installs deps, generates .env and opens it for the API key.
# Later runs: prints the LAN URL for the phone and serves uvicorn on 0.0.0.0:8000.
$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

if (-not (Test-Path ".venv")) {
    Write-Host "== Creating virtual environment ==" -ForegroundColor Cyan
    python -m venv .venv
}
$py = ".\.venv\Scripts\python.exe"

Write-Host "== Installing dependencies ==" -ForegroundColor Cyan
& $py -m pip install -r requirements.txt --disable-pip-version-check -q

if (-not (Test-Path ".env")) {
    Copy-Item ".env.example" ".env"
    Write-Host "Created .env - opening Notepad." -ForegroundColor Yellow
    Write-Host "Fill DEEPSEEK_API_KEY and a random BACKEND_SECRET_TOKEN, save, then rerun this script." -ForegroundColor Yellow
    Start-Process notepad.exe -ArgumentList ".env"
    exit
}

# Detect a private LAN IPv4 so the phone (same Wi-Fi) can reach this machine.
$ip = (Get-NetIPAddress -AddressFamily IPv4 |
    Where-Object { $_.IPAddress -like "192.168.*" -or $_.IPAddress -like "10.*" -or ($_.IPAddress -like "172.*") } |
    Select-Object -First 1).IPAddress

Write-Host ""
Write-Host "Backend will listen on port 8000 (HTTP allowed for LAN use)." -ForegroundColor Green
if ($ip) {
    Write-Host ("In the App settings enter URL:  http://" + $ip + ":8000") -ForegroundColor Green
} else {
    Write-Host "No private LAN IP found; on the phone use this PC's Wi-Fi IPv4 address." -ForegroundColor Yellow
}
Write-Host "The App token must equal BACKEND_SECRET_TOKEN in .env." -ForegroundColor Green
Write-Host "If Windows Firewall prompts, allow private-network access (or: netsh advfirewall firewall add rule name=studenthelper dir=in action=allow protocol=TCP localport=8000)." -ForegroundColor Green
Write-Host ""
& $py -m uvicorn main:app --host 0.0.0.0 --port 8000
