param(
    [string]$CaseName = "square8_pattern",
    [ValidateSet("accel", "sw", "swmul")]
    [string]$Mode = "accel"
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

$accelRoot = Resolve-AccelRoot
New-Item -ItemType Directory -Force $resultsDir | Out-Null
Acquire-FlowLock -Path $flowLockPath

try {
    $casesJson = Join-Path $tiledTestsDir "cases_square.json"
    $caseHeader = Join-Path $tiledFwDir "tiled_case_data.h"
    $firmwareSrc = "firmware_tiled_matmul.c"

    & python (Join-Path $tiledTestsDir "gen_tiled_cases.py")
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to generate tiled cases json."
    }

    $case = Get-CaseObject -CasesPath $casesJson -Name $CaseName
    $matDim = [int]$case.dim

    & python (Join-Path $tiledTestsDir "gen_tiled_case_header.py") --cases $casesJson --case $CaseName --header-out $caseHeader
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to generate tiled case header."
    }

    $tbFile = switch ($Mode) {
        "accel" { "tb_picorv32_pcpi_tiled_matmul.v" }
        "sw"    { "tb_picorv32_sw_tiled_matmul.v" }
        "swmul" { "tb_picorv32_sw_tiled_matmul_mul.v" }
    }

    $arch = if ($Mode -eq "swmul") { "rv32im" } else { "rv32i" }
    $extraCFlags = if ($Mode -eq "accel") {
        "-DMATMUL_MODE_ACCEL=1 -DMATMUL_MODE_SW=0"
    } else {
        "-DMATMUL_MODE_ACCEL=0 -DMATMUL_MODE_SW=1"
    }

    $logFile = Join-Path $resultsDir ("{0}_{1}.log" -f $CaseName, $Mode)
    $simExe = Join-Path $resultsDir ("{0}_{1}.out" -f $CaseName, $Mode)
    $sources = @(
        (Join-Path $repoRoot "picorv32\picorv32.v"),
        (Join-Path $accelRoot "rtl\pe_cell_q5_10.v"),
        (Join-Path $accelRoot "rtl\issue_logic_4x4_q5_10.v"),
        (Join-Path $accelRoot "rtl\systolic_array_4x4_q5_10.v"),
        (Join-Path $accelRoot "rtl\matrix_accel_4x4_q5_10.v")
    )
    if ($Mode -eq "accel") {
        $sources += (Join-Path $demoDir "rtl\pcpi_tinyml_accel.v")
    }
    $sources += (Join-Path $tbDir $tbFile)

    Build-Firmware -SourceFileName $firmwareSrc -Words 4096 -Arch $arch -ExtraCFlags $extraCFlags

    & iverilog -g2012 -I $tbDir -o $simExe @sources
    if ($LASTEXITCODE -ne 0) {
        throw "iverilog failed for $CaseName ($Mode)."
    }

    & vvp $simExe +CASE_NAME=$CaseName +MAT_DIM=$matDim | Tee-Object -FilePath $logFile | Out-Host
    if ($LASTEXITCODE -ne 0) {
        throw "vvp failed for $CaseName ($Mode)."
    }

    Write-Host "TILED_DEMO case=$CaseName dim=$matDim mode=$Mode"
    Write-Host "Log: $logFile"
}
finally {
    Release-FlowLock
}
