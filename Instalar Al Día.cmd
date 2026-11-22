@echo off
setlocal DisableDelayedExpansion
set "ALDIA_CARPETA=%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$base=$env:ALDIA_CARPETA; Get-ChildItem -LiteralPath $base -File | Unblock-File; foreach($dir in 'src','gui','datos'){Get-ChildItem -LiteralPath (Join-Path $base $dir) -File | Unblock-File}"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0aldia.ps1" instalar --desde-lanzador
if not errorlevel 1 powershell.exe -NoProfile -Command "Write-Host ('Listo. Ya tienes Al D{0}a en el escritorio' -f [char]237)"
pause
