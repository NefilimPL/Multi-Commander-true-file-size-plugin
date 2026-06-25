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

Assert-True ($allocatedColumnRegistration -match "FILEPROP_STRING") `
    "The visible allocated-size column must stay FILEPROP_STRING because Multi Commander 15.8 does not reliably render this plugin's numeric columns."
Assert-False ($allocatedColumnRegistration -match "FILEPROP_NUM") `
    "The visible allocated-size column must not be FILEPROP_NUM until the Multi Commander numeric rendering issue is resolved."
Assert-False ($allocatedColumnRegistration -match "FILEPROP_FORMATDISP") `
    "The visible allocated-size column must not rely on numeric FormatDisplayValue."
Assert-False ($allocatedColumnRegistration -match "FILEPROP_DONOTCACHEASDISPLAY") `
    "The visible allocated-size column must not rely on GetDisplayValue; Multi Commander 15.8 leaves that path blank for this plugin."

$displayValueFunction = Get-Section `
    -Text $propSource `
    -StartPattern "bool MCRealDiskSizeProp::GetDisplayValue\([^\)]*\)\s*\{" `
    -EndPattern "bool MCRealDiskSizeProp::GetPropStr" `
    -Message "Could not find GetDisplayValue."

Assert-False ($displayValueFunction -match "PROP_REAL_DISK_SIZE") `
    "The visible allocated-size column must not depend on GetDisplayValue because that rendered blank in Multi Commander 15.8."

$stringValueBranch = Get-Section `
    -Text $propSource `
    -StartPattern "if\s*\(PropertyId\s*==\s*PROP_REAL_DISK_SIZE\s*\|\|\s*PropertyId\s*==\s*PROP_REAL_DISK_SIZE_RAW\)\s*\{" `
    -EndPattern "if\s*\(PropertyId\s*==\s*PROP_CLOUD_STATUS\)" `
    -Message "Could not find the string value branch for size columns."

Assert-True ($stringValueBranch -match "PropertyId\s*==\s*PROP_REAL_DISK_SIZE_RAW") `
    "GetPropStr must keep a separate RAW branch for the zero-padded byte sort key."
Assert-True ($stringValueBranch -match "StringCchPrintfW\(propData,\s*nLen,\s*L`"%020llu`",\s*result\.bytes\)") `
    "RAW must return a zero-padded byte string so text sorting remains numeric there."
Assert-True ($stringValueBranch -match "FormatSortableBytes\(result\.bytes\)" -and $stringValueBranch -match "StringCchCopyW\(propData,\s*nLen,\s*formatted\.c_str\(\)\)") `
    "The visible allocated-size column must return sortable readable text directly from GetPropStr."

Assert-True ($diskSource -match "std::wstring\s+FormatSortableBytes\(unsigned long long bytes\)") `
    "DiskSizeUtil must expose a sortable formatter for the visible allocated-size column."
Assert-True ($diskSource -match "sortablePrefix" -and $diskSource -match "unitIndex") `
    "The sortable formatter must include a unit-order prefix so GB sorts after MB/KB as text."
Assert-True ($diskSource -match "StringCchPrintfW\(buffer,\s*ARRAYSIZE\(buffer\),\s*L`"%u: %07\.2f %s`"") `
    "The sortable formatter must use fixed-width numeric text so values in the same unit sort numerically."

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
