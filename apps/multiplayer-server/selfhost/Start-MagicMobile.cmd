@echo off
setlocal
set "MAGICMOBILE_LAUNCHER_DIR=%~dp0"
rem Execute this downloaded launcher's commands without changing PowerShell policy.
powershell.exe -NoProfile -Command "$ErrorActionPreference='Stop'; try { & ([scriptblock]::Create([IO.File]::ReadAllText((Join-Path $env:MAGICMOBILE_LAUNCHER_DIR 'Launch-MagicMobile.ps1')))) } catch { Write-Host $_ -ForegroundColor Red; exit 1 }"
echo.
echo Server stopped. This window can now be closed.
pause
endlocal
