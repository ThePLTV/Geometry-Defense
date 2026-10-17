#requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ProjectPath,
    [string]$OutputApk = (Join-Path (Split-Path $PSScriptRoot -Parent) 'GeometryDefense-debug.apk'),
    [string]$Preset = 'Android'
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'env.ps1')
$ProjectPath = [IO.Path]::GetFullPath($ProjectPath)
$OutputApk = [IO.Path]::GetFullPath($OutputApk)
if (-not (Test-Path -LiteralPath (Join-Path $ProjectPath 'project.godot'))) { throw 'project.godot not found.' }
New-Item -ItemType Directory -Path (Split-Path $OutputApk -Parent) -Force | Out-Null
if((Get-Content -LiteralPath (Join-Path $ProjectPath 'export_presets.cfg') -Raw) -match 'gradle_build/use_gradle_build=true') {
    & (Join-Path $ProjectPath 'tools/windows/prepare-gradle.ps1') -ProjectPath $ProjectPath -Toolchain $GeometryDefenseToolchain
}
& $GeometryDefenseToolchain.godot --headless --path $ProjectPath --editor --import
if ($LASTEXITCODE -ne 0) { throw 'Godot import failed.' }
& $GeometryDefenseToolchain.godot --headless --path $ProjectPath --export-debug $Preset $OutputApk
if ($LASTEXITCODE -ne 0) { throw 'Android export failed.' }
if (-not (Test-Path -LiteralPath $OutputApk)) { throw 'Godot did not produce an APK.' }
$apksigner = Join-Path $env:ANDROID_HOME ('build-tools\' + $GeometryDefenseToolchain.buildToolsVersion + '\apksigner.bat')
& $apksigner verify --verbose $OutputApk
if ($LASTEXITCODE -ne 0) { throw 'APK signature verification failed.' }
Write-Output ("Verified APK: " + $OutputApk)
