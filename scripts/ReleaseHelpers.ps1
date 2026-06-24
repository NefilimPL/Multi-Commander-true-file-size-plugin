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
