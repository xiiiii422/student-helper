# 下载 KaTeX 本地资源到 assets/katex/，供 MathText 组件离线渲染数学公式。
# KaTeX 为 MIT 开源库。此脚本从官方 jsDelivr CDN 拉取指定版本。
$ErrorActionPreference = "Stop"
$ver = "0.16.11"
$dest = Join-Path $PSScriptRoot "katex"
New-Item -ItemType Directory -Force -Path $dest | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $dest "fonts") | Out-Null

$base = "https://cdn.jsdelivr.net/npm/katex@$ver/dist"
Invoke-WebRequest "$base/katex.min.css" -OutFile (Join-Path $dest "katex.min.css")
Invoke-WebRequest "$base/katex.min.js"  -OutFile (Join-Path $dest "katex.min.js")
Invoke-WebRequest "$base/contrib/auto-render.min.js" -OutFile (Join-Path $dest "auto-render.min.js")

# 解析 CSS 中引用的字体文件并下载（兼容 url("fonts/...") 与 url(fonts/...) 两种写法）
$css = Get-Content (Join-Path $dest "katex.min.css") -Raw
$fonts = [regex]::Matches($css, 'url\((?:")?fonts/([^)"\s]+)(?:")?\)') | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique
foreach ($f in $fonts) {
    $url = "$base/" + $f.Replace("\", "/")
    $out = Join-Path $dest $f
    New-Item -ItemType Directory -Force -Path (Split-Path $out) | Out-Null
    Write-Host "downloading $f"
    Invoke-WebRequest $url -OutFile $out
}
Write-Host "KaTeX 资源已下载到 $dest"
