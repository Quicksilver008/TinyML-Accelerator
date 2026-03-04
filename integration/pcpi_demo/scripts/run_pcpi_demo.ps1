Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$demoDir = Split-Path -Parent $scriptDir
$repoRoot = Split-Path -Parent (Split-Path -Parent $demoDir)
$fwDir = Join-Path $demoDir "firmware"
$resultsDir = Join-Path $demoDir "results"

New-Item -ItemType Directory -Force $resultsDir | Out-Null

$simExe = Join-Path $resultsDir "pcpi_demo_tb.out"
$logFile = Join-Path $resultsDir "pcpi_demo.log"
$fwHex = Join-Path $fwDir "firmware.hex"

$sources = @(
    (Join-Path $repoRoot "picorv32\picorv32.v"),
    (Join-Path $repoRoot "midsem_sim\rtl\pe_cell_q5_10.v"),
    (Join-Path $repoRoot "midsem_sim\rtl\issue_logic_4x4_q5_10.v"),
    (Join-Path $repoRoot "midsem_sim\rtl\systolic_array_4x4_q5_10.v"),
    (Join-Path $repoRoot "midsem_sim\rtl\matrix_accel_4x4_q5_10.v"),
    (Join-Path $demoDir "rtl\pcpi_tinyml_accel.v"),
    (Join-Path $demoDir "tb\tb_picorv32_pcpi_tinyml.v")
)

$toolchain = Get-Command riscv64-unknown-elf-gcc -ErrorAction SilentlyContinue
if ($toolchain) {
    Write-Host "RISC-V toolchain found. Building firmware..."
    & make -C $fwDir clean all
    if ($LASTEXITCODE -ne 0) {
        throw "Firmware build failed with exit code $LASTEXITCODE"
    }
} elseif (Test-Path $fwHex) {
    $fwSourceFiles = @(
        (Join-Path $fwDir "firmware.S"),
        (Join-Path $fwDir "sections.lds"),
        (Join-Path $fwDir "Makefile")
    )
    $hexTime = (Get-Item $fwHex).LastWriteTimeUtc
    $newerSource = $fwSourceFiles | Where-Object { (Get-Item $_).LastWriteTimeUtc -gt $hexTime } | Select-Object -First 1
    if ($newerSource) {
        throw "RISC-V toolchain missing and firmware sources are newer than firmware.hex. Install toolchain and rebuild firmware."
    }
    Write-Host "RISC-V toolchain not found. Using existing firmware hex: $fwHex"
} else {
    throw "RISC-V toolchain is missing and no prebuilt firmware hex exists at $fwHex"
}

Write-Host "Compiling PCPI integration demo..."
& iverilog -g2012 -o $simExe @sources
if ($LASTEXITCODE -ne 0) {
    throw "iverilog compilation failed with exit code $LASTEXITCODE"
}

Write-Host "Running PCPI integration demo..."
& vvp $simExe | Tee-Object -FilePath $logFile
if ($LASTEXITCODE -ne 0) {
    throw "vvp simulation failed with exit code $LASTEXITCODE"
}

Write-Host "Done."
Write-Host "Log: $logFile"
Write-Host "Waveform: integration/pcpi_demo/results/pcpi_demo_wave.vcd"
