param(
    [string]$InputJson,
    [string]$CasesFile,
    [string]$CaseName = "live_eval_tiled"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$demoDir = Split-Path -Parent $scriptDir
$tiledTestsDir = Join-Path $demoDir "tiled_matmul\tests"
$converter = Join-Path $tiledTestsDir "real_to_q5_10_tiled_case.py"
$compareScript = Join-Path $scriptDir "run_tiled_cycle_compare.ps1"

if ([string]::IsNullOrWhiteSpace($InputJson)) {
    $InputJson = Join-Path $tiledTestsDir "live_real_input.json"
}
if ([string]::IsNullOrWhiteSpace($CasesFile)) {
    $CasesFile = Join-Path $tiledTestsDir "live_eval_cases.json"
}

& python $converter --clear-generated --custom-cases $CasesFile
if ($LASTEXITCODE -ne 0) {
    throw "Failed to clear generated tiled live cases in $CasesFile"
}

& python $converter --input-json $InputJson --append-custom --custom-cases $CasesFile --name $CaseName --notes "Auto-generated for live tiled evaluator flow from real-valued JSON input."
if ($LASTEXITCODE -ne 0) {
    throw "Failed to convert tiled live real input."
}

& $compareScript -CaseName $CaseName -CasesFile $CasesFile
if ($LASTEXITCODE -ne 0) {
    throw "run_tiled_cycle_compare.ps1 failed for live tiled case '$CaseName'."
}
