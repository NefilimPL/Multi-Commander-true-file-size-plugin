param(
    [Parameter(Mandatory = $true)]
    [string] $Version,

    [ValidateSet("x64", "Win32")]
    [string] $Platform = "x64",

    [ValidateSet("Release", "Debug")]
    [string] $Configuration = "Release",

    [string] $SDKDir = ""
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot "ReleaseHelpers.ps1")

if (-not (Test-PluginVersion $Version)) {
    throw "Invalid plugin version '$Version'. Expected 1.0.0 or 1.0.0.1."
}

$buildArgs = @{
    Platform = $Platform
    Configuration = $Configuration
    PluginVersion = $Version
}
if (-not [string]::IsNullOrWhiteSpace($SDKDir)) {
    $buildArgs.SDKDir = $SDKDir
}

& (Join-Path $PSScriptRoot "02_build.ps1") @buildArgs

$dll = Join-Path $root "bin\$Platform\$Configuration\MCRealDiskSize.dll"
if (!(Test-Path $dll)) {
    throw "DLL not found after build: $dll"
}

$artifactsRoot = Join-Path $root "artifacts"
$packageRoot = Join-Path $artifactsRoot "package"
$pluginDir = Join-Path $packageRoot "MCRealDiskSize"
$releaseDir = Join-Path $artifactsRoot "release"

$artifactsRootFull = [IO.Path]::GetFullPath($artifactsRoot)
$packageRootFull = [IO.Path]::GetFullPath($packageRoot)
if (-not $packageRootFull.StartsWith($artifactsRootFull, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing to clean package directory outside artifacts: $packageRootFull"
}

if (Test-Path $packageRoot) {
    Remove-Item $packageRoot -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $pluginDir | Out-Null
New-Item -ItemType Directory -Force -Path $releaseDir | Out-Null

Copy-Item $dll -Destination (Join-Path $pluginDir "MCRealDiskSize.dll") -Force

$zipName = Get-ReleasePackageName -Version $Version -Platform $Platform
$zipPath = Join-Path $releaseDir $zipName
if (Test-Path $zipPath) {
    Remove-Item $zipPath -Force
}

Compress-Archive -Path $pluginDir -DestinationPath $zipPath -Force

if ($env:GITHUB_OUTPUT) {
    "zip_path=$zipPath" | Out-File -FilePath $env:GITHUB_OUTPUT -Append -Encoding utf8
    "zip_name=$zipName" | Out-File -FilePath $env:GITHUB_OUTPUT -Append -Encoding utf8
}

Write-Host "Release package: $zipPath"
