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
$propHeader = Get-Content -LiteralPath (Join-Path $repoRoot "src\MCRealDiskSizeProp.h") -Raw
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
Assert-True ($stringValueBranch -match "FormatBytes\(result\.bytes\)" -and $stringValueBranch -match "StringCchCopyW\(propData,\s*nLen,\s*formatted\.c_str\(\)\)") `
    "The visible allocated-size column must return only readable text directly from GetPropStr."
Assert-False ($stringValueBranch -match "FormatSortableBytes") `
    "The visible allocated-size column must not prepend hidden sort keys; Multi Commander 15.8 can crash after refresh when cached column text contains hidden Unicode tag characters."
Assert-False ($diskSource -match "0xE0030u" -or $diskSource -match "0xE007Fu" -or $diskSource -match "AppendUnicodeTagDigit" -or $diskSource -match "MakeHiddenSortKey") `
    "The plugin must not generate Unicode tag-character sort keys for visible column text."
Assert-False ($diskSource -match "L`"%u: %07\.2f %s`"" -or $diskSource -match "sortablePrefix") `
    "The visible allocated-size column must not show technical sort prefixes such as '3:' or fixed-width values."

$vtableTailSection = Get-Section `
    -Text $propHeader `
    -StartPattern "bool SetProp\(IFileItem\* pFileItem,\s*WORD PropertyId,\s*const BYTE\* propData\) override;" `
    -EndPattern "private:" `
    -Message "Could not find the tail of MCRealDiskSizeProp's virtual method declarations."

Assert-True ($vtableTailSection -match "bool Execute\(ExecuteInfo\* pExecuteInfo\) override;") `
    "MCRealDiskSizeProp must explicitly keep Execute at the end of the public SDK 2.4 IFileProperties vtable."
Assert-True ($vtableTailSection -match "virtual bool ReservedForMultiCommander25VTable0\(IFileItem\* pFileItem\);" -and
             $vtableTailSection -match "virtual bool ReservedForMultiCommander25VTable1\(IFileItem\* pFileItem\);") `
    "MCRealDiskSizeProp must reserve two additional tail vtable slots because Multi Commander 15.8 calls an IFileProperties entry at vtable offset +0x78 during refresh."
Assert-True ($propSource -match "bool MCRealDiskSizeProp::ReservedForMultiCommander25VTable0\(IFileItem\* /\*pFileItem\*/\)\s*\{\s*return false;\s*\}" -and
             $propSource -match "bool MCRealDiskSizeProp::ReservedForMultiCommander25VTable1\(IFileItem\* /\*pFileItem\*/\)\s*\{\s*return false;\s*\}") `
    "The Multi Commander 15.8 reserved vtable slots must be implemented as safe no-op methods."

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
