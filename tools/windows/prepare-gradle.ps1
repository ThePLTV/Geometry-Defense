#requires -Version 7.0
[CmdletBinding()]
param([Parameter(Mandatory)][string]$ProjectPath,[Parameter(Mandatory)][object]$Toolchain)
$ErrorActionPreference='Stop'
$GeometryDefenseToolchain=$Toolchain
$ProjectPath=[IO.Path]::GetFullPath($ProjectPath)
$buildPath=Join-Path $ProjectPath 'android/build'
if(-not (Test-Path -LiteralPath (Join-Path $buildPath 'build.gradle'))) {
    New-Item -ItemType Directory -Path $buildPath -Force | Out-Null
    Expand-Archive -LiteralPath (Join-Path $GeometryDefenseToolchain.templates 'android_source.zip') -DestinationPath $buildPath -Force
}
[IO.File]::WriteAllText((Join-Path $ProjectPath 'android/.build_version'),$GeometryDefenseToolchain.godotVersion)
[IO.File]::WriteAllText((Join-Path $ProjectPath 'android/.gdignore'),'')
$propertiesPath=Join-Path $buildPath 'gradle.properties'
$properties=Get-Content -LiteralPath $propertiesPath -Raw
if($properties -notmatch 'org.gradle.daemon=false') { Add-Content -LiteralPath $propertiesPath -Value "`norg.gradle.daemon=false" }
$configPath=Join-Path $buildPath 'config.gradle'
$config=Get-Content -LiteralPath $configPath -Raw
$config=$config.Replace("buildTools         : '36.1.0'","buildTools         : '36.0.0'").Replace("ndkVersion         : '29.0.14206865'","ndkVersion         : '28.1.13356709'")
[IO.File]::WriteAllText($configPath,$config)
