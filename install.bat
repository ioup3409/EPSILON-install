@echo off
:: EPSILON — Script d'installation Windows
:: Usage one-line : powershell -ExecutionPolicy Bypass -Command "irm https://raw.githubusercontent.com/ioup3409/EPSILON-install/main/install.ps1 | iex"
:: Usage local    : double-clic ou : install.bat

:: Délégation à PowerShell (logique dans install.ps1 du repo public EPSILON-install)
::
:: 🔴 `irm`, et JAMAIS `WebClient.DownloadString` — mesuré le 2026-09-09.
:: GitHub sert le script en `text/plain; charset=utf-8`. `Invoke-RestMethod` respecte
:: ce charset et rend le texte intact (95 accents corrects, 0 erreur de syntaxe).
:: `WebClient.DownloadString` l'IGNORE et décode en Windows-1252 : 104 séquences
:: illisibles, et le script téléchargé ne se PARSE PLUS (3 erreurs) — donc
:: `Invoke-Expression` recevait du texte corrompu et l'installation ne pouvait pas
:: aboutir. C'était le chemin du double-clic, celui de l'utilisateur non technique,
:: alors que la commande à copier-coller de la ligne 3 fonctionnait déjà.
:: ⚠️ Ne pas « revenir à WebClient pour éviter une dépendance » : l'échec est
::    silencieux côté encodage, et l'erreur affichée parle de syntaxe PowerShell.
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "irm 'https://raw.githubusercontent.com/ioup3409/EPSILON-install/main/install.ps1' -UseBasicParsing | iex"

pause
