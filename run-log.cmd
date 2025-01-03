@ECHO OFF
cd %~dp0
cls
zig build run -Doptimize=Debug -freference-trace > run.log 2>&1