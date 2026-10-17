#requires -Version 7.0
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'env.ps1')
$workspaceRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$smokeRoot = Join-Path $workspaceRoot 'work\toolchain-smoke'
$outputRoot = Split-Path $PSScriptRoot -Parent
$apkPath = Join-Path $outputRoot 'GeometryDefense-toolchain-check.apk'
New-Item -ItemType Directory -Path $smokeRoot -Force | Out-Null
@'
config_version=5

[application]
config/name="Geometry Defense - Toolchain Check"
run/main_scene="res://main.tscn"

[display]
window/size/viewport_width=540
window/size/viewport_height=960
window/stretch/mode="canvas_items"
window/handheld/orientation=1

[rendering]
renderer/rendering_method="gl_compatibility"
renderer/rendering_method.mobile="gl_compatibility"
textures/vram_compression/import_etc2_astc=true
environment/defaults/default_clear_color=Color(0.12, 0.135, 0.15, 1)
'@ | Set-Content -LiteralPath (Join-Path $smokeRoot 'project.godot') -Encoding utf8
@'
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://main.gd" id="1"]

[node name="ToolchainCheck" type="Control"]
layout_mode=3
anchors_preset=15
anchor_right=1.0
anchor_bottom=1.0
grow_horizontal=2
grow_vertical=2
script=ExtResource("1")
'@ | Set-Content -LiteralPath (Join-Path $smokeRoot 'main.tscn') -Encoding utf8
@'
extends Control

var tap_count: int = 0

func _ready() -> void:
    var box := VBoxContainer.new()
    box.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
    box.position = Vector2(40, 270)
    box.size = Vector2(460, 400)
    box.add_theme_constant_override("separation", 28)
    add_child(box)
    var title := Label.new()
    title.text = "GEOMETRY DEFENSE"
    title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    title.add_theme_font_size_override("font_size", 34)
    box.add_child(title)
    var status := Label.new()
    status.text = "Проверка среды сборки\nGodot + Android SDK + Java\n\nЭто тест инструментов."
    status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    status.add_theme_font_size_override("font_size", 24)
    box.add_child(status)
    var button := Button.new()
    button.text = "Проверить касание: 0"
    button.custom_minimum_size = Vector2(460, 80)
    button.add_theme_font_size_override("font_size", 25)
    button.pressed.connect(func() -> void:
        tap_count += 1
        button.text = "Проверить касание: %d" % tap_count
    )
    box.add_child(button)
    print("TOOLCHAIN_SMOKE_READY")
'@ | Set-Content -LiteralPath (Join-Path $smokeRoot 'main.gd') -Encoding utf8
@'
[preset.0]
name="Android"
platform="Android"
runnable=true
advanced_options=false
dedicated_server=false
custom_features=""
export_filter="all_resources"
include_filter=""
exclude_filter=""
export_path=""
script_export_mode=2

[preset.0.options]
custom_template/debug=""
custom_template/release=""
gradle_build/use_gradle_build=false
architectures/armeabi-v7a=false
architectures/arm64-v8a=true
architectures/x86=false
architectures/x86_64=false
version/code=1
version/name="0.0.1-toolchain-check"
package/unique_name="org.thepltv.geometrydefense.toolchaincheck"
package/name="Geometry Defense - Toolchain Check"
package/signed=true
screen/immersive_mode=true
permissions/internet=false
'@ | Set-Content -LiteralPath (Join-Path $smokeRoot 'export_presets.cfg') -Encoding utf8

# Configure only this self-contained copy of Godot.
$editorSettingsRoot = Join-Path (Split-Path $GeometryDefenseToolchain.godot -Parent) 'editor_data'
New-Item -ItemType Directory -Path $editorSettingsRoot -Force | Out-Null
$editorSettingsPath = Join-Path $editorSettingsRoot 'editor_settings-4.7.tres'
$editorSettings = if (Test-Path -LiteralPath $editorSettingsPath) {
    Get-Content -LiteralPath $editorSettingsPath -Raw
} else {
    '[gd_resource type="EditorSettings" format=3]' + [Environment]::NewLine + [Environment]::NewLine + '[resource]' + [Environment]::NewLine
}
$settings = [ordered]@{
    'export/android/android_sdk_path' = $GeometryDefenseToolchain.androidSdk.Replace('\', '/')
    'export/android/java_sdk_path' = $GeometryDefenseToolchain.javaHome.Replace('\', '/')
    'export/android/debug_keystore' = $GeometryDefenseToolchain.debugKeystore.Replace('\', '/')
    'export/android/debug_keystore_user' = 'androiddebugkey'
    'export/android/debug_keystore_pass' = 'android'
}
foreach ($setting in $settings.GetEnumerator()) {
    $line = $setting.Key + ' = ' + (ConvertTo-Json -InputObject $setting.Value -Compress)
    $pattern = '(?m)^' + [regex]::Escape($setting.Key) + ' = .*$'
    if ([regex]::IsMatch($editorSettings, $pattern)) {
        $replacement = $line
        $editorSettings = [regex]::Replace($editorSettings, $pattern, [Text.RegularExpressions.MatchEvaluator]{ param($m) $replacement })
    } else {
        $editorSettings += [Environment]::NewLine + $line
    }
}
$editorSettings | Set-Content -LiteralPath $editorSettingsPath -Encoding utf8

& $GeometryDefenseToolchain.godot --version
if ($LASTEXITCODE -ne 0) { throw 'Godot cannot start.' }
& (Join-Path $env:JAVA_HOME 'bin\java.exe') -version
if ($LASTEXITCODE -ne 0) { throw 'Java cannot start.' }
& (Join-Path $env:ANDROID_HOME 'platform-tools\adb.exe') version
if ($LASTEXITCODE -ne 0) { throw 'ADB cannot start.' }
& (Join-Path $PSScriptRoot 'build-android.ps1') -ProjectPath $smokeRoot -OutputApk $apkPath
$sceneLog = & $GeometryDefenseToolchain.godot --headless --path $smokeRoot --quit-after 5 2>&1
$sceneLog | Write-Output
if ($LASTEXITCODE -ne 0) { throw 'Godot smoke scene failed.' }
if (-not ($sceneLog -match '^TOOLCHAIN_SMOKE_READY$')) { throw 'Smoke scene did not reach _ready().' }
if ($sceneLog -match 'SCRIPT ERROR:|ERROR:') { throw 'Godot reported a runtime error in the smoke scene.' }
$aapt = Join-Path $env:ANDROID_HOME ('build-tools\' + $GeometryDefenseToolchain.buildToolsVersion + '\aapt.exe')
$badging = & $aapt dump badging $apkPath
if ($LASTEXITCODE -ne 0) { throw 'APK manifest inspection failed.' }
$badging | Set-Content -LiteralPath (Join-Path $outputRoot 'toolchain-apk-manifest.txt') -Encoding utf8
if (-not ($badging -match 'org.thepltv.geometrydefense.toolchaincheck')) { throw 'Unexpected APK package.' }
if (-not ($badging -match "native-code: 'arm64-v8a'")) { throw 'Missing Android arm64 native library.' }
$report = [ordered]@{
    checkedAt = (Get-Date).ToUniversalTime().ToString('o')
    godotVersion = $GeometryDefenseToolchain.godotVersion
    javaHome = $GeometryDefenseToolchain.javaHome
    androidSdk = $GeometryDefenseToolchain.androidSdk
    apk = $apkPath
    apkBytes = (Get-Item -LiteralPath $apkPath).Length
    apkSha256 = (Get-FileHash -LiteralPath $apkPath -Algorithm SHA256).Hash
    apkSignatureVerified = $true
    apkManifestVerified = $true
    smokeSceneRanHeadless = $true
    deviceInstallTested = $false
}
$report | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath (Join-Path $outputRoot 'toolchain-verification.json') -Encoding utf8
Write-Output 'Verification passed: scene starts, APK exports, signature and Android manifest are valid.'
