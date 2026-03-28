param(
    [string]$CasesFile,
    [switch]$RefreshAll
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$demoDir = Split-Path -Parent $scriptDir
$repoRoot = Split-Path -Parent (Split-Path -Parent $demoDir)
$resultsDir = Join-Path $demoDir "results\tiled_matmul"
$tiledTestsDir = Join-Path $demoDir "tiled_matmul\tests"
$compareScript = Join-Path $scriptDir "run_tiled_cycle_compare.ps1"

if ([string]::IsNullOrWhiteSpace($CasesFile)) {
    $CasesFile = Join-Path $tiledTestsDir "cases_square.json"
    & python (Join-Path $tiledTestsDir "gen_tiled_cases.py")
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to generate tiled default cases."
    }
}

New-Item -ItemType Directory -Force $resultsDir | Out-Null

$cases = (Get-Content -Raw -Path $CasesFile | ConvertFrom-Json).cases
$rows = @()

foreach ($case in $cases) {
    $caseName = [string]$case.name
    $summaryJson = Join-Path $resultsDir ("{0}_cycle_compare_summary.json" -f $caseName)
    if ($RefreshAll -or -not (Test-Path $summaryJson)) {
        & $compareScript -CaseName $caseName -CasesFile $CasesFile
        if ($LASTEXITCODE -ne 0) {
            throw "Failed tiled compare for benchmark case '$caseName'."
        }
    }
    $rows += Get-Content -Raw -Path $summaryJson | ConvertFrom-Json
}

$benchmarkJson = Join-Path $resultsDir "tiled_benchmark_summary.json"
$benchmarkMd = Join-Path $resultsDir "tiled_benchmark_summary.md"
$casesFileDisplay = $CasesFile.Replace($repoRoot + "\", "").Replace("\", "/")

$payload = [ordered]@{
    generated_at_utc = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    cases_file = $casesFileDisplay
    rows = $rows
}
$payload | ConvertTo-Json -Depth 6 | Set-Content -Path $benchmarkJson -Encoding UTF8

$md = @()
$md += "# Tiled NxN Benchmark Summary"
$md += ""
$md += "- Cases file: $casesFileDisplay"
$md += "- Generated (UTC): $($payload.generated_at_utc)"
$md += ""
$md += "| Case | Dim | Accel Cycles | SW no-MUL Cycles | SW MUL Cycles | SW no-MUL / Accel | SW MUL / Accel | SW no-MUL / SW MUL |"
$md += "| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |"
foreach ($row in $rows) {
    $md += "| $($row.case_name) | $($row.dim) | $($row.accel_cycles) | $($row.sw_nomul_cycles) | $($row.sw_mul_cycles) | $($row.speedup_sw_nomul_over_accel)x | $($row.speedup_sw_mul_over_accel)x | $($row.speedup_sw_nomul_over_sw_mul)x |"
}
$md -join "`n" | Set-Content -Path $benchmarkMd -Encoding UTF8

Write-Host "Benchmark summary (md): $benchmarkMd"
Write-Host "Benchmark summary (json): $benchmarkJson"
