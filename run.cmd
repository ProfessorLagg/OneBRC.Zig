@ECHO OFF
cd %~dp0
SET ExePath=.\zig-out\bin\1brc.cli.exe
if exist %ExePath% del %ExePath%
zig build -Doptimize=ReleaseFast
cls
%ExePath%
pause