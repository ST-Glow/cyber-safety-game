[CmdletBinding()]
param(
  [string]$OutputPath = ""
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$sourceDirectory = Join-Path $repositoryRoot "cloud/aliyun-upload-api"
$distDirectory = Join-Path $repositoryRoot "dist"
$stagingDirectory = Join-Path $distDirectory "fc-package"

if (-not $OutputPath) {
  $OutputPath = Join-Path $distDirectory "cyber-safety-upload-api-fc-cn-hongkong.zip"
} elseif (-not [System.IO.Path]::IsPathRooted($OutputPath)) {
  $OutputPath = Join-Path $repositoryRoot $OutputPath
}

if (Test-Path -LiteralPath $stagingDirectory) {
  Remove-Item -LiteralPath $stagingDirectory -Recurse -Force
}
if (Test-Path -LiteralPath $OutputPath) {
  Remove-Item -LiteralPath $OutputPath -Force
}

New-Item -ItemType Directory -Path $stagingDirectory -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $sourceDirectory "server.js") -Destination $stagingDirectory
Copy-Item -LiteralPath (Join-Path $sourceDirectory "package.json") -Destination $stagingDirectory
Copy-Item -LiteralPath (Join-Path $sourceDirectory "package-lock.json") -Destination $stagingDirectory
Copy-Item -LiteralPath (Join-Path $sourceDirectory "src") -Destination $stagingDirectory -Recurse

$installedModules = Join-Path $sourceDirectory "node_modules"
$expressManifest = Join-Path $installedModules "express/package.json"
if (Test-Path -LiteralPath $expressManifest) {
  Write-Host "Reusing the production dependencies already installed in cloud/aliyun-upload-api/node_modules"
  Copy-Item -LiteralPath $installedModules -Destination $stagingDirectory -Recurse
} else {
  Write-Host "Production dependencies are not installed yet; running npm ci"
  Push-Location $stagingDirectory
  try {
    npm.cmd ci --omit=dev --ignore-scripts
    if ($LASTEXITCODE -ne 0) {
      throw "npm ci failed with exit code $LASTEXITCODE"
    }
  } finally {
    Pop-Location
  }
}

tar.exe -a -c -f $OutputPath -C $stagingDirectory .
if ($LASTEXITCODE -ne 0) {
  throw "Archive creation failed with exit code $LASTEXITCODE"
}
$archive = Get-Item -LiteralPath $OutputPath
if ($archive.Length -le 0) {
  throw "Archive creation produced an empty file"
}
Write-Host "Function Compute package created: $($archive.FullName)"
Write-Host "Package size: $([math]::Round($archive.Length / 1MB, 2)) MB"
Write-Host "Runtime: Web Function / Custom Runtime / Node.js 20"
Write-Host "Startup command: node server.js"
Write-Host "Listening port: 9000"
