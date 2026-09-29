@echo off
rem Starts the bookkeeping form. Uses the system image if one has been built
rem (see sysimage\README.md); works perfectly well without it, just slower.
cd /d "%~dp0"
if exist "sysimage\ldgr.dll" (
  julia -J sysimage\ldgr.dll --startup-file=no server.jl %*
) else (
  julia --startup-file=no server.jl %*
)
