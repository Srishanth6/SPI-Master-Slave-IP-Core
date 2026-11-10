# Run the Icarus directed tests with OSS CAD Suite on Windows.
# Prerequisites: OSS CAD Suite at C:\oss-cad-suite

$ErrorActionPreference = "Stop"
$root = $PSScriptRoot
Set-Location $root

$envBat = "C:\oss-cad-suite\environment.bat"
if (-not (Test-Path $envBat)) {
    Write-Host "OSS CAD Suite not found at C:\oss-cad-suite"
    exit 1
}

# Import the suite into this PowerShell session
cmd /c "`"$envBat`" && set" | ForEach-Object {
    if ($_ -match "^(.*?)=(.*)$") {
        [System.Environment]::SetEnvironmentVariable($matches[1], $matches[2])
    }
}

New-Item -ItemType Directory -Force -Path build, waves, results | Out-Null

Write-Host "=== tb_spi_core ==="
& iverilog -g2012 -o build/tb_spi_core rtl/spi_master.v rtl/spi_slave.v rtl/spi_apb.v rtl/spi_loopback.v tb/spi_monitor.v tb/tb_spi_core.v
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& vvp -n build/tb_spi_core 2>&1 | Tee-Object results/tb_spi_core.log
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host "=== tb_spi_apb ==="
& iverilog -g2012 -o build/tb_spi_apb rtl/spi_master.v rtl/spi_slave.v rtl/spi_apb.v rtl/spi_loopback.v tb/spi_monitor.v tb/tb_spi_apb.v
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& vvp -n build/tb_spi_apb 2>&1 | Tee-Object results/tb_spi_apb.log
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host "Done. Waveforms are in waves/, logs in results/."
Write-Host "For GTKWave: gtkwave waves\tb_spi_core.vcd"
