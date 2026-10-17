#requires -Version 7.0
[CmdletBinding()]
param(
    [string]$ToolRoot = (Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'work\toolchain'),
    [switch]$SkipVerification
)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$ToolRoot = [IO.Path]::GetFullPath($ToolRoot)
$cacheRoot = Join-Path $ToolRoot 'downloads'
$godotRoot = Join-Path $ToolRoot 'godot'
$javaRoot = Join-Path $ToolRoot 'java'
$sdkRoot = Join-Path $ToolRoot 'android-sdk'
$stateRoot = Join-Path $ToolRoot 'state'
foreach ($folder in @($cacheRoot, $godotRoot, $javaRoot, $sdkRoot, $stateRoot)) {
    New-Item -ItemType Directory -Path $folder -Force | Out-Null
}
$packages = @(
    @{
        Name='godot.zip'; Algorithm='SHA256'
        Hash='731980f9608d61333e5baf54a2ef17210acc7a538446c0cb9969f002aca1e953'
        Url='https://github.com/godotengine/godot/releases/download/4.7.2-stable/Godot_v4.7.2-stable_win64.exe.zip'
    },
    @{
        Name='export-templates.tpz'; Algorithm='SHA256'
        Hash='f298490b8d44d934be425a5a65a51bf15f422428b229a06a6e11d9ffea248011'
        Url='https://github.com/godotengine/godot/releases/download/4.7.2-stable/Godot_v4.7.2-stable_export_templates.tpz'
    },
    @{
        Name='jdk17.zip'; Algorithm='SHA256'
        Hash='e53a79c3c3d86865bd7e787903884331068e71321714ffd44f145785affc7cb0'
        Url='https://github.com/adoptium/temurin17-binaries/releases/download/jdk-17.0.20.1%2B1/OpenJDK17U-jdk_x64_windows_hotspot_17.0.20.1_1.zip'
    },
    @{
        Name='android-command-line-tools.zip'; Algorithm='SHA1'
        Hash='54a582f3bf73e04253602f2d1c80bd5868aac115'
        Url='https://dl.google.com/android/repository/commandlinetools-win-13114758_latest.zip'
    }
)
Write-Output 'Downloading official packages and checking publisher checksums...'
$packages | ForEach-Object -Parallel {
    $package = $_
    $target = Join-Path $using:cacheRoot $package.Name
    if ((Test-Path -LiteralPath $target) -and
        ((Get-FileHash -LiteralPath $target -Algorithm $package.Algorithm).Hash -eq $package.Hash)) {
        Write-Output ("Cached and verified: " + $package.Name)
        return
    }
    $partial = $target + '.partial'
    & curl.exe --fail --location --retry 3 --connect-timeout 30 --silent --show-error --output $partial $package.Url
    if ($LASTEXITCODE -ne 0) { throw ("Download failed: " + $package.Name) }
    if ((Get-FileHash -LiteralPath $partial -Algorithm $package.Algorithm).Hash -ne $package.Hash) {
        throw ("Publisher checksum mismatch: " + $package.Name)
    }
    Move-Item -LiteralPath $partial -Destination $target -Force
    Write-Output ("Downloaded and verified: " + $package.Name)
} -ThrottleLimit 4

Add-Type -AssemblyName System.IO.Compression.FileSystem
function Expand-CheckedZip {
    param([string]$Archive, [string]$Destination, [string]$Prefix = '')
    $zip = [IO.Compression.ZipFile]::OpenRead($Archive)
    $destinationFull = [IO.Path]::GetFullPath($Destination).TrimEnd('\') + '\'
    New-Item -ItemType Directory -Path $destinationFull -Force | Out-Null
    try {
        foreach ($entry in $zip.Entries) {
            if ($Prefix -and -not $entry.FullName.StartsWith($Prefix, [StringComparison]::Ordinal)) { continue }
            $relative = $entry.FullName.Substring($Prefix.Length)
            if (-not $relative -or $entry.FullName.EndsWith('/')) { continue }
            $target = [IO.Path]::GetFullPath((Join-Path $destinationFull $relative))
            if (-not $target.StartsWith($destinationFull, [StringComparison]::OrdinalIgnoreCase)) {
                throw "Unsafe archive path: $($entry.FullName)"
            }
            New-Item -ItemType Directory -Path ([IO.Path]::GetDirectoryName($target)) -Force | Out-Null
            [IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $target, $true)
        }
    } finally { $zip.Dispose() }
}

$godotExe = Join-Path $godotRoot 'Godot_v4.7.2-stable_win64_console.exe'
if (-not (Test-Path -LiteralPath $godotExe)) {
    Write-Output 'Extracting Godot...'
    Expand-CheckedZip (Join-Path $cacheRoot 'godot.zip') $godotRoot
}
# Godot self-contained mode keeps editor settings and templates inside ToolRoot.
New-Item -ItemType File -Path (Join-Path $godotRoot '_sc_') -Force | Out-Null
$templateRoot = Join-Path $godotRoot 'editor_data\export_templates\4.7.2.stable'
if (-not (Test-Path -LiteralPath (Join-Path $templateRoot 'android_debug.apk'))) {
    Write-Output 'Extracting matching export templates...'
    Expand-CheckedZip (Join-Path $cacheRoot 'export-templates.tpz') $templateRoot 'templates/'
}
$javaExe = Get-ChildItem -LiteralPath $javaRoot -Filter java.exe -Recurse -File | Select-Object -First 1
if (-not $javaExe) {
    Write-Output 'Extracting Java 17...'
    Expand-CheckedZip (Join-Path $cacheRoot 'jdk17.zip') $javaRoot
    $javaExe = Get-ChildItem -LiteralPath $javaRoot -Filter java.exe -Recurse -File | Select-Object -First 1
}
if (-not $javaExe) { throw 'Java installation is incomplete.' }
$javaHome = Split-Path (Split-Path $javaExe.FullName -Parent) -Parent
$sdkManager = Join-Path $sdkRoot 'cmdline-tools\19.0\bin\sdkmanager.bat'
if (-not (Test-Path -LiteralPath $sdkManager)) {
    Write-Output 'Extracting Android SDK command-line tools...'
    Expand-CheckedZip (Join-Path $cacheRoot 'android-command-line-tools.zip') (Join-Path $sdkRoot 'cmdline-tools\19.0') 'cmdline-tools/'
}
$env:JAVA_HOME = $javaHome
$env:ANDROID_HOME = $sdkRoot
$env:ANDROID_SDK_ROOT = $sdkRoot
$env:ANDROID_USER_HOME = Join-Path $stateRoot 'android'
$env:GRADLE_USER_HOME = Join-Path $stateRoot 'gradle'
$env:PATH = (Join-Path $javaHome 'bin') + ';' + $env:PATH
New-Item -ItemType Directory -Path $env:ANDROID_USER_HOME -Force | Out-Null
Write-Output 'Installing Android build packages (licenses accepted for this installation)...'
$licenseAnswers = 1..100 | ForEach-Object { 'y' }
$licenseAnswers | & $sdkManager "--sdk_root=$sdkRoot" --licenses
if ($LASTEXITCODE -ne 0) { throw 'Android SDK license setup failed.' }
$sdkPackages = @('platform-tools', 'build-tools;36.0.0', 'platforms;android-36', 'cmake;3.10.2.4988404', 'ndk;28.1.13356709')
& $sdkManager "--sdk_root=$sdkRoot" --install @sdkPackages
if ($LASTEXITCODE -ne 0) { throw 'Android SDK package installation failed.' }

$debugKeystore = Join-Path $stateRoot 'android\debug.keystore'
if (-not (Test-Path -LiteralPath $debugKeystore)) {
    & (Join-Path $javaHome 'bin\keytool.exe') -genkeypair -keystore $debugKeystore -storepass android -keypass android -alias androiddebugkey -dname 'CN=Android Debug,O=Android,C=US' -keyalg RSA -keysize 2048 -validity 10000 -storetype JKS
    if ($LASTEXITCODE -ne 0) { throw 'Debug keystore creation failed.' }
}
$manifest = [ordered]@{
    schema=1
    godotVersion='4.7.2.stable'
    godot=$godotExe
    javaHome=$javaHome
    androidSdk=$sdkRoot
    androidApi=36
    buildToolsVersion='36.0.0'
    sdkManager=$sdkManager
    debugKeystore=$debugKeystore
    templates=$templateRoot
    stateRoot=$stateRoot
    packages=$sdkPackages
}
$manifest | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $PSScriptRoot 'toolchain.json') -Encoding utf8
Write-Output 'Installation complete.'
if (-not $SkipVerification) {
    & (Join-Path $PSScriptRoot 'verify.ps1')
}
