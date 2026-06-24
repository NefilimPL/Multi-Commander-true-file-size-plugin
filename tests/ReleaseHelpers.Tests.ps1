$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $repoRoot "scripts\ReleaseHelpers.ps1")

function Assert-Equal {
    param(
        [Parameter(Mandatory = $true)] $Actual,
        [Parameter(Mandatory = $true)] $Expected,
        [Parameter(Mandatory = $true)] [string] $Message
    )

    if ($Actual -ne $Expected) {
        throw "$Message. Expected '$Expected', got '$Actual'."
    }
}

function Assert-True {
    param(
        [Parameter(Mandatory = $true)] [bool] $Condition,
        [Parameter(Mandatory = $true)] [string] $Message
    )

    if (-not $Condition) {
        throw $Message
    }
}

function Assert-False {
    param(
        [Parameter(Mandatory = $true)] [bool] $Condition,
        [Parameter(Mandatory = $true)] [string] $Message
    )

    if ($Condition) {
        throw $Message
    }
}

function Assert-Throws {
    param(
        [Parameter(Mandatory = $true)] [scriptblock] $ScriptBlock,
        [Parameter(Mandatory = $true)] [string] $Message
    )

    $thrown = $false
    try {
        & $ScriptBlock
    }
    catch {
        $thrown = $true
    }

    if (-not $thrown) {
        throw $Message
    }
}

Assert-Equal (ConvertTo-PluginVersionFromTag "V1.0.0") "1.0.0" "Uppercase V tag should convert"
Assert-Equal (ConvertTo-PluginVersionFromTag "v1.0.0.1") "1.0.0.1" "Lowercase v four-part tag should convert"
Assert-Throws { ConvertTo-PluginVersionFromTag "1.0.0" } "Tag without V prefix should be rejected"
Assert-Throws { ConvertTo-PluginVersionFromTag "V1.0" } "Two-part tag should be rejected"

Assert-True (Test-PluginVersion "1.0.0") "Three-part version should be valid"
Assert-True (Test-PluginVersion "1.0.0.1") "Four-part version should be valid"
Assert-False (Test-PluginVersion "1.0") "Two-part version should be invalid"
Assert-False (Test-PluginVersion "v1.0.0") "Version should not include tag prefix"

Assert-Equal (Get-ReleasePackageName -Version "1.0.0" -Platform "x64") "MCRealDiskSize-v1.0.0-x64.zip" "x64 package name should include version"
Assert-Equal (Get-ReleasePackageName -Version "1.0.0.1" -Platform "Win32") "MCRealDiskSize-v1.0.0.1-Win32.zip" "Win32 package name should include four-part version"
Assert-Throws { Get-ReleasePackageName -Version "1.0" -Platform "x64" } "Invalid package version should be rejected"
