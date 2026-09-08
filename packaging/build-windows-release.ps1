[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string] $SourceRoot,

    [Parameter(Mandatory = $true)]
    [string] $CommonConfigRoot,

    [Parameter(Mandatory = $true)]
    [string] $WindowsPatch,

    [Parameter(Mandatory = $true)]
    [string] $MpvArchive,

    [Parameter(Mandatory = $true)]
    [string] $UmpvPath,

    [Parameter(Mandatory = $true)]
    [string] $YtDlpPath,

    [Parameter(Mandatory = $true)]
    [string] $VapourSynthArchive,

    [Parameter(Mandatory = $true)]
    [string] $K7sfuncWheel,

    [Parameter(Mandatory = $true)]
    [string[]] $VsCpuArchives,

    [string[]] $VsNvArchives = @(),

    [Parameter(Mandatory = $true)]
    [string] $PythonRoot,

    [Parameter(Mandatory = $true)]
    [string] $OutputDirectory,

    [Parameter(Mandatory = $true)]
    [string] $Version,

    [Parameter(Mandatory = $true)]
    [string] $SfxModule,

    [switch] $IncludeVsNv
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Resolve-FullPath([string] $Path) {
    return [System.IO.Path]::GetFullPath($Path)
}

function Ensure-Directory([string] $Path) {
    New-Item -ItemType Directory -Path $Path -Force | Out-Null
}

function Invoke-7Zip([string[]] $Arguments) {
    & 7z @Arguments | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "7-Zip failed with exit code ${LASTEXITCODE}: $($Arguments -join ' ')"
    }
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

function Copy-DirectoryContents([string] $Source, [string] $Destination) {
    Ensure-Directory $Destination
    foreach ($item in Get-ChildItem -LiteralPath $Source -Force) {
        Copy-Item -LiteralPath $item.FullName -Destination $Destination -Recurse -Force | Out-Null
    }
}

function Apply-ConfigurationPatch([string] $ConfigRoot, [string] $PatchFile) {
    $gitCommand = Get-Command git -ErrorAction Stop
    Push-Location $ConfigRoot
    try {
        & $gitCommand.Source apply --no-index --ignore-space-change --ignore-whitespace --whitespace=nowarn $PatchFile
    } finally {
        Pop-Location
    }
    if ($LASTEXITCODE -ne 0) {
        throw "Could not apply Windows configuration patch: $PatchFile"
    }
}

function Initialize-Package([string] $PackageRoot, [bool] $KeepVs) {
    Ensure-Directory $PackageRoot
    $sourceConfig = Join-Path $CommonConfigRoot 'portable_config'
    $packageConfig = Join-Path $PackageRoot 'portable_config'
    if (-not (Test-Path -LiteralPath $sourceConfig -PathType Container)) {
        throw "Common portable_config is missing: $sourceConfig"
    }
    Copy-Item -LiteralPath $sourceConfig -Destination $PackageRoot -Recurse -Force | Out-Null
    Apply-ConfigurationPatch -ConfigRoot $packageConfig -PatchFile $WindowsPatch
    if (-not $KeepVs) {
        $vsConfig = Join-Path $packageConfig 'vs'
        if (Test-Path -LiteralPath $vsConfig) {
            Remove-Item -LiteralPath $vsConfig -Recurse -Force
        }
    }

    foreach ($cacheName in @('icc', 'shader', 'usubs', 'watch_later')) {
        Ensure-Directory (Join-Path $packageConfig "_cache/$cacheName")
    }

    $externalSources = Join-Path $CommonConfigRoot 'EXTERNAL-SOURCES.txt'
    if (Test-Path -LiteralPath $externalSources -PathType Leaf) {
        Copy-RequiredFile $externalSources (Join-Path $PackageRoot 'EXTERNAL-SOURCES.txt')
    }

    $sourceInstaller = Join-Path $SourceRoot 'installer'
    $packageInstaller = Join-Path $PackageRoot 'installer'
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
}

function Add-MpvRuntime([string] $PackageRoot, [string] $Archive, [string] $Umpv, [string] $YtDlp, [string] $StageRoot) {
    $stage = Join-Path $StageRoot 'mpv'
    Ensure-Directory $stage
    Invoke-7Zip @('x', '-y', "-o$stage", $Archive)
    Copy-RequiredFile (Find-RequiredFile $stage 'mpv.exe') (Join-Path $PackageRoot 'mpv.exe')
    Copy-RequiredFile (Find-RequiredFile $stage 'mpv.com') (Join-Path $PackageRoot 'mpv.com')
    Copy-RequiredFile (Find-RequiredFile $stage 'manual.pdf') (Join-Path $PackageRoot 'mpv_manual.pdf')
    Copy-RequiredFile $Umpv (Join-Path $PackageRoot 'umpv.exe')
    Copy-RequiredFile $YtDlp (Join-Path $PackageRoot 'yt-dlp.exe')
}

function Add-VapourSynthRuntime([string] $PackageRoot, [string] $Archive, [string] $Wheel, [string] $StageRoot) {
    $pythonExe = Join-Path $PythonRoot 'python.exe'
    if (-not (Test-Path -LiteralPath $pythonExe -PathType Leaf)) {
        throw "Python executable is missing: $pythonExe"
    }

    # The hosted Python installation is copied into the package, then the
    # official VapourSynth wheel and the maintained K7sfunc wheel are installed
    # into that private site-packages directory.
    Copy-DirectoryContents $PythonRoot $PackageRoot
    $sitePackages = Join-Path $PackageRoot 'Lib/site-packages'
    Ensure-Directory $sitePackages

    $vsStage = Join-Path $StageRoot 'vapoursynth'
    Ensure-Directory $vsStage
    Expand-Archive -LiteralPath $Archive -DestinationPath $vsStage -Force
    $vsWheel = Get-ChildItem -LiteralPath $vsStage -Filter 'vapoursynth-*.whl' -File -Recurse | Select-Object -First 1
    if ($null -eq $vsWheel) {
        throw "Could not find the VapourSynth wheel in $Archive"
    }

    & $pythonExe -m pip install --disable-pip-version-check --no-warn-script-location --no-cache-dir --no-deps --target $sitePackages $vsWheel.FullName $Wheel
    if ($LASTEXITCODE -ne 0) {
        throw 'Could not install VapourSynth/K7sfunc wheels'
    }
    & $pythonExe -m pip install --disable-pip-version-check --no-warn-script-location --no-cache-dir --target $sitePackages 'numpy<3' onnx
    if ($LASTEXITCODE -ne 0) {
        throw 'Could not install the Python AI dependencies'
    }

    $vsPythonRoot = Join-Path $sitePackages 'vapoursynth'
    foreach ($runtimeFile in @('libvapoursynth.dll', 'vsscript.dll', 'vspipe.exe', 'vsvfw.dll')) {
        Copy-RequiredFile (Join-Path $vsPythonRoot $runtimeFile) (Join-Path $PackageRoot $runtimeFile)
    }
    $corePluginRoot = Join-Path $vsPythonRoot 'plugins'
    if (Test-Path -LiteralPath $corePluginRoot -PathType Container) {
        Copy-DirectoryContents $corePluginRoot (Join-Path $PackageRoot 'vs-coreplugins')
    }
    New-Item -ItemType File -Path (Join-Path $PackageRoot 'portable.vs') -Force | Out-Null
}

function Merge-VsArchive([string] $Archive, [string] $PackageRoot, [string] $StageRoot) {
    $name = [System.IO.Path]::GetFileNameWithoutExtension($Archive)
    $stage = Join-Path $StageRoot ("vs-" + $name.Replace('.', '_'))
    Ensure-Directory $stage
    Invoke-7Zip @('x', '-y', "-o$stage", $Archive)

    $pluginRoot = Join-Path $PackageRoot 'vs-plugins'
    $scriptRoot = Join-Path $PackageRoot 'vs-scripts'
    Ensure-Directory $pluginRoot
    Ensure-Directory $scriptRoot
    foreach ($file in Get-ChildItem -LiteralPath $stage -File -Recurse) {
        $relative = [System.IO.Path]::GetRelativePath($stage, $file.FullName)
        if ($file.Name -eq 'vsmlrt.py') {
            Copy-RequiredFile $file.FullName (Join-Path $scriptRoot $file.Name)
        } else {
            Copy-RequiredFile $file.FullName (Join-Path $pluginRoot $relative)
        }
    }
}

function New-7zPackage([string] $PackageRoot, [string] $ArchivePath, [string] $VolumeSize = '') {
    $parent = Split-Path -Parent $PackageRoot
    $name = Split-Path -Leaf $PackageRoot
    Push-Location $parent
    try {
        $arguments = @('a', '-t7z', '-mx=9')
        if (-not [string]::IsNullOrWhiteSpace($VolumeSize)) {
            $arguments += "-v$VolumeSize"
        }
        $arguments += @($ArchivePath, $name)
        Invoke-7Zip $arguments
    } finally {
        Pop-Location
    }
}

function New-SfxPackage([string] $PackageRoot, [string] $ArchivePath) {
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
$CommonConfigRoot = Resolve-FullPath $CommonConfigRoot
$WindowsPatch = Resolve-FullPath $WindowsPatch
$MpvArchive = Resolve-FullPath $MpvArchive
$UmpvPath = Resolve-FullPath $UmpvPath
$YtDlpPath = Resolve-FullPath $YtDlpPath
$VapourSynthArchive = Resolve-FullPath $VapourSynthArchive
$K7sfuncWheel = Resolve-FullPath $K7sfuncWheel
$PythonRoot = Resolve-FullPath $PythonRoot
$OutputDirectory = Resolve-FullPath $OutputDirectory
$SfxModule = Resolve-FullPath $SfxModule
$VsCpuArchives = @($VsCpuArchives | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { Resolve-FullPath $_ })
$VsNvArchives = @($VsNvArchives | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { Resolve-FullPath $_ })

foreach ($requiredPath in @($MpvArchive, $UmpvPath, $YtDlpPath, $VapourSynthArchive, $K7sfuncWheel, $SfxModule)) {
    if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
        throw "Required external asset does not exist: $requiredPath"
    }
}
foreach ($archive in $VsCpuArchives) {
    if (-not (Test-Path -LiteralPath $archive -PathType Leaf)) {
        throw "CPU VS archive does not exist: $archive"
    }
}
if ($IncludeVsNv -and $VsNvArchives.Count -eq 0) {
    throw 'IncludeVsNv was requested, but no VS NV archives were supplied.'
}

if (Test-Path -LiteralPath $OutputDirectory) {
    Remove-Item -LiteralPath $OutputDirectory -Recurse -Force
}
Ensure-Directory $OutputDirectory
$workDirectory = Join-Path $OutputDirectory '_work'
Ensure-Directory $workDirectory

$noVsRoot = Join-Path $workDirectory 'noVS/mpv-lazy'
$standardRoot = Join-Path $workDirectory 'standard/mpv-lazy'
$vsNvRoot = Join-Path $workDirectory 'vsNV/mpv-lazy'

Initialize-Package $noVsRoot $false
Add-MpvRuntime $noVsRoot $MpvArchive $UmpvPath $YtDlpPath $workDirectory

Initialize-Package $standardRoot $true
Add-MpvRuntime $standardRoot $MpvArchive $UmpvPath $YtDlpPath $workDirectory
Add-VapourSynthRuntime $standardRoot $VapourSynthArchive $K7sfuncWheel $workDirectory
foreach ($archive in $VsCpuArchives) {
    Merge-VsArchive $archive $standardRoot $workDirectory
}

$noVsArchive = Join-Path $OutputDirectory "mpv-lazy-$Version-noVS.7z"
$standardExe = Join-Path $OutputDirectory "mpv-lazy-$Version.exe"
New-7zPackage $noVsRoot $noVsArchive
New-SfxPackage $standardRoot $standardExe

if ($IncludeVsNv) {
    Initialize-Package $vsNvRoot $true
    foreach ($archive in $VsNvArchives) {
        Merge-VsArchive $archive $vsNvRoot $workDirectory
    }
    $vsNvArchive = Join-Path $OutputDirectory "mpv-lazy-$Version-vsNV.7z"
    New-7zPackage $vsNvRoot $vsNvArchive '1900m'
}

$metadata = @(
    "release=$Version",
    "source_commit=$((git -C $SourceRoot rev-parse HEAD).Trim())",
    'common_config=packaging/portable_config plus external source overlay',
    'windows_patch=packaging/windows.patch',
    "mpv_archive=$(Split-Path -Leaf $MpvArchive)",
    "vapoursynth_archive=$(Split-Path -Leaf $VapourSynthArchive)",
    "k7sfunc_wheel=$(Split-Path -Leaf $K7sfuncWheel)",
    "vs_cpu_archives=$($VsCpuArchives.Count)",
    "vs_nv_archives=$($VsNvArchives.Count)",
    "include_vsnv=$($IncludeVsNv.IsPresent)"
)
$metadata | Set-Content -LiteralPath (Join-Path $OutputDirectory 'BUILD-METADATA-windows.txt') -Encoding UTF8

$checksums = Get-ChildItem -LiteralPath $OutputDirectory -File |
    Where-Object { $_.Name -ne 'SHA256SUMS-windows.txt' } |
    Sort-Object Name |
    ForEach-Object {
        $hash = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        "$hash  $($_.Name)"
    }
$checksums | Set-Content -LiteralPath (Join-Path $OutputDirectory 'SHA256SUMS-windows.txt') -Encoding ASCII

Remove-Item -LiteralPath $workDirectory -Recurse -Force
Write-Host "Built Windows release assets in $OutputDirectory"
