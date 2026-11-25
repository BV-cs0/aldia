Import-Module (Join-Path (Split-Path $PSScriptRoot) 'Aldia.psd1') -Force

Describe 'Actualización automática' {
    InModuleScope Aldia {
        function New-PaquetePrueba {
            param([string]$Carpeta, [string]$Version, [string[]]$Extra = @(), [string[]]$Rutas = @())
            $origen = Join-Path $Carpeta "origen-$Version"
            $lista = @('aldia.ps1', 'Aldia.psm1', 'Aldia.psd1', 'src\Uno.ps1') + $Extra
            foreach ($a in $lista) {
                $null = New-Item -ItemType Directory -Force (Split-Path (Join-Path $origen $a))
                Set-Content -LiteralPath (Join-Path $origen $a) -Value "# $a $Version" -Encoding UTF8
            }
            $fileList = ($lista | Where-Object { $_ -notin $Extra } | ForEach-Object { "'$_'" }) -join ','
            Set-Content -LiteralPath (Join-Path $origen 'Aldia.psd1') -Value "@{ ModuleVersion = '$Version'; FileList = @($fileList) }" -Encoding UTF8
            Add-Type -AssemblyName System.IO.Compression.FileSystem
            $zip = Join-Path $Carpeta "Aldia-$Version.zip"
            if (Test-Path $zip) { Remove-Item $zip }
            $archivo = [IO.Compression.ZipFile]::Open($zip, 'Create')
            try {
                foreach ($a in $lista) {
                    $null = [IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archivo, (Join-Path $origen $a), ($a -replace '\\', '/'))
                }
                foreach ($r in $Rutas) { $null = $archivo.CreateEntry($r) }
            } finally { $archivo.Dispose() }
            Set-Content -LiteralPath "$zip.sha256" -Value "$((Get-FileHash $zip -Algorithm SHA256).Hash.ToLower())  Aldia-$Version.zip" -Encoding Ascii
            $zip
        }

        function New-CarpetaPortatil {
            param([string]$Ruta, [string]$Version)
            $null = New-Item -ItemType Directory -Force (Join-Path $Ruta 'src')
            Set-Content (Join-Path $Ruta 'Aldia.psd1') "@{ ModuleVersion = '$Version'; FileList = @() }" -Encoding UTF8
            Set-Content (Join-Path $Ruta 'src\Viejo.ps1') '# ya no existe en la versión nueva' -Encoding UTF8
            Set-Content (Join-Path $Ruta 'config.json') '{"mio":true}' -Encoding UTF8
        }

        Context 'compara versiones' {
            It 'detecta solo versiones estables más nuevas' {
                Test-AldiaVersionNueva '1.0.1' '1.1.0' | Should Be $true
                Test-AldiaVersionNueva '1.0.1' 'v1.0.2' | Should Be $true
                Test-AldiaVersionNueva '1.9.0' '1.10.0' | Should Be $true
                Test-AldiaVersionNueva '1.1' '1.1.0' | Should Be $false
                Test-AldiaVersionNueva '1.1.0' '1.0.9' | Should Be $false
                Test-AldiaVersionNueva '1.0.1' '1.1.0-beta' | Should Be $false
                Test-AldiaVersionNueva '1.0.1' '' | Should Be $false
                Test-AldiaVersionNueva '1.0.1' $null | Should Be $false
                Test-AldiaVersionNueva 'raro' '9.9.9' | Should Be $false
            }
        }

        Context 'consulta la release oficial' {
            $release = {
                [pscustomobject]@{ tag_name = 'v1.2.0'; draft = $false; prerelease = $false; assets = @(
                    [pscustomobject]@{ name = 'Aldia-1.2.0.zip'; browser_download_url = 'https://github.com/BV-cs0/aldia/releases/download/v1.2.0/Aldia-1.2.0.zip' }
                    [pscustomobject]@{ name = 'Aldia-1.2.0.zip.sha256'; browser_download_url = 'https://github.com/BV-cs0/aldia/releases/download/v1.2.0/Aldia-1.2.0.zip.sha256' }) }
            }
            It 'devuelve la versión y las URL del canal oficial' {
                Mock Invoke-AldiaHttp $release
                $r = Get-AldiaUltimaRelease
                $r.Version | Should Be '1.2.0'
                $r.Zip | Should Be 'https://github.com/BV-cs0/aldia/releases/download/v1.2.0/Aldia-1.2.0.zip'
            }
            It 'rechaza descargas fuera del repositorio oficial' {
                Mock Invoke-AldiaHttp {
                    $r = & $release
                    $r.assets[0].browser_download_url = 'https://evil.example/Aldia-1.2.0.zip'
                    $r
                }
                Get-AldiaUltimaRelease | Should Be $null
            }
            It 'ignora las versiones previas y la ausencia de releases' {
                Mock Invoke-AldiaHttp { $r = & $release; $r.prerelease = $true; $r }
                Get-AldiaUltimaRelease | Should Be $null
            }
            It 'sin ninguna release publicada (404) devuelve nada, sin error' {
                Mock Invoke-AldiaHttp {
                    $respuesta = [pscustomobject]@{ StatusCode = 404 }
                    $error404 = [Net.WebException]::new('404')
                    $error404 | Add-Member -NotePropertyName Response -NotePropertyValue $respuesta -Force
                    throw $error404
                }
                Get-AldiaUltimaRelease | Should Be $null
            }
            It 'Save-AldiaDescarga solo acepta el origen oficial' {
                { Save-AldiaDescarga 'https://evil.example/x.zip' (Join-Path $TestDrive 'x') 5 } | Should Throw
            }
        }

        Context 'los fallos de red nunca se propagan' {
            It 'la tarea programada sigue aunque falle todo' {
                Mock Get-AldiaCanal { 'instalado' }
                Mock Invoke-AldiaHttp { throw [Net.WebException]::new('sin conexión') }
                Mock Write-AldiaLog {}
                { Update-AldiaInstalado 'C:\Program Files\Aldia' } | Should Not Throw
                Assert-MockCalled Write-AldiaLog -Times 1 -Exactly -Scope It
            }
            It 'sin releases publicadas no ensucia el registro' {
                Mock Get-AldiaCanal { 'instalado' }
                Mock Get-AldiaUltimaRelease { $null }
                Mock Write-AldiaLog {}
                Update-AldiaInstalado 'C:\Program Files\Aldia'
                Assert-MockCalled Write-AldiaLog -Times 0 -Exactly -Scope It
            }
            It 'el aviso de la Gallery no falla con el estado roto ni sin red' {
                Mock Get-AldiaCanal { 'galeria' }
                $estado = Join-Path $TestDrive 'roto.json'
                Set-Content $estado '{roto' -Encoding UTF8
                { Show-AldiaAvisoVersion $TestDrive $estado } | Should Not Throw
                Mock Invoke-AldiaHttp { throw [Net.WebException]::new('sin conexión') }
                { Update-AldiaEstadoGaleria (Join-Path $TestDrive 'e.json') } | Should Throw
            }
            It 'la portátil no falla si no puede descargar ni aplicar' {
                Mock Get-AldiaCanal { 'portatil' }
                { Complete-AldiaActualizacionPortatil (Join-Path $TestDrive 'no-existe') } | Should Not Throw
            }
        }

        Context 'aviso de la Gallery' {
            It 'avisa una sola vez por versión, en una línea' {
                Mock Get-AldiaCanal { 'galeria' }
                Mock Get-AldiaVersionLocal { '1.0.1' }
                Mock Write-Host {}
                $estado = Join-Path $TestDrive 'version.json'
                $ahora = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
                Set-Content $estado "{`"ultima`":`"1.1.0`",`"comprobado`":$ahora}" -Encoding UTF8
                Show-AldiaAvisoVersion $TestDrive $estado
                Show-AldiaAvisoVersion $TestDrive $estado
                Assert-MockCalled Write-Host -Times 1 -Exactly -Scope It -ParameterFilter { $Object -like '*1.1.0*Update-Module Aldia*' }
            }
        }

        Context 'descarga, verifica y aplica' {
            It 'actualiza la carpeta portátil al cerrar y quita los .ps1 que ya no existen' {
                $carpeta = Join-Path $TestDrive 'portatil'
                New-CarpetaPortatil $carpeta '1.0.0'
                $zip = New-PaquetePrueba $TestDrive '1.2.0'
                Mock Get-AldiaUltimaRelease { [pscustomobject]@{ Version = '1.2.0'; Zip = $zip; Sha = "$zip.sha256"; Nombre = 'Aldia-1.2.0.zip' } }
                Mock Save-AldiaDescarga { Copy-Item -LiteralPath $Uri -Destination $Destino }
                Mock Get-AldiaCanal { 'portatil' }
                Save-AldiaActualizacion $carpeta (Join-Path $carpeta '.actualizacion') | Should Be '1.2.0'
                Complete-AldiaActualizacionPortatil $carpeta
                Get-AldiaVersionLocal $carpeta | Should Be '1.2.0'
                Test-Path (Join-Path $carpeta 'src\Uno.ps1') | Should Be $true
                Test-Path (Join-Path $carpeta 'src\Viejo.ps1') | Should Be $false
                Get-Content (Join-Path $carpeta 'config.json') | Should Be '{"mio":true}'
                Test-Path (Join-Path $carpeta '.actualizacion\pendiente.json') | Should Be $false
            }
            It 'no deja nada preparado si el SHA-256 no coincide' {
                $carpeta = Join-Path $TestDrive 'hash'
                New-CarpetaPortatil $carpeta '1.0.0'
                $zip = New-PaquetePrueba $TestDrive '1.3.0'
                Set-Content "$zip.sha256" ('0' * 64) -Encoding Ascii
                Mock Get-AldiaUltimaRelease { [pscustomobject]@{ Version = '1.3.0'; Zip = $zip; Sha = "$zip.sha256"; Nombre = 'Aldia-1.3.0.zip' } }
                Mock Save-AldiaDescarga { Copy-Item -LiteralPath $Uri -Destination $Destino }
                { Save-AldiaActualizacion $carpeta (Join-Path $carpeta '.actualizacion') } | Should Throw
                Test-Path (Join-Path $carpeta '.actualizacion\pendiente.json') | Should Be $false
                Test-Path (Join-Path $carpeta '.actualizacion\Aldia-1.3.0.zip') | Should Be $false
            }
            It 'no aplica un paquete que cambió después de verificarlo' {
                $carpeta = Join-Path $TestDrive 'cambiado'
                New-CarpetaPortatil $carpeta '1.0.0'
                $zip = New-PaquetePrueba $TestDrive '1.4.0'
                Mock Get-AldiaUltimaRelease { [pscustomobject]@{ Version = '1.4.0'; Zip = $zip; Sha = "$zip.sha256"; Nombre = 'Aldia-1.4.0.zip' } }
                Mock Save-AldiaDescarga { Copy-Item -LiteralPath $Uri -Destination $Destino }
                $null = Save-AldiaActualizacion $carpeta (Join-Path $carpeta '.actualizacion')
                Add-Content (Join-Path $carpeta '.actualizacion\Aldia-1.4.0.zip') 'basura'
                { Install-AldiaActualizacionPendiente $carpeta (Join-Path $carpeta '.actualizacion') } | Should Throw
                Get-AldiaVersionLocal $carpeta | Should Be '1.0.0'
            }
            It 'rechaza rutas que salen de la carpeta (zip slip)' {
                $zip = New-PaquetePrueba $TestDrive '1.5.0' -Rutas @('../fuera.ps1')
                { Expand-AldiaPaquete $zip (Join-Path $TestDrive 'slip') } | Should Throw
                Test-Path (Join-Path $TestDrive 'fuera.ps1') | Should Be $false
            }
            It 'rechaza un paquete con archivos que no están en su manifiesto' {
                $zip = New-PaquetePrueba $TestDrive '1.6.0' -Extra @('src\Intruso.ps1')
                $destino = Join-Path $TestDrive 'extra'
                Expand-AldiaPaquete $zip $destino
                { Get-AldiaArchivosPaquete $destino '1.6.0' } | Should Throw
            }
            It 'rechaza un paquete de otra versión' {
                $zip = New-PaquetePrueba $TestDrive '1.7.0'
                $destino = Join-Path $TestDrive 'otra'
                Expand-AldiaPaquete $zip $destino
                { Get-AldiaArchivosPaquete $destino '1.8.0' } | Should Throw
            }
        }

        Context 'canales' {
            It 'distingue instalada, desarrollo, Gallery y portátil' {
                Mock Get-AldiaProgramFiles { 'C:\Program Files\Aldia' }
                Get-AldiaCanal 'C:\Program Files\Aldia\' | Should Be 'instalado'
                $git = Join-Path $TestDrive 'repo'
                $null = New-Item -ItemType Directory -Force (Join-Path $git '.git')
                Get-AldiaCanal $git | Should Be 'desarrollo'
                $env:PSModulePath, $antes = (Join-Path $TestDrive 'Modulos'), $env:PSModulePath
                try { Get-AldiaCanal (Join-Path $TestDrive 'Modulos\Aldia\1.0.1') | Should Be 'galeria' }
                finally { $env:PSModulePath = $antes }
                Get-AldiaCanal 'E:\USB\Aldia' | Should Be 'portatil'
            }
        }
    }
}
