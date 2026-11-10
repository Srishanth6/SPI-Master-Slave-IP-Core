@echo off
REM Run the Icarus directed tests with OSS CAD Suite on Windows.
REM Prerequisites: OSS CAD Suite at C:\oss-cad-suite

if exist C:\oss-cad-suite\environment.bat (
  call C:\oss-cad-suite\environment.bat
) else (
  echo OSS CAD Suite not found at C:\oss-cad-suite
  exit /b 1
)

if not exist build mkdir build
if not exist waves mkdir waves
if not exist results mkdir results

echo === tb_spi_core ===
iverilog -g2012 -o build/tb_spi_core rtl/spi_master.v rtl/spi_slave.v rtl/spi_apb.v rtl/spi_loopback.v tb/spi_monitor.v tb/tb_spi_core.v
if errorlevel 1 exit /b 1
vvp -n build/tb_spi_core > results\tb_spi_core.log
type results\tb_spi_core.log

echo === tb_spi_apb ===
iverilog -g2012 -o build/tb_spi_apb rtl/spi_master.v rtl/spi_slave.v rtl/spi_apb.v rtl/spi_loopback.v tb/spi_monitor.v tb/tb_spi_apb.v
if errorlevel 1 exit /b 1
vvp -n build/tb_spi_apb > results\tb_spi_apb.log
type results\tb_spi_apb.log

echo Done. Waveforms are in waves\, logs in results\.
echo For GTKWave: gtkwave waves\tb_spi_core.vcd
