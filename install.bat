@echo off
:: EPSILON — Script d'installation Windows
:: Usage one-line : powershell -ExecutionPolicy Bypass -Command "irm https://raw.githubusercontent.com/ioup3409/EPSILON-install/main/install.ps1 | iex"
:: Usage local    : double-clic ou : install.bat

:: Délégation à PowerShell (logique dans install.ps1 du repo public EPSILON-install)
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$script = (New-Object Net.WebClient).DownloadString('https://raw.githubusercontent.com/ioup3409/EPSILON-install/main/install.ps1'); Invoke-Expression $script"

pause
