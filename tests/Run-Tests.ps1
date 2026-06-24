$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot

$testFiles = @(
    Join-Path $PSScriptRoot "ReleaseHelpers.Tests.ps1"
)

foreach ($testFile in $testFiles) {
    Write-Host "Running $testFile"
    & $testFile
}

Write-Host "All tests passed."
