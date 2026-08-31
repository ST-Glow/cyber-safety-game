[CmdletBinding()]
param(
    [string]$GodotExe = "",
    [switch]$VerboseOutput
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

$projectPath = Split-Path -Parent $PSScriptRoot
$tests = @(
    "mvp_smoke_test.gd",
    "spinner_race_smoke_test.gd",
    "data_chip_hunt_smoke_test.gd",
    "signal_bomb_survival_smoke_test.gd",
    "obstacle_contact_smoke_test.gd",
    "menu_flow_smoke_test.gd",
    "level_flow_smoke_test.gd",
    "pause_coordinator_smoke_test.gd",
    "experiment_session_smoke_test.gd",
    "ai_assistant_smoke_test.gd",
    "scaffold_controller_smoke_test.gd",
    "digcomp_hub_smoke_test.gd",
    "jigsaw_puzzle_smoke_test.gd",
    "data_repair_conveyor_smoke_test.gd",
    "safety_checkpoint_smoke_test.gd",
    "scene_navigation_smoke_test.gd"
)

$failedTests = [System.Collections.Generic.List[string]]::new()
foreach ($test in $tests) {
    $rawOutput = & $GodotExe `
        --headless `
        --audio-driver Dummy `
        --path $projectPath `
        --script "res://tests/$test" 2>&1
    $exitCode = $LASTEXITCODE
    $output = @($rawOutput | ForEach-Object { $_.ToString() })

    $unexpected = @($output | Where-Object {
        $line = $_
        if ($line -match "Failed to read the root certificate store\.") {
            return $false
        }
        return $line -match "SCRIPT ERROR|Parse Error|\[FAIL\]|_FAILED|ObjectDB instances were leaked|resources still in use|\bERROR:"
    })
    $hasSuccessSentinel = @($output | Where-Object { $_ -match "_SMOKE_TEST_OK" }).Count -gt 0

    if ($VerboseOutput -or $exitCode -ne 0 -or -not $hasSuccessSentinel -or $unexpected.Count -gt 0) {
        Write-Output "### $test"
        $output | Write-Output
    }

    if ($exitCode -eq 0 -and $hasSuccessSentinel -and $unexpected.Count -eq 0) {
        Write-Output "PASS $test"
    } else {
        $failedTests.Add($test)
    }
}

if ($failedTests.Count -gt 0) {
    throw "Godot smoke test failures: $($failedTests -join ', ')"
}

Write-Output "ALL_GODOT_SMOKE_TESTS_OK ($($tests.Count) tests)"
