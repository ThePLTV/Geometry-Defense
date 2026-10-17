# Dot-source this file to enable the local, pinned build tools in the current shell.
$manifestPath = Join-Path $PSScriptRoot 'toolchain.json'
if (-not (Test-Path -LiteralPath $manifestPath)) { throw 'Run setup.ps1 first.' }
$GeometryDefenseToolchain = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
$env:JAVA_HOME = $GeometryDefenseToolchain.javaHome
$env:ANDROID_HOME = $GeometryDefenseToolchain.androidSdk
$env:ANDROID_SDK_ROOT = $GeometryDefenseToolchain.androidSdk
$env:ANDROID_USER_HOME = Join-Path $GeometryDefenseToolchain.stateRoot 'android'
$env:GRADLE_USER_HOME = Join-Path $GeometryDefenseToolchain.stateRoot 'gradle'
$env:GODOT_ANDROID_KEYSTORE_DEBUG_PATH = $GeometryDefenseToolchain.debugKeystore
$env:GODOT_ANDROID_KEYSTORE_DEBUG_USER = 'androiddebugkey'
$env:GODOT_ANDROID_KEYSTORE_DEBUG_PASSWORD = 'android'
$toolPaths = @(
    (Split-Path $GeometryDefenseToolchain.godot -Parent),
    (Join-Path $env:JAVA_HOME 'bin'),
    (Join-Path $env:ANDROID_HOME 'platform-tools'),
    (Join-Path $env:ANDROID_HOME 'cmdline-tools\19.0\bin')
)
$env:PATH = ($toolPaths -join ';') + ';' + $env:PATH
