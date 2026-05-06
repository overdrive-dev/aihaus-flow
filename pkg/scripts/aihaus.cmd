@echo off
:: aihaus.cmd — Windows cmd.exe wrapper for the aihaus CLI shim
:: M022/Z5 — FR-10; ADR-260504-A §6.1
:: Locates bash (Git Bash / WSL bash) and delegates to aihaus POSIX shim.
:: Falls back to aihaus.ps1 if no bash is found on PATH.
where bash >nul 2>nul
if %ERRORLEVEL%==0 (
    bash "%~dp0aihaus" %*
) else (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0aihaus.ps1" %*
)
