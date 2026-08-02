[CmdletBinding()]
param(
    [string]$GodotExe = "",
    [string]$ApiBaseUrl = ""
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

if ([string]::IsNullOrWhiteSpace($ApiBaseUrl)) {
    $ApiBaseUrl = $env:AI_API_BASE_URL
}
if ([string]::IsNullOrWhiteSpace($ApiBaseUrl)) {
    $ApiBaseUrl = "http://127.0.0.1:8787"
}
$ApiBaseUrl = $ApiBaseUrl.Trim().TrimEnd("/")
$isLocal = $ApiBaseUrl -match '^http://(127\.0\.0\.1|localhost):\d+$'
if (-not $isLocal -and -not $ApiBaseUrl.StartsWith("https://", [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "AI API URL must use HTTPS, except for an explicit loopback development URL."
}

$projectPath = Split-Path -Parent $PSScriptRoot
$outputPath = Join-Path $projectPath "build\web\index.html"
& $GodotExe --headless --path $projectPath --export-debug Web $outputPath
if ($LASTEXITCODE -ne 0) {
    throw "Godot Web export failed with exit code $LASTEXITCODE"
}

$html = [System.IO.File]::ReadAllText($outputPath)
$encodedUrl = ConvertTo-Json $ApiBaseUrl -Compress
$configuration = "<script>window.GODOT_AI_CONFIG=Object.freeze({apiBaseUrl:$encodedUrl});</script>"
if (-not $html.Contains("</head>")) {
    throw "Exported HTML has no </head> marker for AI configuration injection."
}
$html = $html.Replace("</head>", "$configuration`n</head>")
[System.IO.File]::WriteAllText($outputPath, $html, [System.Text.UTF8Encoding]::new($false))
Write-Output "WEB_EXPORT_OK $outputPath AI_API_BASE_URL=$ApiBaseUrl"
