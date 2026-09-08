[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string] $SourceRoot,

    [Parameter(Mandatory = $true)]
    [string] $StandardConfigRoot,

    [Parameter(Mandatory = $true)]
    [string] $PlatformPatch,

    [Parameter(Mandatory = $true)]
    [string] $BaseNoVsArchive,

    [Parameter(Mandatory = $true)]
    [string] $BaseFullArchive,

    [Parameter(Mandatory = $true)]
    [string] $OutputDirectory,

    [Parameter(Mandatory = $true)]
    [string] $Version,

    [string] $Platform = 'windows',

    [string] $MpvRoot,

    [string] $UmpvPath,

    [string] $YtDlpPath,

    [string] $SfxModule,

    [string[]] $VsNvArchives = @(),

    [switch] $IncludeVsNv
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Resolve-FullPath([string] $Path) {
    return [System.IO.Path]::GetFullPath($Path)
}

function Invoke-7Zip([string[]] $Arguments) {
    # Keep the helper's output out of callers that capture its return value,
    # notably Extract-Package, which must return only the package root path.
    & 7z @Arguments | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "7-Zip failed with exit code ${LASTEXITCODE}: $($Arguments -join ' ')"
    }
}

function Ensure-Directory([string] $Path) {
    New-Item -ItemType Directory -Path $Path -Force | Out-Null
}

function Copy-RequiredFile([string] $Source, [string] $Destination) {
    if (-not (Test-Path -LiteralPath $Source -PathType Leaf)) {
        throw "Required file does not exist: $Source"
    }
    Ensure-Directory (Split-Path -Parent $Destination)
    Copy-Item -LiteralPath $Source -Destination $Destination -Force | Out-Null
}

function Find-RequiredFile([string] $Root, [string] $Name) {
    $match = Get-ChildItem -LiteralPath $Root -Filter $Name -File -Recurse | Select-Object -First 1
    if ($null -eq $match) {
        throw "Could not find $Name below $Root"
    }
    return $match.FullName
}

function Extract-Package([string] $Archive, [string] $Destination) {
    Ensure-Directory $Destination
    Invoke-7Zip @('x', '-y', "-o$Destination", $Archive)
    $packageRoot = Join-Path $Destination 'mpv-lazy'
    if (-not (Test-Path -LiteralPath $packageRoot -PathType Container)) {
        throw "The archive did not contain the expected mpv-lazy directory: $Archive"
    }
    return $packageRoot
}

function Apply-ConfigurationPatch([string] $ConfigRoot, [string] $PatchFile) {
    if (-not (Test-Path -LiteralPath $PatchFile -PathType Leaf)) {
        throw "Platform patch is missing: $PatchFile"
    }
    $gitCommand = Get-Command git -ErrorAction Stop
    Push-Location $ConfigRoot
    try {
        & $gitCommand.Source apply --no-index --ignore-space-change --ignore-whitespace --whitespace=nowarn $PatchFile
    } finally {
        Pop-Location
    }
    if ($LASTEXITCODE -ne 0) {
        throw "Could not apply platform patch: $PatchFile"
    }
}

function Prepare-PortableConfig(
    [string] $PackageRoot,
    [bool] $KeepVs
) {
    $standardConfig = Resolve-FullPath $StandardConfigRoot
    $packageConfig = Join-Path $PackageRoot 'portable_config'

    if (-not (Test-Path -LiteralPath $standardConfig -PathType Container)) {
        throw "The standard portable_config is missing: $standardConfig"
    }

    if (Test-Path -LiteralPath $packageConfig) {
        Remove-Item -LiteralPath $packageConfig -Recurse -Force
    }
    Copy-Item -LiteralPath $standardConfig -Destination $PackageRoot -Recurse -Force | Out-Null
    Apply-ConfigurationPatch -ConfigRoot $packageConfig -PatchFile $PlatformPatch

    if (-not $KeepVs) {
        $vsPath = Join-Path $packageConfig 'vs'
        if (Test-Path -LiteralPath $vsPath) {
            Remove-Item -LiteralPath $vsPath -Recurse -Force
        }
    }

    foreach ($cacheName in @('icc', 'shader', 'usubs', 'watch_later')) {
        Ensure-Directory (Join-Path $packageConfig "_cache/$cacheName")
    }
}

function Prepare-Package(
    [string] $PackageRoot,
    [bool] $KeepVs
) {
    Prepare-PortableConfig -PackageRoot $PackageRoot -KeepVs $KeepVs

    $sourceInstaller = Join-Path $SourceRoot 'installer'
    $packageInstaller = Join-Path $PackageRoot 'installer'
    Ensure-Directory $packageInstaller

    # The lazy package deliberately ships this subset of the repository's
    # installer helpers. mpv-install.bat/mpv-uninstall.bat and input mode are
    # source-repo utilities, not part of the published lazy package.
    $installerFiles = @(
        'mpv-BenchMark.conf',
        'mpv-icon.ico',
        'mpv-register.bat',
        'mpv-test.conf',
        'mpv-unregister.bat',
        'mpv-测试模式.bat',
        'mpv-纯净模式.bat',
        'mpv-跑分模式.bat',
        'umpv-install.bat',
        'umpv-uninstall.bat'
    )
    foreach ($fileName in $installerFiles) {
        Copy-RequiredFile (Join-Path $sourceInstaller $fileName) (Join-Path $packageInstaller $fileName)
    }

    foreach ($rootFile in @('README.MD', 'LICENSE.MD', 'umpv.conf')) {
        Copy-RequiredFile (Join-Path $SourceRoot $rootFile) (Join-Path $PackageRoot $rootFile)
    }

    if (-not [string]::IsNullOrWhiteSpace($MpvRoot)) {
        Copy-RequiredFile (Find-RequiredFile $MpvRoot 'mpv.exe') (Join-Path $PackageRoot 'mpv.exe')
        Copy-RequiredFile (Find-RequiredFile $MpvRoot 'mpv.com') (Join-Path $PackageRoot 'mpv.com')
    }
    if (-not [string]::IsNullOrWhiteSpace($UmpvPath)) {
        Copy-RequiredFile $UmpvPath (Join-Path $PackageRoot 'umpv.exe')
    }
    if (-not [string]::IsNullOrWhiteSpace($YtDlpPath)) {
        Copy-RequiredFile $YtDlpPath (Join-Path $PackageRoot 'yt-dlp.exe')
    }
}

function New-7zPackage([string] $PackageRoot, [string] $ArchivePath) {
    $parent = Split-Path -Parent $PackageRoot
    $name = Split-Path -Leaf $PackageRoot
    Push-Location $parent
    try {
        Invoke-7Zip @('a', '-t7z', '-mx=9', $ArchivePath, $name)
    } finally {
        Pop-Location
    }
}

function New-SfxPackage([string] $PackageRoot, [string] $ArchivePath) {
    if ([string]::IsNullOrWhiteSpace($SfxModule) -or -not (Test-Path -LiteralPath $SfxModule -PathType Leaf)) {
        throw 'A 7-Zip SFX module is required to build the standard .exe package.'
    }
    $parent = Split-Path -Parent $PackageRoot
    $name = Split-Path -Leaf $PackageRoot
    Push-Location $parent
    try {
        Invoke-7Zip @('a', '-t7z', '-mx=9', "-sfx$SfxModule", $ArchivePath, $name)
    } finally {
        Pop-Location
    }
}

$SourceRoot = Resolve-FullPath $SourceRoot
$StandardConfigRoot = Resolve-FullPath $StandardConfigRoot
$PlatformPatch = Resolve-FullPath $PlatformPatch
$BaseNoVsArchive = Resolve-FullPath $BaseNoVsArchive
$BaseFullArchive = Resolve-FullPath $BaseFullArchive
$OutputDirectory = Resolve-FullPath $OutputDirectory
if (-not [string]::IsNullOrWhiteSpace($MpvRoot)) { $MpvRoot = Resolve-FullPath $MpvRoot }
if (-not [string]::IsNullOrWhiteSpace($UmpvPath)) { $UmpvPath = Resolve-FullPath $UmpvPath }
if (-not [string]::IsNullOrWhiteSpace($YtDlpPath)) { $YtDlpPath = Resolve-FullPath $YtDlpPath }
if (-not [string]::IsNullOrWhiteSpace($SfxModule)) { $SfxModule = Resolve-FullPath $SfxModule }
$VsNvArchives = @($VsNvArchives | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { Resolve-FullPath $_ })

if (Test-Path -LiteralPath $OutputDirectory) {
    Remove-Item -LiteralPath $OutputDirectory -Recurse -Force
}
Ensure-Directory $OutputDirectory
$workDirectory = Join-Path $OutputDirectory '_work'
Ensure-Directory $workDirectory

$noVsRoot = Extract-Package $BaseNoVsArchive (Join-Path $workDirectory 'noVS')
$fullRoot = Extract-Package $BaseFullArchive (Join-Path $workDirectory 'full')

Prepare-Package -PackageRoot $noVsRoot -KeepVs $false
Prepare-Package -PackageRoot $fullRoot -KeepVs $true

$noVsArchive = Join-Path $OutputDirectory "mpv-lazy-$Version-noVS.7z"
$standardExe = Join-Path $OutputDirectory "mpv-lazy-$Version.exe"
New-7zPackage -PackageRoot $noVsRoot -ArchivePath $noVsArchive
New-SfxPackage -PackageRoot $fullRoot -ArchivePath $standardExe

if ($IncludeVsNv) {
    if ($VsNvArchives.Count -eq 0) {
        throw 'IncludeVsNv was requested, but no vsNV archive volumes were supplied.'
    }
    foreach ($archive in $VsNvArchives) {
        if (-not (Test-Path -LiteralPath $archive -PathType Leaf)) {
            throw "vsNV archive volume does not exist: $archive"
        }
        $leaf = Split-Path -Leaf $archive
        $suffix = [Regex]::Match($leaf, '\.7z\.\d+$').Value
        if ([string]::IsNullOrWhiteSpace($suffix)) {
            throw "Unexpected vsNV volume name: $leaf"
        }
        Copy-Item -LiteralPath $archive -Destination (Join-Path $OutputDirectory "mpv-lazy-$Version-vsNV$suffix") -Force | Out-Null
    }
}

$metadata = @(
    "release=$Version",
    "source_commit=$((git -C $SourceRoot rev-parse HEAD).Trim())",
    'standard_config=packaging/portable_config',
    'platform_patch=packaging/windows.patch',
    "base_noVS=$(Split-Path -Leaf $BaseNoVsArchive)",
    "base_full=$(Split-Path -Leaf $BaseFullArchive)",
    "include_vsnv=$($IncludeVsNv.IsPresent)"
)
$metadata | Set-Content -LiteralPath (Join-Path $OutputDirectory "BUILD-METADATA-$Platform.txt") -Encoding UTF8

$checksums = Get-ChildItem -LiteralPath $OutputDirectory -File |
    Where-Object { $_.Name -ne "SHA256SUMS-$Platform.txt" } |
    Sort-Object Name |
    ForEach-Object {
        $hash = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        "$hash  $($_.Name)"
    }
$checksums | Set-Content -LiteralPath (Join-Path $OutputDirectory "SHA256SUMS-$Platform.txt") -Encoding ASCII

Remove-Item -LiteralPath $workDirectory -Recurse -Force
Write-Host "Built release assets in $OutputDirectory"
