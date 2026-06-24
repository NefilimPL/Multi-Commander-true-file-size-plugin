$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot

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

function Get-Section {
    param(
        [Parameter(Mandatory = $true)] [string] $Text,
        [Parameter(Mandatory = $true)] [string] $StartPattern,
        [Parameter(Mandatory = $true)] [string] $EndPattern,
        [Parameter(Mandatory = $true)] [string] $Message
    )

    $match = [regex]::Match($Text, "$StartPattern(?<section>[\s\S]*?)$EndPattern")
    if (-not $match.Success) {
        throw $Message
    }

    return $match.Groups["section"].Value
}

$propSource = Get-Content -LiteralPath (Join-Path $repoRoot "src\MCRealDiskSizeProp.cpp") -Raw
$diskSource = Get-Content -LiteralPath (Join-Path $repoRoot "src\DiskSizeUtil.cpp") -Raw

$allocatedColumnRegistration = Get-Section `
    -Text $propSource `
    -StartPattern "fpd\.PropertyId\s*=\s*PROP_REAL_DISK_SIZE;" `
    -EndPattern "propMan->RegisterProperty\(&fpd\);" `
    -Message "Could not find the allocated-size column registration."

Assert-True ($allocatedColumnRegistration -match "FILEPROP_NUM") `
    "The visible allocated-size column must be registered as FILEPROP_NUM so Multi Commander sorts it numerically."
Assert-True ($allocatedColumnRegistration -match "FILEPROP_FORMATDISP") `
    "The visible allocated-size column must use FILEPROP_FORMATDISP so the numeric sort value still displays as a readable size."
Assert-False ($allocatedColumnRegistration -match "FILEPROP_STRING") `
    "The visible allocated-size column must not be FILEPROP_STRING, because text sorting puts values like 150 MB above 2 GB."

$allocatedFileFunction = Get-Section `
    -Text $diskSource `
    -StartPattern "SizeResult GetAllocatedSizeForFile\([^\)]*\)\s*\{" `
    -EndPattern "bool ShouldSkipDirectoryReparsePoint" `
    -Message "Could not find GetAllocatedSizeForFile."

$cloudCheckIndex = $allocatedFileFunction.IndexOf("IsSparseCompressedOrCloud(attrs)")
$compressedCallIndex = $allocatedFileFunction.IndexOf("GetCompressedSize(path)")

Assert-True ($cloudCheckIndex -ge 0) "GetAllocatedSizeForFile should branch on sparse/compressed/cloud attributes."
Assert-True ($compressedCallIndex -ge 0) "GetAllocatedSizeForFile should still use GetCompressedFileSizeW for sparse/compressed/cloud files."
Assert-True ($cloudCheckIndex -lt $compressedCallIndex) `
    "Regular files should not call GetCompressedFileSizeW before the sparse/compressed/cloud check."

Assert-True ($diskSource -match "clusterSizeCache") `
    "Cluster size lookup should be cached per volume instead of calling GetDiskFreeSpaceW for every regular file."
Assert-True ($propSource -match "GetExtraPropData" -and $propSource -match "SetExtraPropData") `
    "Allocated-size results should be cached on IFileItem so visible and RAW columns do not recalculate the same item."
