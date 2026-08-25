[CmdletBinding()]
param(
    [string]$GodotExe = "",
    [string]$ApiBaseUrl = "",
    [string]$PrimaryApiBaseUrl = "",
    [string]$FallbackApiBaseUrl = "",
    [string]$StudyVersion = "godot-v1",
    [string]$BuildVersion = "",
    [switch]$ProductionMode
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($GodotExe)) {
    $GodotExe = $env:GODOT4_BIN
}
if ([string]::IsNullOrWhiteSpace($GodotExe)) {
    $downloadsFolder = -join @([char]0x6D4F, [char]0x89C8, [char]0x5668, [char]0x4E0B, [char]0x8F7D)
    $GodotExe = Join-Path "E:\" "$downloadsFolder\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64_console.exe"
}
if (-not (Test-Path -LiteralPath $GodotExe -PathType Leaf)) {
    throw "Godot console executable not found. Pass -GodotExe or set GODOT4_BIN."
}

if ([string]::IsNullOrWhiteSpace($PrimaryApiBaseUrl)) { $PrimaryApiBaseUrl = $ApiBaseUrl }
if ([string]::IsNullOrWhiteSpace($PrimaryApiBaseUrl)) { $PrimaryApiBaseUrl = $env:PRIMARY_API_BASE_URL }
if ([string]::IsNullOrWhiteSpace($PrimaryApiBaseUrl)) { $PrimaryApiBaseUrl = $env:AI_API_BASE_URL }
if ([string]::IsNullOrWhiteSpace($PrimaryApiBaseUrl)) { $PrimaryApiBaseUrl = "http://127.0.0.1:8787" }
if ([string]::IsNullOrWhiteSpace($FallbackApiBaseUrl)) { $FallbackApiBaseUrl = $env:FALLBACK_API_BASE_URL }
if ([string]::IsNullOrWhiteSpace($FallbackApiBaseUrl)) { $FallbackApiBaseUrl = $PrimaryApiBaseUrl }
if ([string]::IsNullOrWhiteSpace($BuildVersion)) { $BuildVersion = $env:GITHUB_SHA }
if ([string]::IsNullOrWhiteSpace($BuildVersion)) { $BuildVersion = "local" }

function Assert-ApiUrl([string]$Value, [string]$Label) {
    $isLocal = $Value -match '^http://(127\.0\.0\.1|localhost):\d+$'
    if (-not $isLocal -and -not $Value.StartsWith("https://", [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "$Label must use HTTPS, except for an explicit loopback development URL."
    }
}

$PrimaryApiBaseUrl = $PrimaryApiBaseUrl.Trim().TrimEnd("/")
$FallbackApiBaseUrl = $FallbackApiBaseUrl.Trim().TrimEnd("/")
Assert-ApiUrl $PrimaryApiBaseUrl "Primary API URL"
Assert-ApiUrl $FallbackApiBaseUrl "Fallback API URL"
if ($ProductionMode -and $PrimaryApiBaseUrl -eq $FallbackApiBaseUrl) {
    throw "Production export requires distinct primary and fallback API URLs."
}

$projectPath = Split-Path -Parent $PSScriptRoot
$repositoryPath = Split-Path -Parent $projectPath
$outputFolder = Join-Path $projectPath "build\web"
$outputPath = Join-Path $outputFolder "index.html"
if (-not (Test-Path -LiteralPath $outputFolder -PathType Container)) {
    New-Item -ItemType Directory -Path $outputFolder -Force | Out-Null
}
& $GodotExe --headless --path $projectPath --export-debug Web $outputPath
if ($LASTEXITCODE -ne 0) {
    throw "Godot Web export failed with exit code $LASTEXITCODE"
}

$bridgeSource = Join-Path $projectPath "web\experiment-bridge.js"
$ossSdkSource = Join-Path $repositoryPath "cloud\aliyun-upload-api\node_modules\ali-oss\dist\aliyun-oss-sdk.min.js"
if (-not (Test-Path -LiteralPath $bridgeSource -PathType Leaf)) {
    throw "Experiment bridge source is missing: $bridgeSource"
}
if (-not (Test-Path -LiteralPath $ossSdkSource -PathType Leaf)) {
    throw "Local Aliyun OSS browser SDK is missing. Run npm ci in cloud/aliyun-upload-api first."
}
Copy-Item -LiteralPath $bridgeSource -Destination (Join-Path $outputFolder "experiment-bridge.js") -Force
Copy-Item -LiteralPath $ossSdkSource -Destination (Join-Path $outputFolder "aliyun-oss-sdk.min.js") -Force

$aiConfig = [ordered]@{
    apiBaseUrl = $PrimaryApiBaseUrl
    primaryApiBaseUrl = $PrimaryApiBaseUrl
    fallbackApiBaseUrl = $FallbackApiBaseUrl
} | ConvertTo-Json -Compress
$experimentConfig = [ordered]@{
    productionMode = [bool]$ProductionMode
    primaryApiBaseUrl = $PrimaryApiBaseUrl
    fallbackApiBaseUrl = $FallbackApiBaseUrl
    studyVersion = $StudyVersion
    buildVersion = $BuildVersion
    retentionMonths = 12
} | ConvertTo-Json -Compress
$configuration = @"
<script>window.GODOT_AI_CONFIG=Object.freeze($aiConfig);window.GODOT_EXPERIMENT_CONFIG=Object.freeze($experimentConfig);</script>
<script src="aliyun-oss-sdk.min.js"></script>
<script src="experiment-bridge.js"></script>
"@
$html = [System.IO.File]::ReadAllText($outputPath)
if (-not $html.Contains("</head>")) {
    throw "Exported HTML has no </head> marker for experiment configuration injection."
}
$html = $html.Replace("</head>", "$configuration`n</head>")
[System.IO.File]::WriteAllText($outputPath, $html, [System.Text.UTF8Encoding]::new($false))
Write-Output "WEB_EXPORT_OK $outputPath PRIMARY=$PrimaryApiBaseUrl FALLBACK=$FallbackApiBaseUrl PRODUCTION=$([bool]$ProductionMode)"
