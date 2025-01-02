@ECHO OFF
cd %~dp0
zig build -Doptimize=ReleaseFast
cls
.\zig-out\bin\1brc.cli.exe
pause