@echo off
setlocal DisableDelayedExpansion
set "ALDIA_CARPETA=%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$base=$env:ALDIA_CARPETA; Get-ChildItem -LiteralPath $base -File | Unblock-File; foreach($dir in 'src','gui','datos'){Get-ChildItem -LiteralPath (Join-Path $base $dir) -File | Unblock-File}"
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0aldia.ps1" gui --portatil
