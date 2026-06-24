param(
    [ValidateSet("x64", "Win32")]
    [string]$Platform = "x64",

    [ValidateSet("Release", "Debug")]
    [string]$Configuration = "Release",

    [string]$SDKDir = "",

    [string]$PluginVersion = ""
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot "ReleaseHelpers.ps1")

if (-not [string]::IsNullOrWhiteSpace($PluginVersion) -and -not (Test-PluginVersion $PluginVersion)) {
    throw "Invalid plugin version '$PluginVersion'. Expected 1.0.0 or 1.0.0.1."
}

if ([string]::IsNullOrWhiteSpace($SDKDir)) {
    $SDKDir = Join-Path $root "external\MultiCommander-SDK-main\MultiCommander\SDK"
}
$SDKDir = [IO.Path]::GetFullPath($SDKDir)

if (!(Test-Path (Join-Path $SDKDir "FilePropertiesPlugin.h"))) {
    Write-Host "SDK not found. Running 01_download_sdk.ps1..."
    & (Join-Path $PSScriptRoot "01_download_sdk.ps1")
}

if (!(Test-Path (Join-Path $SDKDir "FilePropertiesPlugin.h"))) {
    throw "SDK not found: $SDKDir"
}

$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
if (!(Test-Path $vswhere)) {
    throw "vswhere.exe not found. Install Visual Studio 2022 or Build Tools with 'Desktop development with C++'."
}

$vsInstall = & $vswhere -latest -products * -requires Microsoft.Component.MSBuild -property installationPath
if ([string]::IsNullOrWhiteSpace($vsInstall)) {
    throw "Visual Studio/MSBuild not found. Install Visual Studio 2022 or Build Tools with C++ workload."
}

$msbuild = Join-Path $vsInstall "MSBuild\Current\Bin\MSBuild.exe"
if (!(Test-Path $msbuild)) {
    $msbuild = Join-Path $vsInstall "MSBuild\15.0\Bin\MSBuild.exe"
}
if (!(Test-Path $msbuild)) {
    throw "MSBuild.exe not found under: $vsInstall"
}

$project = Join-Path $root "MCRealDiskSize.vcxproj"
Write-Host "Building: $project"
Write-Host "Platform: $Platform"
Write-Host "Configuration: $Configuration"
Write-Host "SDKDir: $SDKDir"
if (-not [string]::IsNullOrWhiteSpace($PluginVersion)) {
    Write-Host "PluginVersion: $PluginVersion"
}

$msbuildArgs = @(
    $project,
    "/m",
    "/p:Configuration=$Configuration",
    "/p:Platform=$Platform",
    "/p:MCSDKDir=$SDKDir",
    "/t:Rebuild"
)
if (-not [string]::IsNullOrWhiteSpace($PluginVersion)) {
    $msbuildArgs += "/p:MCRealDiskSizeVersion=$PluginVersion"
}

& $msbuild @msbuildArgs
if ($LASTEXITCODE -ne 0) {
    throw "Build failed with exit code $LASTEXITCODE"
}

$dll = Join-Path $root "bin\$Platform\$Configuration\MCRealDiskSize.dll"
if (!(Test-Path $dll)) {
    throw "Build finished but DLL was not found: $dll"
}

Write-Host "Build OK: $dll"
