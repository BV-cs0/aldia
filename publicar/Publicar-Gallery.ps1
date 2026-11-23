# Publica Al Día en la PowerShell Gallery.
# Uso:   .\publicar\Publicar-Gallery.ps1           (pide la clave y publica)
#        .\publicar\Publicar-Gallery.ps1 -Prueba   (solo prepara y comprueba el paquete)
# Solo se publican los archivos de FileList (Aldia.psd1): nada de pruebas ni archivos internos.
param([switch]$Prueba)
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

$raiz = Split-Path $PSScriptRoot
$manifiesto = Import-PowerShellDataFile (Join-Path $raiz 'Aldia.psd1')

$faltan = @(Get-ChildItem -LiteralPath (Join-Path $raiz 'src') -Filter '*.ps1' | Where-Object { "src\$($_.Name)" -notin $manifiesto.FileList })
if ($faltan.Count) { throw "Añade estos archivos a FileList en Aldia.psd1: $($faltan.Name -join ', ')" }

$destino = Join-Path ([IO.Path]::GetTempPath()) 'aldia-publicar\Aldia'
if (Test-Path -LiteralPath $destino) { Remove-Item -LiteralPath $destino -Recurse -Force }
foreach ($archivo in $manifiesto.FileList) {
    $copia = Join-Path $destino $archivo
    $null = New-Item -ItemType Directory -Force (Split-Path $copia)
    Copy-Item -LiteralPath (Join-Path $raiz $archivo) -Destination $copia
}
$modulo = Test-ModuleManifest (Join-Path $destino 'Aldia.psd1')
Write-Host "Paquete Aldia $($modulo.Version) preparado en $destino" -ForegroundColor Green
if ($Prueba) { return }

if (!(Get-Module Microsoft.PowerShell.PSResourceGet -ListAvailable)) {
    Write-Host 'Instalando la herramienta oficial de Microsoft para publicar (PSResourceGet)...'
    Install-Module Microsoft.PowerShell.PSResourceGet -Repository PSGallery -Scope CurrentUser -Force
}
Import-Module Microsoft.PowerShell.PSResourceGet

$clave = Read-Host 'Pega tu clave de la PowerShell Gallery (no se verá al escribir)' -AsSecureString
$puntero = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($clave)
try {
    $texto = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($puntero)
    Publish-PSResource -Path $destino -Repository PSGallery -ApiKey $texto
} finally {
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($puntero)
}
Write-Host "Publicado. En unos minutos estará en https://www.powershellgallery.com/packages/Aldia" -ForegroundColor Green
