$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
Remove-Item (Join-Path $root "bin") -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item (Join-Path $root "obj") -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path (Join-Path $root "bin") | Out-Null
Write-Host "Cleaned bin/ and obj/."
