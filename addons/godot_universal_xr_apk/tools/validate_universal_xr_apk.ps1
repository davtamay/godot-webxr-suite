param(
	[Parameter(Mandatory = $true)]
	[string]$Apk,
	[string]$AndroidSdk = ""
)

$ErrorActionPreference = "Stop"
$apkPath = (Resolve-Path -LiteralPath $Apk).Path

if ($AndroidSdk -eq "") {
	if ($env:ANDROID_HOME) {
		$AndroidSdk = $env:ANDROID_HOME
	} elseif ($env:ANDROID_SDK_ROOT) {
		$AndroidSdk = $env:ANDROID_SDK_ROOT
	} else {
		$AndroidSdk = Join-Path $env:LOCALAPPDATA "Android\Sdk"
	}
}

$buildTools = Join-Path $AndroidSdk "build-tools"
if (-not (Test-Path -LiteralPath $buildTools)) {
	throw "Android build-tools not found under $buildTools"
}

$aapt2 = Get-ChildItem -LiteralPath $buildTools -Directory |
	Sort-Object { [version]$_.Name } -Descending |
	ForEach-Object { Join-Path $_.FullName "aapt2.exe" } |
	Where-Object { Test-Path -LiteralPath $_ } |
	Select-Object -First 1
if (-not $aapt2) {
	throw "aapt2.exe was not found under $buildTools"
}

$apksigner = Get-ChildItem -LiteralPath $buildTools -Directory |
	Sort-Object { [version]$_.Name } -Descending |
	ForEach-Object { Join-Path $_.FullName "apksigner.bat" } |
	Where-Object { Test-Path -LiteralPath $_ } |
	Select-Object -First 1
if (-not $apksigner) {
	throw "apksigner.bat was not found under $buildTools"
}

$badging = & $aapt2 dump badging $apkPath 2>&1 | Out-String
if ($LASTEXITCODE -ne 0) {
	throw "aapt2 could not inspect $apkPath`n$badging"
}

$manifest = & $aapt2 dump xmltree --file AndroidManifest.xml $apkPath 2>&1 | Out-String
if ($LASTEXITCODE -ne 0) {
	throw "aapt2 could not dump AndroidManifest.xml`n$manifest"
}

$checks = [ordered]@{
	"OpenXR immersive category" = "org.khronos.openxr.intent.category.IMMERSIVE_HMD"
	"Android XR feature" = "android.software.xr.api.openxr"
	"Google OpenXR library" = "libopenxr.google.so"
	"Full-space launch property" = "android.window.PROPERTY_XR_ACTIVITY_START_MODE"
	"Full-space launch value" = "XR_ACTIVITY_START_MODE_FULL_SPACE_UNMANAGED"
	"Android hand permission" = "android.permission.HAND_TRACKING"
	"Meta Horizon hand permission" = "horizonos.permission.HAND_TRACKING"
	"Android XR fine scene permission" = "android.permission.SCENE_UNDERSTANDING_FINE"
	"Android XR coarse scene permission" = "android.permission.SCENE_UNDERSTANDING_COARSE"
	"Meta scene permission" = "com.oculus.permission.USE_SCENE"
	"Meta Horizon scene permission" = "horizonos.permission.USE_SCENE"
	"Meta anchor API permission" = "horizonos.permission.USE_ANCHOR_API"
	"Meta passthrough feature" = "com.oculus.feature.PASSTHROUGH"
}

$failed = $false
foreach ($entry in $checks.GetEnumerator()) {
	if ($manifest.Contains($entry.Value)) {
		Write-Output "[PASS] $($entry.Key)"
	} else {
		Write-Output "[FAIL] $($entry.Key): missing $($entry.Value)"
		$failed = $true
	}
}

if ($badging -match "sdkVersion:'(\d+)'") {
	$minSdk = [int]$Matches[1]
	if ($minSdk -ge 34) {
		Write-Output "[PASS] Minimum SDK: $minSdk"
	} else {
		Write-Output "[FAIL] Minimum SDK is $minSdk; Galaxy XR requires 34+"
		$failed = $true
	}
} else {
	Write-Output "[FAIL] Minimum SDK could not be read"
	$failed = $true
}

Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [IO.Compression.ZipFile]::OpenRead($apkPath)
try {
	$nativeEntries = @($zip.Entries | Where-Object {
		$_.FullName.StartsWith("lib/") -and $_.FullName.EndsWith(".so")
	})
	$hasArm64 = $null -ne ($nativeEntries | Where-Object {
		$_.FullName.StartsWith("lib/arm64-v8a/")
	} | Select-Object -First 1)
	$hasOpenXRLoader = $null -ne ($nativeEntries | Where-Object {
		$_.FullName -eq "lib/arm64-v8a/libopenxr_loader.so"
	} | Select-Object -First 1)
	$hasOpenXRVendors = $null -ne ($nativeEntries | Where-Object {
		$_.FullName -eq "lib/arm64-v8a/libgodotopenxrvendors.so"
	} | Select-Object -First 1)
	$hasOpenXRVendorsDescriptor = $null -ne ($zip.Entries | Where-Object {
		$_.FullName -eq "assets/addons/godotopenxrvendors/plugin.gdextension"
	} | Select-Object -First 1)
	$abis = @($nativeEntries | ForEach-Object {
		$parts = $_.FullName.Split("/")
		if ($parts.Count -ge 3) { $parts[1] }
	} | Sort-Object -Unique)
} finally {
	$zip.Dispose()
}
if ($hasArm64) {
	Write-Output "[PASS] arm64-v8a native libraries"
} else {
	Write-Output "[FAIL] No arm64-v8a native library was found"
	$failed = $true
}
if ($hasOpenXRLoader) {
	Write-Output "[PASS] Khronos OpenXR loader"
} else {
	Write-Output "[FAIL] lib/arm64-v8a/libopenxr_loader.so is missing"
	$failed = $true
}
if ($hasOpenXRVendors) {
	Write-Output "[PASS] OpenXR vendor extension library"
} else {
	Write-Output "[FAIL] lib/arm64-v8a/libgodotopenxrvendors.so is missing"
	$failed = $true
}
if ($hasOpenXRVendorsDescriptor) {
	Write-Output "[PASS] OpenXR vendor extension descriptor"
} else {
	Write-Output "[FAIL] Godot OpenXR Vendors GDExtension descriptor is missing"
	$failed = $true
}
if ($abis.Count -eq 1 -and $abis[0] -eq "arm64-v8a") {
	Write-Output "[PASS] arm64-v8a is the only packaged ABI"
} else {
	Write-Output "[FAIL] Expected only arm64-v8a; found: $($abis -join ', ')"
	$failed = $true
}

$libraryIndex = $manifest.IndexOf('"libopenxr.google.so"')
$requiredFalseIndex = $manifest.IndexOf(
	"android:required(0x0101028e)=false",
	[Math]::Max(0, $libraryIndex)
)
if ($libraryIndex -ge 0 -and $requiredFalseIndex -gt $libraryIndex -and
	$requiredFalseIndex -lt ($libraryIndex + 500)) {
	Write-Output "[PASS] Google OpenXR library is optional"
} else {
	Write-Output "[FAIL] libopenxr.google.so is not explicitly android:required=false"
	$failed = $true
}

$signature = & $apksigner verify --verbose $apkPath 2>&1 | Out-String
if ($LASTEXITCODE -eq 0 -and
	$signature.Contains("Verified using v2 scheme (APK Signature Scheme v2): true")) {
	Write-Output "[PASS] APK Signature Scheme v2"
} else {
	Write-Output "[FAIL] APK is not validly signed with APK Signature Scheme v2"
	$failed = $true
}

$hash = (Get-FileHash -LiteralPath $apkPath -Algorithm SHA256).Hash
Write-Output "SHA256 $hash"

if ($failed) {
	exit 1
}

Write-Output "Universal XR APK validation passed."
