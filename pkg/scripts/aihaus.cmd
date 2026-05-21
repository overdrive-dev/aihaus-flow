@echo off
:: aihaus.cmd — Windows cmd.exe wrapper for the aihaus CLI shim
:: M022/Z5 — FR-10; ADR-260504-A §6.1
:: Locates bash (prefer Git Bash; WSL bash may be an unusable stub) and delegates to aihaus POSIX shim.
:: Falls back to aihaus.ps1 if no bash is found on PATH.
set "GIT_BASH=%ProgramFiles%\Git\bin\bash.exe"
if exist "%GIT_BASH%" (
    "%GIT_BASH%" "%~dp0aihaus" %*
) else (
    where bash >nul 2>nul
    if %ERRORLEVEL%==0 (
        bash "%~dp0aihaus" %*
    ) else (
        powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0aihaus.ps1" %*
    )
)
