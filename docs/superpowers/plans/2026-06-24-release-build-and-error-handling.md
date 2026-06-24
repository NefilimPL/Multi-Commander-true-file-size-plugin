# Release Build and Error Handling Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build release ZIPs from version tags, prefer available self-hosted Windows runners with hosted fallback, and stop showing raw `ERROR` text for transient file metadata read failures.

**Architecture:** Add small PowerShell release helper functions and tests, pass the tag-derived version into MSBuild, package the DLL into an install-ready ZIP, and add a GitHub Actions workflow with a preflight runner-selection job. Keep C++ changes narrow: version macro injection and less alarming display values on read failures.

**Tech Stack:** C++17, Visual Studio/MSBuild v143, PowerShell 5.1+, GitHub Actions, GitHub REST API, ZIP packaging through `Compress-Archive`.

---

### Task 1: Add Release Helper Tests

**Files:**
- Create: `tests/Run-Tests.ps1`
- Create: `tests/ReleaseHelpers.Tests.ps1`
- Create after the failing test: `scripts/ReleaseHelpers.ps1`

- [ ] **Step 1: Write the failing test runner**

Create `tests/Run-Tests.ps1`:

```powershell
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
```

- [ ] **Step 2: Write the failing release helper tests**

Create `tests/ReleaseHelpers.Tests.ps1`:

```powershell
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
```

- [ ] **Step 3: Run tests to verify they fail**

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\Run-Tests.ps1
```

Expected: FAIL because `scripts\ReleaseHelpers.ps1` does not exist.

### Task 2: Implement Release Helpers

**Files:**
- Create: `scripts/ReleaseHelpers.ps1`
- Test: `tests/Run-Tests.ps1`

- [ ] **Step 1: Create helper implementation**

Create `scripts/ReleaseHelpers.ps1`:

```powershell
function Test-PluginVersion {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Version
    )

    return $Version -match '^\d+\.\d+\.\d+(\.\d+)?$'
}

function ConvertTo-PluginVersionFromTag {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Tag
    )

    if ($Tag -notmatch '^[Vv](\d+\.\d+\.\d+(\.\d+)?)$') {
        throw "Invalid release tag '$Tag'. Expected V1.0.0 or V1.0.0.1."
    }

    return $Matches[1]
}

function Get-ReleasePackageName {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Version,

        [Parameter(Mandatory = $true)]
        [ValidateSet("x64", "Win32")]
        [string] $Platform
    )

    if (-not (Test-PluginVersion $Version)) {
        throw "Invalid plugin version '$Version'. Expected 1.0.0 or 1.0.0.1."
    }

    return "MCRealDiskSize-v$Version-$Platform.zip"
}
```

- [ ] **Step 2: Run helper tests**

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\Run-Tests.ps1
```

Expected: PASS.

### Task 3: Inject Plugin Version and Soften Error Display

**Files:**
- Modify: `MCRealDiskSize.vcxproj`
- Modify: `scripts/02_build.ps1`
- Modify: `src/MCRealDiskSizeProp.cpp`
- Modify: `src/DiskSizeUtil.cpp`

- [ ] **Step 1: Add MSBuild version property**

In `MCRealDiskSize.vcxproj`, add:

```xml
<MCRealDiskSizeVersion Condition="'$(MCRealDiskSizeVersion)'==''">0.1.2.0</MCRealDiskSizeVersion>
```

to the existing global `PropertyGroup`, and add:

```xml
MCREALDISKSIZE_VERSION=&quot;$(MCRealDiskSizeVersion)&quot;;
```

to every `ClCompile` `PreprocessorDefinitions` value.

- [ ] **Step 2: Add build script parameter**

In `scripts/02_build.ps1`, add:

```powershell
[string]$PluginVersion = ""
```

Validate it with `scripts\ReleaseHelpers.ps1` when provided, then append:

```powershell
/p:MCRealDiskSizeVersion=$PluginVersion
```

to the MSBuild invocation only when it is non-empty.

- [ ] **Step 3: Use the version macro in C++**

In `src/MCRealDiskSizeProp.cpp`, add:

```cpp
#ifndef MCREALDISKSIZE_VERSION
#define MCREALDISKSIZE_VERSION "0.1.2.0"
#endif
```

and replace the hard-coded version string in `GetExtensionInfo()` with `MCREALDISKSIZE_VERSION`.

- [ ] **Step 4: Remove visible raw error text**

In `src/MCRealDiskSizeProp.cpp`, replace the `ERR:%lu` branch with an empty property value and a successful string callback.

In `src/DiskSizeUtil.cpp`, replace `return L"ERROR";` with `return L"UNKNOWN";`.

- [ ] **Step 5: Run helper tests**

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\Run-Tests.ps1
```

Expected: PASS.

### Task 4: Add Release Package Script

**Files:**
- Create: `scripts/New-ReleasePackage.ps1`
- Test: `tests/Run-Tests.ps1`

- [ ] **Step 1: Create package script**

Create `scripts/New-ReleasePackage.ps1`:

```powershell
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
```

- [ ] **Step 2: Run helper tests**

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\Run-Tests.ps1
```

Expected: PASS.

- [ ] **Step 3: Verify invalid package version fails before build**

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\New-ReleasePackage.ps1 -Version 1.0 -Platform x64 -Configuration Release
```

Expected: FAIL with `Invalid plugin version`.

### Task 5: Add GitHub Release Workflow

**Files:**
- Create: `.github/workflows/release.yml`

- [ ] **Step 1: Create workflow**

Create `.github/workflows/release.yml` with:

```yaml
name: Release DLL

on:
  release:
    types: [published]
  push:
    tags:
      - 'V*'
      - 'v*'
  workflow_dispatch:
    inputs:
      tag:
        description: 'Release tag, for example V1.0.0'
        required: true
        type: string

permissions:
  contents: write

jobs:
  preflight:
    name: Select runner
    runs-on: ubuntu-latest
    outputs:
      runner: ${{ steps.select.outputs.runner }}
      fallback: ${{ steps.select.outputs.fallback }}
      tag: ${{ steps.version.outputs.tag }}
      version: ${{ steps.version.outputs.version }}
    steps:
      - name: Resolve version
        id: version
        shell: pwsh
        run: |
          $tag = "${{ github.ref_name }}"
          if ("${{ github.event_name }}" -eq "release") {
            $tag = "${{ github.event.release.tag_name }}"
          }
          if ("${{ github.event_name }}" -eq "workflow_dispatch") {
            $tag = "${{ inputs.tag }}"
          }

          if ($tag -notmatch '^[Vv](\d+\.\d+\.\d+(\.\d+)?)$') {
            throw "Invalid release tag '$tag'. Expected V1.0.0 or V1.0.0.1."
          }

          "tag=$tag" >> $env:GITHUB_OUTPUT
          "version=$($Matches[1])" >> $env:GITHUB_OUTPUT

      - name: Select build runner
        id: select
        shell: pwsh
        env:
          RUNNER_STATUS_TOKEN: ${{ secrets.RUNNER_STATUS_TOKEN }}
          REPOSITORY: ${{ github.repository }}
        run: |
          $selfHosted = '["self-hosted","Windows","X64"]'
          $hosted = '"windows-latest"'

          if ([string]::IsNullOrWhiteSpace($env:RUNNER_STATUS_TOKEN)) {
            Write-Host "RUNNER_STATUS_TOKEN is not configured. Falling back to windows-latest."
            "runner=$hosted" >> $env:GITHUB_OUTPUT
            "fallback=true" >> $env:GITHUB_OUTPUT
            exit 0
          }

          try {
            $headers = @{
              Authorization = "Bearer $env:RUNNER_STATUS_TOKEN"
              Accept = "application/vnd.github+json"
              "X-GitHub-Api-Version" = "2022-11-28"
            }
            $uri = "https://api.github.com/repos/$env:REPOSITORY/actions/runners?per_page=100"
            $response = Invoke-RestMethod -Method Get -Uri $uri -Headers $headers
            $runner = $response.runners | Where-Object {
              $_.status -eq "online" -and
              -not $_.busy -and
              (($_.labels | ForEach-Object { $_.name }) -contains "self-hosted") -and
              (($_.labels | ForEach-Object { $_.name }) -contains "Windows") -and
              (($_.labels | ForEach-Object { $_.name }) -contains "X64")
            } | Select-Object -First 1

            if ($runner) {
              Write-Host "Using self-hosted runner labels: self-hosted, Windows, X64"
              "runner=$selfHosted" >> $env:GITHUB_OUTPUT
              "fallback=false" >> $env:GITHUB_OUTPUT
            }
            else {
              Write-Host "No online idle self-hosted Windows X64 runner found. Falling back to windows-latest."
              "runner=$hosted" >> $env:GITHUB_OUTPUT
              "fallback=true" >> $env:GITHUB_OUTPUT
            }
          }
          catch {
            Write-Host "Could not query self-hosted runners: $($_.Exception.Message)"
            Write-Host "Falling back to windows-latest."
            "runner=$hosted" >> $env:GITHUB_OUTPUT
            "fallback=true" >> $env:GITHUB_OUTPUT
          }

  build:
    name: Build DLL
    needs: preflight
    runs-on: ${{ fromJSON(needs.preflight.outputs.runner) }}
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Build release package
        id: package
        shell: pwsh
        run: |
          .\scripts\New-ReleasePackage.ps1 -Version '${{ needs.preflight.outputs.version }}' -Platform x64 -Configuration Release

      - name: Upload release asset
        uses: softprops/action-gh-release@v2
        with:
          tag_name: ${{ needs.preflight.outputs.tag }}
          files: ${{ steps.package.outputs.zip_path }}
          fail_on_unmatched_files: true

      - name: Upload fallback Actions artifact
        if: needs.preflight.outputs.fallback == 'true'
        uses: actions/upload-artifact@v4
        with:
          name: ${{ steps.package.outputs.zip_name }}
          path: ${{ steps.package.outputs.zip_path }}
          if-no-files-found: error
```

- [ ] **Step 2: Check workflow text for the required fallback artifact policy**

Run:

```powershell
Select-String -Path .\.github\workflows\release.yml -Pattern "Upload fallback Actions artifact|needs.preflight.outputs.fallback == 'true'|actions/upload-artifact@v4"
```

Expected: all three patterns are present.

### Task 6: Update README

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Add release installation and self-build requirements**

Update README to include these sections:

- `## Instalacja z GitHub Release`
- Instruction to download `MCRealDiskSize-v<wersja>-x64.zip`.
- Instruction to extract folder `MCRealDiskSize` into `<MultiCommander>\Extensions\`.
- Final DLL path: `<MultiCommander>\Extensions\MCRealDiskSize\MCRealDiskSize.dll`.
- Release-note compatibility example:
  `Compatibility:`, `- Multi Commander 15.8`, `- Windows 10/11 x64`.
- `## Wymagania do samodzielnego utworzenia DLL`
- Requirements: Windows 10/11, Visual Studio 2022 or Build Tools 2022, `Desktop development with C++`, MSVC v143, Windows 10/11 SDK, PowerShell 5.1+, and internet for first SDK download unless `external\MultiCommander-SDK-main` already exists.

- [ ] **Step 2: Run helper tests**

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\Run-Tests.ps1
```

Expected: PASS.

### Task 7: Build and Verify

**Files:**
- All modified files

- [ ] **Step 1: Ensure SDK is available**

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\01_download_sdk.ps1
```

Expected: SDK exists under `external\MultiCommander-SDK-main`.

- [ ] **Step 2: Build with explicit plugin version**

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\02_build.ps1 -Platform x64 -Configuration Release -PluginVersion 1.0.0
```

Expected: `bin\x64\Release\MCRealDiskSize.dll` exists.

- [ ] **Step 3: Build release ZIP**

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\New-ReleasePackage.ps1 -Version 1.0.0 -Platform x64 -Configuration Release
```

Expected: `artifacts\release\MCRealDiskSize-v1.0.0-x64.zip` exists and contains `MCRealDiskSize/MCRealDiskSize.dll`.

- [ ] **Step 4: Run final tests**

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\Run-Tests.ps1
```

Expected: PASS.

- [ ] **Step 5: Review diff**

Run:

```powershell
git diff --stat
git diff -- . ':!external' ':!bin' ':!obj' ':!artifacts'
```

Expected: changes are limited to scripts, workflow, tests, source, project, README, and plan docs.
