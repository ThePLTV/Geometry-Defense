#requires -Version 7.0
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'env.ps1')
$projectDirectory=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
& (Join-Path $PSScriptRoot 'prepare-gradle.ps1') -ProjectPath $projectDirectory -Toolchain $GeometryDefenseToolchain
$taskDirectory=Join-Path $projectDirectory 'work/report-share'
New-Item -ItemType Directory -Path $taskDirectory -Force | Out-Null
$library=[IO.Compression.ZipFile]::OpenRead((Join-Path $projectDirectory 'android/build/libs/debug/godot-lib.template_debug.aar'))
[IO.Compression.ZipFileExtensions]::ExtractToFile($library.GetEntry('classes.jar'),(Join-Path $taskDirectory 'godot.jar'),$true)
$library.Dispose()
$classesDirectory=Join-Path $taskDirectory 'classes'
New-Item -ItemType Directory -Path $classesDirectory -Force | Out-Null
$sourceDirectory=Join-Path $projectDirectory 'addons/report_share/src'
$compileClasspath=(Join-Path $GeometryDefenseToolchain.androidSdk 'platforms/android-36/android.jar')+';'+(Join-Path $taskDirectory 'godot.jar')
& (Join-Path $GeometryDefenseToolchain.javaHome 'bin/javac.exe') -encoding UTF-8 -source 17 -target 17 -classpath $compileClasspath -d $classesDirectory (Join-Path $sourceDirectory 'ReportShare.java') (Join-Path $sourceDirectory 'ReportProvider.java')
if($LASTEXITCODE -ne 0){throw 'Native report plugin compilation failed'}
$classesJar=Join-Path $taskDirectory 'classes.jar'
& (Join-Path $GeometryDefenseToolchain.javaHome 'bin/jar.exe') --create --file $classesJar -C $classesDirectory .
$aarPath=Join-Path $projectDirectory 'addons/report_share/ReportShare.aar'
$stream=[IO.File]::Open($aarPath,[IO.FileMode]::Create)
$archive=[IO.Compression.ZipArchive]::new($stream,[IO.Compression.ZipArchiveMode]::Create)
[IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive,$classesJar,'classes.jar') | Out-Null
[IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive,(Join-Path $sourceDirectory 'AndroidManifest.xml'),'AndroidManifest.xml') | Out-Null
$archive.Dispose()
