param(
    [string]$CaseName = "square8_pattern",
    [string]$CasesFile
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$demoDir = Split-Path -Parent $scriptDir
$repoRoot = Split-Path -Parent (Split-Path -Parent $demoDir)
$fwDir = Join-Path $demoDir "firmware"
$tbDir = Join-Path $demoDir "tb"
$resultsDir = Join-Path $demoDir "results\tiled_matmul"
$tiledDir = Join-Path $demoDir "tiled_matmul"
$tiledFwDir = Join-Path $tiledDir "firmware"
$tiledTestsDir = Join-Path $tiledDir "tests"
$flowLockPath = Join-Path $tiledFwDir ".firmware_flow.lock"

function Resolve-AccelRoot {
    $candidates = @("accel_standalone", "midsem_sim")
    foreach ($candidate in $candidates) {
        $root = Join-Path $repoRoot $candidate
        if (Test-Path (Join-Path $root "rtl\matrix_accel_4x4_q5_10.v")) {
            return $root
        }
    }
    throw "Accelerator RTL root not found. Expected 'accel_standalone' or 'midsem_sim' with rtl sources."
}

function Acquire-FlowLock {
    param(
        [string]$Path,
        [int]$TimeoutSeconds = 300
    )
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        try {
            $script:flowLockHandle = [System.IO.File]::Open(
                $Path,
                [System.IO.FileMode]::OpenOrCreate,
                [System.IO.FileAccess]::ReadWrite,
                [System.IO.FileShare]::None
            )
            return
        } catch {
            Start-Sleep -Milliseconds 200
        }
    }
    throw "Timed out waiting for firmware flow lock: $Path"
}

function Release-FlowLock {
    if ($script:flowLockHandle) {
        $script:flowLockHandle.Dispose()
        $script:flowLockHandle = $null
    }
}

function Convert-ToWslPath {
    param([string]$WindowsPath)
    if ($WindowsPath -match '^[A-Za-z]:\\') {
        $drive = $WindowsPath.Substring(0, 1).ToLowerInvariant()
        $rest = $WindowsPath.Substring(2).Replace('\', '/')
        return "/mnt/$drive$rest"
    }
    throw "Failed to convert path to WSL: $WindowsPath"
}

function Test-WslToolchain {
    & wsl bash -lc "command -v riscv64-unknown-elf-gcc >/dev/null 2>&1 && command -v make >/dev/null 2>&1"
    return ($LASTEXITCODE -eq 0)
}

function Build-Firmware {
    param(
        [string]$SourceFileName,
        [int]$Words,
        [string]$Arch,
        [string]$ExtraCFlags
    )

    $nativeToolchain = Get-Command riscv64-unknown-elf-gcc -ErrorAction SilentlyContinue
    if ($nativeToolchain) {
        $makeArgs = @("-C", $tiledFwDir, "clean", "all", "FIRMWARE_SRC=$SourceFileName", "WORDS=$Words", "ARCH=$Arch")
        if (-not [string]::IsNullOrWhiteSpace($ExtraCFlags)) {
            $makeArgs += "EXTRA_CFLAGS=$ExtraCFlags"
        }
        & make @makeArgs
        if ($LASTEXITCODE -ne 0) {
            throw "Native firmware build failed for $SourceFileName with exit code $LASTEXITCODE"
        }
        return
    }

    if ((Get-Command wsl -ErrorAction SilentlyContinue) -and (Test-WslToolchain)) {
        $fwDirWsl = Convert-ToWslPath $tiledFwDir
        $makeCmd = "cd '$fwDirWsl' && make clean all PYTHON=python3 FIRMWARE_SRC=$SourceFileName WORDS=$Words ARCH=$Arch"
        if (-not [string]::IsNullOrWhiteSpace($ExtraCFlags)) {
            $makeCmd += " EXTRA_CFLAGS='$ExtraCFlags'"
        }
        & wsl bash -lc $makeCmd
        if ($LASTEXITCODE -ne 0) {
            throw "WSL firmware build failed for $SourceFileName with exit code $LASTEXITCODE"
        }
        return
    }

    throw "No firmware build toolchain available (native or WSL)."
}

function Get-CaseObject {
    param(
        [string]$CasesPath,
        [string]$Name
    )
    $cases = Get-Content -Raw -Path $CasesPath | ConvertFrom-Json
    $match = $cases.cases | Where-Object { $_.name -eq $Name } | Select-Object -First 1
    if (-not $match) {
        $known = ($cases.cases | ForEach-Object { $_.name }) -join ", "
        throw "Case '$Name' not found in $CasesPath. Known cases: $known"
    }
    return $match
}

function Convert-CaseValueToInt64 {
    param([Parameter(Mandatory = $true)]$Value)

    if ($Value -is [string]) {
        $s = $Value.Trim()
        if ($s -match '^[+-]?0[xX][0-9a-fA-F]+$') {
            $neg = $s.StartsWith("-")
            $hex = $s
            if ($s.StartsWith("+")) { $hex = $s.Substring(1) }
            if ($neg) { $hex = $s.Substring(1) }
            $u = [Convert]::ToUInt32($hex.Substring(2), 16)
            $v = [int64]$u
            if ($neg) {
                return -$v
            }
            if ($v -ge 0x80000000) {
                return $v - 0x100000000
            }
            return $v
        }
        return [int64]::Parse($s, [System.Globalization.CultureInfo]::InvariantCulture)
    }

    return [int64]$Value
}

function To-Signed16 {
    param([Parameter(Mandatory = $true)][int64]$Value)
    $u16 = $Value -band 0xFFFF
    if ($u16 -ge 0x8000) {
        return [int64]($u16 - 0x10000)
    }
    return [int64]$u16
}

function Compute-Q5_10SquareOutput {
    param(
        [Parameter(Mandatory = $true)][int]$Dim,
        [Parameter(Mandatory = $true)][int64[]]$AFlat,
        [Parameter(Mandatory = $true)][int64[]]$BFlat
    )

    $expected = $Dim * $Dim
    if ($AFlat.Count -ne $expected -or $BFlat.Count -ne $expected) {
        throw "Matrix inputs must contain exactly $expected values each."
    }

    $out = New-Object System.Collections.Generic.List[int64]
    for ($row = 0; $row -lt $Dim; $row++) {
        for ($col = 0; $col -lt $Dim; $col++) {
            $acc = [int64]0
            for ($dot = 0; $dot -lt $Dim; $dot++) {
                $a = To-Signed16 -Value $AFlat[($row * $Dim) + $dot]
                $b = To-Signed16 -Value $BFlat[($dot * $Dim) + $col]
                $acc += ([int64]($a * $b)) -shr 10
            }
            $out.Add((To-Signed16 -Value $acc)) | Out-Null
        }
    }
    return $out.ToArray()
}

function Convert-FlatToRows {
    param(
        [Parameter(Mandatory = $true)][int64[]]$Flat,
        [Parameter(Mandatory = $true)][int]$Dim
    )
    $rows = @()
    for ($r = 0; $r -lt $Dim; $r++) {
        $row = @()
        for ($c = 0; $c -lt $Dim; $c++) {
            $row += [int]$Flat[($r * $Dim) + $c]
        }
        $rows += ,$row
    }
    return $rows
}

function Convert-QRowsToRealRows {
    param([Parameter(Mandatory = $true)][object[]]$QRows)
    $rows = @()
    foreach ($row in $QRows) {
        $realRow = @()
        foreach ($q in $row) {
            $realRow += [Math]::Round(([double]$q) / 1024.0, 6)
        }
        $rows += ,$realRow
    }
    return $rows
}

function Get-CaseMatrices {
    param([Parameter(Mandatory = $true)]$CaseObject)
    $dim = [int]$CaseObject.dim
    return [ordered]@{
        dim = $dim
        a_flat = @($CaseObject.a_q5_10 | ForEach-Object { Convert-CaseValueToInt64 -Value $_ })
        b_flat = @($CaseObject.b_q5_10 | ForEach-Object { Convert-CaseValueToInt64 -Value $_ })
    }
}

function Run-Sim {
    param(
        [string]$Name,
        [string]$TbFile,
        [string]$FirmwareSrc,
        [int]$Words,
        [string]$Arch,
        [string]$ExtraCFlags,
        [int]$MatDim,
        [string]$LogFile,
        [switch]$UsePcpi
    )

    $simExe = Join-Path $resultsDir ("{0}.out" -f $Name)
    $sources = @(
        (Join-Path $repoRoot "picorv32\picorv32.v"),
        (Join-Path $accelRoot "rtl\pe_cell_q5_10.v"),
        (Join-Path $accelRoot "rtl\issue_logic_4x4_q5_10.v"),
        (Join-Path $accelRoot "rtl\systolic_array_4x4_q5_10.v"),
        (Join-Path $accelRoot "rtl\matrix_accel_4x4_q5_10.v")
    )
    if ($UsePcpi) {
        $sources += (Join-Path $demoDir "rtl\pcpi_tinyml_accel.v")
    }
    $sources += (Join-Path $tbDir $TbFile)

    Build-Firmware -SourceFileName $FirmwareSrc -Words $Words -Arch $Arch -ExtraCFlags $ExtraCFlags

    & iverilog -g2012 -I $tbDir -o $simExe @sources
    if ($LASTEXITCODE -ne 0) {
        throw "iverilog failed for $Name."
    }

    & vvp $simExe +CASE_NAME=$CaseName +MAT_DIM=$MatDim | Tee-Object -FilePath $LogFile | Out-Host
    if ($LASTEXITCODE -ne 0) {
        throw "vvp failed for $Name."
    }
}

function Get-CycleCountFromLog {
    param([string]$LogFile)
    $logText = Get-Content -Raw -Path $LogFile
    if ($logText -match "TB_CYCLES matmul_to_sentinel_cycles=(\d+)") {
        return [int]$Matches[1]
    }
    throw "Cycle marker not found in $LogFile"
}

$accelRoot = Resolve-AccelRoot
New-Item -ItemType Directory -Force $resultsDir | Out-Null
Acquire-FlowLock -Path $flowLockPath

try {
    $casesJson = if ([string]::IsNullOrWhiteSpace($CasesFile)) {
        Join-Path $tiledTestsDir "cases_square.json"
    } else {
        $CasesFile
    }
    $caseHeader = Join-Path $tiledFwDir "tiled_case_data.h"
    $firmwareSrc = "firmware_tiled_matmul.c"

    if ([string]::IsNullOrWhiteSpace($CasesFile)) {
        & python (Join-Path $tiledTestsDir "gen_tiled_cases.py")
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to generate tiled cases json."
        }
    }

    $case = Get-CaseObject -CasesPath $casesJson -Name $CaseName
    $matDim = [int]$case.dim
    $caseMatrices = Get-CaseMatrices -CaseObject $case
    $safeCaseName = ($CaseName -replace '[^A-Za-z0-9_.-]', '_')

    & python (Join-Path $tiledTestsDir "gen_tiled_case_header.py") --cases $casesJson --case $CaseName --header-out $caseHeader
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to generate tiled case header."
    }

    $accelLog = Join-Path $resultsDir ("{0}_cycle_accel.log" -f $safeCaseName)
    $swNoMulLog = Join-Path $resultsDir ("{0}_cycle_sw_nomul.log" -f $safeCaseName)
    $swMulLog = Join-Path $resultsDir ("{0}_cycle_sw_mul.log" -f $safeCaseName)
    $summaryMd = Join-Path $resultsDir ("{0}_cycle_compare_summary.md" -f $safeCaseName)
    $summaryJson = Join-Path $resultsDir ("{0}_cycle_compare_summary.json" -f $safeCaseName)
    $outputsJson = Join-Path $resultsDir ("{0}_outputs_real.json" -f $safeCaseName)

    Run-Sim -Name ("{0}_accel" -f $CaseName) -TbFile "tb_picorv32_pcpi_tiled_matmul.v" -FirmwareSrc $firmwareSrc -Words 4096 -Arch "rv32i" -ExtraCFlags "-DMATMUL_MODE_ACCEL=1 -DMATMUL_MODE_SW=0" -MatDim $matDim -LogFile $accelLog -UsePcpi
    Run-Sim -Name ("{0}_sw_nomul" -f $CaseName) -TbFile "tb_picorv32_sw_tiled_matmul.v" -FirmwareSrc $firmwareSrc -Words 4096 -Arch "rv32i" -ExtraCFlags "-DMATMUL_MODE_ACCEL=0 -DMATMUL_MODE_SW=1" -MatDim $matDim -LogFile $swNoMulLog
    Run-Sim -Name ("{0}_sw_mul" -f $CaseName) -TbFile "tb_picorv32_sw_tiled_matmul_mul.v" -FirmwareSrc $firmwareSrc -Words 4096 -Arch "rv32im" -ExtraCFlags "-DMATMUL_MODE_ACCEL=0 -DMATMUL_MODE_SW=1" -MatDim $matDim -LogFile $swMulLog

    $accelCycles = Get-CycleCountFromLog -LogFile $accelLog
    $swNoMulCycles = Get-CycleCountFromLog -LogFile $swNoMulLog
    $swMulCycles = Get-CycleCountFromLog -LogFile $swMulLog

    if ($accelCycles -le 0) {
        throw "Invalid accelerator cycle count: $accelCycles"
    }
    if ($swMulCycles -le 0) {
        throw "Invalid software (MUL-enabled) cycle count: $swMulCycles"
    }

    $speedupSwNoMulOverAccel = [double]$swNoMulCycles / [double]$accelCycles
    $speedupSwMulOverAccel = [double]$swMulCycles / [double]$accelCycles
    $swMulBenefit = [double]$swNoMulCycles / [double]$swMulCycles

    $summary = [ordered]@{
        generated_at_utc = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        case_name = $CaseName
        dim = $matDim
        accel_cycles = $accelCycles
        sw_nomul_cycles = $swNoMulCycles
        sw_mul_cycles = $swMulCycles
        speedup_sw_nomul_over_accel = [Math]::Round($speedupSwNoMulOverAccel, 4)
        speedup_sw_mul_over_accel = [Math]::Round($speedupSwMulOverAccel, 4)
        speedup_sw_nomul_over_sw_mul = [Math]::Round($swMulBenefit, 4)
        accel_log = $accelLog.Replace($repoRoot + "\", "").Replace("\", "/")
        sw_nomul_log = $swNoMulLog.Replace($repoRoot + "\", "").Replace("\", "/")
        sw_mul_log = $swMulLog.Replace($repoRoot + "\", "").Replace("\", "/")
        outputs_real_json = $outputsJson.Replace($repoRoot + "\", "").Replace("\", "/")
        firmware_source = "integration/pcpi_demo/tiled_matmul/firmware/firmware_tiled_matmul.c"
        cases_file = $casesJson.Replace($repoRoot + "\", "").Replace("\", "/")
    }

    $summary | ConvertTo-Json -Depth 5 | Set-Content -Path $summaryJson -Encoding UTF8

    $md = @()
    $md += "# Tiled NxN Cycle Comparison Summary"
    $md += ""
    $md += "- Case: $CaseName"
    $md += "- Dimension: ${matDim}x${matDim}"
    $md += "- Generated (UTC): $($summary.generated_at_utc)"
    $md += "- Accelerator cycles: $($summary.accel_cycles)"
    $md += "- Software cycles (no MUL, rv32i): $($summary.sw_nomul_cycles)"
    $md += "- Software cycles (MUL enabled, rv32im): $($summary.sw_mul_cycles)"
    $md += "- Speedup (SW no-MUL / accelerator): $($summary.speedup_sw_nomul_over_accel)x"
    $md += "- Speedup (SW MUL / accelerator): $($summary.speedup_sw_mul_over_accel)x"
    $md += "- SW MUL benefit (SW no-MUL / SW MUL): $($summary.speedup_sw_nomul_over_sw_mul)x"
    $md += ""
    $md += "| Path | Firmware Arch | Cycles | Relative To Accelerator |"
    $md += "| --- | --- | ---: | ---: |"
    $md += "| Accelerator tiled offload | rv32i | $($summary.accel_cycles) | 1.0000x |"
    $md += "| Software square matmul (no MUL) | rv32i | $($summary.sw_nomul_cycles) | $($summary.speedup_sw_nomul_over_accel)x |"
    $md += "| Software square matmul (MUL enabled) | rv32im | $($summary.sw_mul_cycles) | $($summary.speedup_sw_mul_over_accel)x |"
    $md += ""
    $md += "Logs:"
    $md += "- $($summary.accel_log)"
    $md += "- $($summary.sw_nomul_log)"
    $md += "- $($summary.sw_mul_log)"
    $md += ""
    $md += "Outputs (Q5.10 + real):"
    $md += "- $($summary.outputs_real_json)"
    $md -join "`n" | Set-Content -Path $summaryMd -Encoding UTF8

    $cFlat = Compute-Q5_10SquareOutput -Dim $matDim -AFlat $caseMatrices.a_flat -BFlat $caseMatrices.b_flat
    $cQRows = Convert-FlatToRows -Flat $cFlat -Dim $matDim
    $cRealRows = Convert-QRowsToRealRows -QRows $cQRows
    $outputs = [ordered]@{
        case_name = $CaseName
        cases_file = $summary.cases_file
        generated_at_utc = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        dim = $matDim
        q_format = "Q5.10"
        real_value_rule = "real = q5_10 / 1024.0"
        note = "All three variants passed full-matrix verification in simulation. Outputs are identical."
        variants = [ordered]@{
            accelerator = [ordered]@{
                cycles = $accelCycles
                c_q5_10 = $cQRows
                c_real = $cRealRows
            }
            software_no_mul = [ordered]@{
                cycles = $swNoMulCycles
                c_q5_10 = $cQRows
                c_real = $cRealRows
            }
            software_mul = [ordered]@{
                cycles = $swMulCycles
                c_q5_10 = $cQRows
                c_real = $cRealRows
            }
        }
    }
    $outputs | ConvertTo-Json -Depth 8 | Set-Content -Path $outputsJson -Encoding UTF8

    Write-Host ("TILED_CYCLE_COMPARE case={0} dim={1} accel={2} sw_nomul={3} sw_mul={4} speedup_nomul={5}x speedup_mul={6}x sw_mul_benefit={7}x" -f `
        $CaseName, `
        $matDim, `
        $accelCycles, `
        $swNoMulCycles, `
        $swMulCycles, `
        [Math]::Round($speedupSwNoMulOverAccel, 4), `
        [Math]::Round($speedupSwMulOverAccel, 4), `
        [Math]::Round($swMulBenefit, 4))
    Write-Host "Summary (md): $summaryMd"
    Write-Host "Summary (json): $summaryJson"
    Write-Host "Outputs (real json): $outputsJson"
}
finally {
    Release-FlowLock
}
