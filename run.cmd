@ECHO OFF
cd %~dp0
SET ExePath=.\zig-out\bin\1brc.cli.exe
:: Based on the least active cores on my specific PC. You should change this
SET AFFINITY=0x0000000000000200

if exist %ExePath% del %ExePath%
zig build -Doptimize=ReleaseFast -freference-trace
if exist %ExePath% (
    cls
    start /B /WAIT /HIGH /AFFINITY %AFFINITY% "OneBillionRows" %ExePath%
    pause
)