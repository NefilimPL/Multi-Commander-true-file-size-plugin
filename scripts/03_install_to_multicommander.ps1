param(
    [string]$MultiCommanderPath = "",

    [ValidateSet("x64", "Win32")]
    [string]$Platform = "x64",

    [ValidateSet("Release", "Debug")]
    [string]$Configuration = "Release"
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$dll = Join-Path $root "bin\$Platform\$Configuration\MCRealDiskSize.dll"

if (!(Test-Path $dll)) {
    throw "DLL not found: $dll. Build first using scripts\02_build.ps1."
}

if ([string]::IsNullOrWhiteSpace($MultiCommanderPath)) {
    $candidates = @(
        "$env:ProgramFiles\MultiCommander",
        "$env:ProgramFiles\Multi Commander",
        "${env:ProgramFiles(x86)}\MultiCommander",
        "${env:ProgramFiles(x86)}\Multi Commander"
    ) | Where-Object { $_ -and (Test-Path (Join-Path $_ "MultiCommander.exe")) }

    if ($candidates.Count -eq 0) {
        throw "Multi Commander path was not detected. Run: .\scripts\03_install_to_multicommander.ps1 -MultiCommanderPath 'C:\Path\To\MultiCommander'"
    }

    $MultiCommanderPath = $candidates[0]
}

$MultiCommanderPath = [IO.Path]::GetFullPath($MultiCommanderPath)
if (!(Test-Path (Join-Path $MultiCommanderPath "MultiCommander.exe"))) {
    throw "MultiCommander.exe not found in: $MultiCommanderPath"
}

$extDir = Join-Path $MultiCommanderPath "Extensions\MCRealDiskSize"
New-Item -ItemType Directory -Force -Path $extDir | Out-Null
Copy-Item $dll -Destination (Join-Path $extDir "MCRealDiskSize.dll") -Force

Write-Host "Installed to: $extDir"
Write-Host "Restart Multi Commander, then enable/add the columns in column customization."
