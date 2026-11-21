# Compiles src/shaders/*.fxc into .vcs archives and .inc combo headers.
#
# Native PowerShell equivalent of tools/build_shaders.sh, for machines without
# CMake or Python's python3 alias. Outputs:
#   build/inc/*.inc                         (consumed by the C++ shader)
#   dist/left4dead2/shaders/fxc/*.vcs       (installed with the DLL)
#
# Adding a shader variant means adding its prefix to $Pairs below and to
# CMakeLists.txt. The C++ and the .inc must always be rebuilt together.

[CmdletBinding()]
param(
    [string]$Python = '',
    [string]$Perl = '',
    [string]$Fxc = '',
    [string]$SdkInclude = ''
)

$ErrorActionPreference = 'Stop'

$Root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$Pairs = @('pulse_pbr', 'pulse_girlsfrontline', 'pulse_npr', 'pulse_umamusume', 'pulse_tooneye')

function New-Directory([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path | Out-Null
    }
}

function Resolve-Python {
    if ($Python) { return $Python }
    $cmd = Get-Command python.exe -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $cmd = Get-Command python3.exe -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $cmd = Get-Command py.exe -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    throw 'Python 3 was not found. Pass -Python <python.exe> or install Python 3.'
}

function Resolve-Perl {
    if ($Perl) { return $Perl }
    $cmd = Get-Command perl.exe -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $candidates = @(
        (Join-Path $env:ProgramFiles 'Git\usr\bin\perl.exe'),
        (Join-Path ${env:ProgramFiles(x86)} 'Git\usr\bin\perl.exe')
    )
    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate) { return $candidate }
    }
    throw 'Perl was not found. Install Git for Windows or pass -Perl <perl.exe>.'
}

function Resolve-Fxc {
    if ($Fxc) { return $Fxc }
    $roots = @()
    if ($env:WindowsSdkDir -and $env:WindowsSDKVersion) {
        $roots += (Join-Path (Join-Path $env:WindowsSdkDir "bin\$env:WindowsSDKVersion") 'x64')
    }
    $kitRoot = 'C:\Program Files (x86)\Windows Kits\10\bin'
    if (Test-Path -LiteralPath $kitRoot) {
        $versions = Get-ChildItem -LiteralPath $kitRoot -Directory |
            Where-Object { $_.Name -match '^10\.' } |
            Sort-Object Name -Descending
        foreach ($version in $versions) { $roots += (Join-Path $version.FullName 'x64') }
    }
    foreach ($root in $roots) {
        $candidate = Join-Path $root 'fxc.exe'
        if (Test-Path -LiteralPath $candidate) { return $candidate }
    }
    throw 'fxc.exe was not found. Install the Windows SDK or pass -Fxc <fxc.exe>.'
}

$Python = Resolve-Python
$Perl = Resolve-Perl
$Fxc = Resolve-Fxc
if (-not $SdkInclude) { $SdkInclude = Join-Path $Root 'sdk\valve-stdshaders' }

$Prep = Join-Path $Root 'sdk\alienswarm-sdk\src\devtools\bin\fxc_prep.pl'
$PrepDir = Split-Path -Parent $Prep
$VcsPack = Join-Path $Root 'tools\vcspack.py'
$SrcDir = Join-Path $Root 'src\shaders'
$Work = Join-Path $Root 'build\shaderwork'
$IncDir = Join-Path $Root 'build\inc'
$VcsDir = Join-Path $Root 'dist\left4dead2\shaders\fxc'

foreach ($required in @($Prep, $VcsPack, $SrcDir)) {
    if (-not (Test-Path -LiteralPath $required)) {
        throw "Required build input not found: $required"
    }
}
if (-not (Test-Path -LiteralPath $SdkInclude)) {
    throw "Shader include directory not found: $SdkInclude"
}

Write-Host "=== PulseShader shader build ==="
Write-Host "python: $Python"
Write-Host "perl:   $Perl"
Write-Host "fxc:    $Fxc"

# A stale work dir or stale .inc is worse than none: fxc_prep.pl appends to
# filelistgen.txt in its cwd, and the C++ build must never consume a header from
# a previous variant set.
if (Test-Path -LiteralPath $Work) { Remove-Item -LiteralPath $Work -Recurse -Force }
New-Directory $Work
New-Directory $IncDir
New-Directory $VcsDir

foreach ($prefix in $Pairs) {
    $dir = Join-Path $Work $prefix
    New-Directory $dir

    Copy-Item -LiteralPath (Join-Path $SrcDir "${prefix}_vs30.fxc") -Destination $dir
    Copy-Item -LiteralPath (Join-Path $SrcDir "${prefix}_ps30.fxc") -Destination $dir
    Get-ChildItem -LiteralPath $SrcDir -Filter '*.h' | Copy-Item -Destination $dir

    Write-Host ""
    Write-Host "--- $prefix ---"
    Push-Location $dir
    try {
        foreach ($stage in @('vs30', 'ps30')) {
            $spec = "${prefix}_${stage}.fxc-----${prefix}_${stage}"
            # fxc_prep.pl's BEGIN block pushes dirname($0), which is "." for a
            # Windows-style $0 under MSYS2 Perl. Add the helper directory
            # explicitly so valve_perl_helpers.pl is found from the work dir.
            & $Perl '-I' $PrepDir $Prep $spec
            if ($LASTEXITCODE -ne 0) {
                throw "fxc_prep.pl failed for $spec (exit $LASTEXITCODE)"
            }
        }

        foreach ($stage in @('vs30', 'ps30')) {
            $shader = "${prefix}_${stage}"
            $vcs = Join-Path $VcsDir "$shader.vcs"
            & $Python $VcsPack 'filelistgen.txt' `
                --shader $shader `
                --workdir '.' `
                --out $vcs `
                --fxc $Fxc `
                --include $SdkInclude
            if ($LASTEXITCODE -ne 0) {
                throw "vcspack.py failed for $shader (exit $LASTEXITCODE)"
            }
            if (-not (Test-Path -LiteralPath $vcs)) {
                throw "vcspack.py did not produce $vcs"
            }
        }

        Get-ChildItem -LiteralPath (Join-Path $dir 'fxctmp9_tmp') -Filter '*.inc' |
            Copy-Item -Destination $IncDir -Force
    }
    finally {
        Pop-Location
    }
}

Write-Host ""
Write-Host "=== shader build complete ==="
$missing = @()
foreach ($prefix in $Pairs) {
    foreach ($stage in @('vs30', 'ps30')) {
        $vcs = Join-Path $VcsDir "${prefix}_${stage}.vcs"
        $inc = Join-Path $IncDir "${prefix}_${stage}.inc"
        if (-not (Test-Path -LiteralPath $vcs) -or (Get-Item -LiteralPath $vcs).Length -eq 0) {
            $missing += $vcs
        }
        if (-not (Test-Path -LiteralPath $inc)) {
            $missing += $inc
        }
    }
}
if ($missing.Count -gt 0) {
    throw "Shader build left missing outputs:`n$($missing -join "`n")"
}

Get-ChildItem -LiteralPath $VcsDir -Filter '*.vcs' |
    Sort-Object Name |
    Select-Object Name, Length |
    Format-Table -AutoSize
Write-Host "VCS: $VcsDir"
Write-Host "INC: $IncDir"
