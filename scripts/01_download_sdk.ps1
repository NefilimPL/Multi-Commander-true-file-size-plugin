param(
    [string]$Destination = "$(Split-Path -Parent $PSScriptRoot)\external"
)

$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$root = Split-Path -Parent $PSScriptRoot
$dest = [IO.Path]::GetFullPath($Destination)
$sdkDir = Join-Path $dest "MultiCommander-SDK-main"
$zipPath = Join-Path $dest "MultiCommander-SDK-main.zip"
$url = "https://github.com/MultiCommander/MultiCommander-SDK/archive/refs/heads/main.zip"

New-Item -ItemType Directory -Force -Path $dest | Out-Null

if (Test-Path (Join-Path $sdkDir "MultiCommander\SDK\FilePropertiesPlugin.h")) {
    Write-Host "SDK already exists: $sdkDir"
    exit 0
}

Write-Host "Downloading MultiCommander SDK..."
Invoke-WebRequest -Uri $url -OutFile $zipPath

if (Test-Path $sdkDir) {
    Remove-Item $sdkDir -Recurse -Force
}

Write-Host "Extracting SDK..."
Expand-Archive -Path $zipPath -DestinationPath $dest -Force

if (!(Test-Path (Join-Path $sdkDir "MultiCommander\SDK\FilePropertiesPlugin.h"))) {
    throw "SDK extraction failed. FilePropertiesPlugin.h not found in $sdkDir"
}

Write-Host "SDK ready: $sdkDir"
