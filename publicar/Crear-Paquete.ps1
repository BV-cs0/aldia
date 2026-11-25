# Crea el paquete que usan las actualizaciones automáticas: Aldia-<versión>.zip y su .sha256.
# Uso:   .\publicar\Crear-Paquete.ps1 [-Salida carpeta]
# Lo ejecuta el flujo de GitHub al publicar una etiqueta vX.Y.Z; también sirve para probarlo en local.
# Solo entran los archivos de FileList (Aldia.psd1), igual que en la PowerShell Gallery.
param([string]$Salida = (Join-Path (Split-Path $PSScriptRoot) 'paquete'))
$ErrorActionPreference = 'Stop'

$raiz = Split-Path $PSScriptRoot
$manifiesto = Import-PowerShellDataFile (Join-Path $raiz 'Aldia.psd1')
$faltan = @(Get-ChildItem -LiteralPath (Join-Path $raiz 'src') -Filter '*.ps1' | Where-Object { "src\$($_.Name)" -notin $manifiesto.FileList })
if ($faltan.Count) { throw "Añade estos archivos a FileList en Aldia.psd1: $($faltan.Name -join ', ')" }

$version = [string]$manifiesto.ModuleVersion
$nombre = "Aldia-$version.zip"
$null = New-Item -ItemType Directory -Force $Salida
$zip = Join-Path $Salida $nombre
if (Test-Path -LiteralPath $zip) { Remove-Item -LiteralPath $zip -Force }

Add-Type -AssemblyName System.IO.Compression.FileSystem
$archivo = [IO.Compression.ZipFile]::Open($zip, 'Create')
try {
    foreach ($ruta in $manifiesto.FileList) {
        # Barras normales: es lo que espera cualquier descompresor, también el de Al Día.
        $null = [IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archivo, (Join-Path $raiz $ruta), ($ruta -replace '\\', '/'), 'Optimal')
    }
} finally { $archivo.Dispose() }

$hash = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLowerInvariant()
[IO.File]::WriteAllText("$zip.sha256", "$hash  $nombre`n", [Text.UTF8Encoding]::new($false))
Write-Host "Paquete $nombre listo en $Salida (SHA-256 $hash)" -ForegroundColor Green
