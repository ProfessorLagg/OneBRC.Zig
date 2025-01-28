@ECHO OFF
cd %~dp0
SET ExePath=.\zig-out\bin\1brc.cli.exe
if exist %ExePath% del %ExePath%
::zig build -Doptimize=Debug -freference-trace
zig build -Doptimize=ReleaseFast -freference-trace
if exist %ExePath% (
    cls
    %ExePath% > run.log 2>&1
)