@ECHO OFF
cd %~dp0
SET ExePath=.\zig-out\bin\1brc.cli.exe
if exist %ExePath% del %ExePath%
zig build -Doptimize=ReleaseSafe -freference-trace
if exist %ExePath% (
    cls
    %ExePath% > run-debug.log
    pause
)