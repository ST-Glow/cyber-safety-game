[CmdletBinding()]
param(
    [string]$GodotExe = "",
    [int]$Runs = 3,
    [double]$WarmupSeconds = 5.0,
    [double]$SampleSeconds = 30.0
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

if ([string]::IsNullOrWhiteSpace($GodotExe)) {
    $GodotExe = $env:GODOT4_BIN
}
if ([string]::IsNullOrWhiteSpace($GodotExe)) {
    $downloadsFolder = -join @(
        [char]0x6D4F,
        [char]0x89C8,
        [char]0x5668,
        [char]0x4E0B,
        [char]0x8F7D
    )
    $GodotExe = Join-Path "E:\" "$downloadsFolder\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64_console.exe"
}
if (-not (Test-Path -LiteralPath $GodotExe -PathType Leaf)) {
    throw "Godot console executable not found. Pass -GodotExe or set GODOT4_BIN: $GodotExe"
}
if ($Runs -lt 1 -or $WarmupSeconds -lt 0 -or $SampleSeconds -le 0) {
    throw "Runs must be at least 1, warmup cannot be negative, and sample duration must be positive."
}

$projectPath = Split-Path -Parent $PSScriptRoot
$scenarios = @("main", "spinner", "collection", "survival")
$results = [System.Collections.Generic.List[object]]::new()

foreach ($scenario in $scenarios) {
    for ($run = 1; $run -le $Runs; $run++) {
        $rawOutput = & $GodotExe `
            --headless `
            --audio-driver Dummy `
            --path $projectPath `
            --script "res://tests/performance_benchmark.gd" `
            -- `
            "--scenario=$scenario" `
            "--warmup=$WarmupSeconds" `
            "--sample=$SampleSeconds" 2>&1
        $exitCode = $LASTEXITCODE
        $output = @($rawOutput | ForEach-Object { $_.ToString() })
        $resultLine = $output | Where-Object { $_ -match "^PERF_RESULT=" } | Select-Object -Last 1
        $unexpected = @($output | Where-Object {
            $line = $_
            if ($line -match "Failed to read the root certificate store\.") {
                return $false
            }
            return $line -match "SCRIPT ERROR|Parse Error|ObjectDB instances were leaked|resources still in use|\bERROR:"
        })
        if ($exitCode -ne 0 -or [string]::IsNullOrWhiteSpace($resultLine) -or $unexpected.Count -gt 0) {
            Write-Output "### $scenario run $run"
            $output | Write-Output
            throw "Performance benchmark failed for $scenario run $run"
        }
        $result = ($resultLine -replace "^PERF_RESULT=", "") | ConvertFrom-Json
        $result | Add-Member -NotePropertyName run -NotePropertyValue $run
        $results.Add($result)
        Write-Output ("PASS {0} run {1}: median={2}ms p95={3}ms ready={4}ms" -f $scenario, $run, $result.frame_median_ms, $result.frame_p95_ms, $result.scene_ready_ms)
    }
}

Write-Output "PERF_RESULTS_JSON=$($results | ConvertTo-Json -Compress)"
