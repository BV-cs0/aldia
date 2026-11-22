Import-Module (Join-Path (Split-Path $PSScriptRoot) 'Aldia.psd1') -Force

Describe 'Ronda B: correcciones de seguridad y salud' {
    InModuleScope Aldia {
        function script:Read-AldiaFixtureRondaB($Nombre) {
            Get-Content -LiteralPath (Join-Path (Split-Path $PSScriptRoot) "tests\fixtures\$Nombre") -Raw -Encoding UTF8
        }

        It 'descarta Node.js como plataforma y conserva Next.js solo dentro del rango vulnerable' {
            $nvd = Read-AldiaFixtureRondaB 'nvd-cve-2021-43803.json' | ConvertFrom-Json
            @(ConvertFrom-AldiaNvd $nvd 'nodejs:node.js' '24.22.2').Count | Should Be 0
            @(ConvertFrom-AldiaNvd $nvd 'vercel:next.js' '12.0.5').Count | Should Be 0
            $r = ConvertFrom-AldiaNvd $nvd 'vercel:next.js' '12.0.0'
            $r.Id | Should Be 'CVE-2021-43803'
            $r.CpeMatch.Count | Should Be 1
            $r.CpeMatch[0].vulnerable | Should Be $true
            $r.Published | Should Match '^2021'
            Compare-AldiaVersionNumerica '8.41.7187.501' '8.41' | Should Be 1
            (Test-AldiaVersionNvd @{} '8.41.00' '8.41') | Should Be $true
            (Test-AldiaVersionNvd @{ versionEndIncluding='8.41' } 'versión desconocida' '*') | Should Be $true
        }

        It 'ignora entradas antiguas de NVD incluso cuando la nueva consulta falla' {
            $cache = Join-Path (Get-PSDrive TestDrive).Root 'cache-b'
            $null = Get-AldiaCacheSeguridad 'nvd|nodejs:node.js|24.22.2' 24 {
                @{ Id='CVE-2021-43803'; Cvss=7.5 }
            } -Directorio $cache
            Mock Invoke-AldiaHttp { throw 'Sin conexión' } -ParameterFilter { $Uri -like '*cves/2.0*' }
            (Get-AldiaCvesNvd 'nodejs:node.js' '24.22.2' @{} $cache).Disponible | Should Be $false
            Assert-MockCalled Invoke-AldiaHttp -Scope It -Times 1 -Exactly
        }

        It 'limita a Bajo por antigüedad o versión comodín y muestra el año de publicación' {
            $m = @{ vulnerable=$true; criteria='cpe:2.3:a:apple:bonjour:*:*:*:*:*:*:*:*'; versionEndIncluding='2011' }
            $cve = @{ id='CVE-2011-0220'; published='2011-01-01'; configurations=@(@{nodes=@(@{cpeMatch=@($m)})});
                metrics=@{ cvssMetricV31=@(@{cvssData=@{baseScore=9.8}}) } }
            $nvd = @{ vulnerabilities=@(@{cve=$cve}) }
            $p = @{ Nombre='Bonjour'; Id='Apple.Bonjour'; Version='3.1.0.1'; Fuente='apps' }
            $ctx = @{ Kev=@{}; Epss=@{} }
            $hallazgo = ConvertFrom-AldiaNvd $nvd 'apple:bonjour' $p.Version
            $r = New-AldiaInformePrograma $p @{ Datos=@($hallazgo); Disponible=$true; Edad=0 } $ctx
            $r.Riesgo | Should Be 'Bajo'
            $r.Anio | Should Be '2011'
            $r.Detalle | Should Match 'dato antiguo o impreciso'
            $m.Remove('versionEndIncluding')
            $cve.published = (Get-Date).ToString('yyyy-MM-dd')
            (ConvertFrom-AldiaNvd $nvd 'apple:bonjour' $p.Version).Impreciso | Should Be $true
        }

        It 'parsea toda la lista real y conserva las cuatro versiones de Visual C++ desalineadas' {
            $texto = Read-AldiaFixtureRondaB 'winget-list-completa.txt'
            $filas = @(ConvertFrom-AldiaWinget $texto -ListaCompleta)
            $filas.Count | Should Be 206
            @($filas | Where-Object Version -in winget,msstore).Count | Should Be 0
            @($filas | Where-Object { $_.Id -match '^Microsoft\.VCRedist\.2008\.' -and $_.Version -eq '9.0.30729.6161' }).Count | Should Be 2
            @($filas | Where-Object { $_.Id -match '^Microsoft\.VCRedist\.2010\.' -and $_.Version -eq '10.0.40219' }).Count | Should Be 2
        }

        It 'admite npm ls con código 1 y unifica duplicados de arquitectura y nombre' {
            Mock Get-AldiaEditores { @{} }
            Mock Get-AldiaApps {
                ConvertFrom-AldiaWinget (Read-AldiaFixtureRondaB 'winget-list-completa.txt') -ListaCompleta
            }
            Mock Get-AldiaNpmEjecutable { 'npm.cmd' }
            Mock Invoke-AldiaComando { @{ Codigo=1; Salida='{"dependencies":{"demo":{"version":"1.0.0"}}}' } }
            $i = Get-AldiaInventarioSeguridad (Get-AldiaConfig)
            $i.Npm[0].Id | Should Be 'demo'
            Assert-MockCalled Invoke-AldiaComando -Scope It -Times 1 -Exactly -ParameterFilter { ($Argumentos -join ' ') -eq 'ls -g --json --depth 0' }
            $vc = @($i.Apps | Where-Object Id -match '^Microsoft\.VCRedist\.2010\.')
            $vc.Count | Should Be 1
            $vc[0].Ids.Count | Should Be 2
            $copilot = @($i.Apps | Where-Object Nombre -eq 'Copilot')
            $copilot.Count | Should Be 1
            $copilot[0].Id | Should Be 'Microsoft.365Copilot'
        }

        It 'envía un tiempo de espera HTTP de 60 segundos' {
            Mock Invoke-RestMethod { @{ totalResults=0 } }
            $null = Invoke-AldiaHttp 'https://api.first.org/data/v1/epss'
            Assert-MockCalled Invoke-RestMethod -Scope It -Times 1 -Exactly -ParameterFilter { $TimeoutSec -eq 60 }
        }

        It 'solo muestra hallazgos en el CLI y cuenta cada resultado en el resumen' {
            Mock Get-AldiaVulnerabilidades {
                @{ Programas=@(
                    @{ Nombre='Con fallo'; Nivel=1; Comprobado=$true; Detalle='CVE-2024-1234 · 2024' }
                    @{ Nombre='Sin fallo'; Nivel=0; Comprobado=$true }
                    @{ Nombre='Sin datos'; Nivel=0; Comprobado=$false }
                ) }
            }
            Mock Show-AldiaTabla {}
            Mock Write-Host {}
            Show-AldiaVulnerabilidadesCli (Get-AldiaConfig)
            Assert-MockCalled Show-AldiaTabla -Scope It -Times 1 -Exactly -ParameterFilter { @($Elementos).Count -eq 1 -and $Elementos[0].Nombre -eq 'Con fallo' }
            Assert-MockCalled Write-Host -Scope It -ParameterFilter { $Object -eq 'Revisados 3 programas: 1 con fallos, 1 sin fallos conocidos, 1 sin datos.' }
        }

        It 'agrupa conexiones duales, resume servicios internos y explica el puerto sensible' {
            Mock Get-NetTCPConnection {
                @{ LocalAddress='::'; LocalPort=445; OwningProcess=4 }
                @{ LocalAddress='0.0.0.0'; LocalPort=445; OwningProcess=4 }
                @{ LocalAddress='::'; LocalPort=49152; OwningProcess=4 }
                @{ LocalAddress='::'; LocalPort=49153; OwningProcess=6 }
            }
            Mock Get-Process {
                if ($Id -eq 4) { @{ ProcessName='System' } } else { @{ ProcessName='otro' } }
            }
            $r = Get-AldiaComprobacionSalud red
            $r.Estado | Should Be 'aviso'
            $r.Detalle | Should Be '1 servicio sensible abierto a la red y 1 servicio interno de Windows.'
            $r.Datos.Count | Should Be 2
            ($r.Datos | Where-Object Puerto -eq 445).Explicacion | Should Match 'Compartir archivos de Windows'
        }

        It 'muestra la tabla de salud y los servicios sin repetir el resto de comprobaciones' {
            Mock Get-AldiaSalud {
                @{ Id='uac'; Nombre='Control de cuentas'; Estado='bien'; Detalle='Detalle único' }
                @{ Id='red'; Estado='aviso'; Datos=@(@{ Direccion='Todas'; Puerto=445; Programa='System' }) }
            }
            Mock Show-AldiaTabla {}
            Mock Write-Host {}
            Show-AldiaSaludCli
            Assert-MockCalled Show-AldiaTabla -Scope It -Times 1 -Exactly
            Assert-MockCalled Write-Host -Scope It -Times 0 -Exactly -ParameterFilter { $Object -like '*Detalle único*' }
            Assert-MockCalled Write-Host -Scope It -Times 1 -Exactly -ParameterFilter { $Object -like '*puerto 445*' }
        }
    }
}

Describe 'Ronda B: adopción, reversión y fijados' {
    InModuleScope Aldia {
        It 'busca una vez, omite componentes y juegos y prefiere la versión mayor de Node.js' {
            $cache = Join-Path (Get-PSDrive TestDrive).Root 'adopcion'
            $config = Get-AldiaConfig
            $listado = @(ConvertFrom-AldiaWinget (Read-AldiaFixtureRondaB 'winget-list-completa.txt') -Inventario)
            $inventario = @($listado | Where-Object Nombre -eq 'Node.js') + @(
                @{ Nombre='Epic Games'; Id='ARP\User\Epic'; Version='1' }
                @{ Nombre='vs_CoreEditorFonts'; Id='ARP\User\Fonts'; Version='1' }
                @{ Nombre='???'; Id='ARP\User\SinNombre'; Version='1' }
            )
            Mock Get-AldiaEditores { @{} }
            Mock Invoke-AldiaComando { @{ Codigo=0; Salida=(Read-AldiaFixtureRondaB 'winget-search-nodejs.txt') } }
            $r = @(Get-AldiaAdopciones $config $inventario -Cache $cache)
            $r.Count | Should Be 1
            $r[0].Id | Should Be 'OpenJS.NodeJS.24'
            $r[0].Confianza | Should Be 'alta'
            (Get-AldiaAdopciones $config $inventario -Cache $cache).Id | Should Be 'OpenJS.NodeJS.24'
            Assert-MockCalled Invoke-AldiaComando -Scope It -Times 1 -Exactly -ParameterFilter { ($Argumentos -join ' ') -eq 'search --name Node.js --source winget --accept-source-agreements --disable-interactivity' }
        }

        It 'confirma la adopción solo cuando winget list devuelve el Id con origen' {
            Mock Invoke-AldiaComando {
                @{ Codigo=0; Salida=(Read-AldiaFixtureRondaB 'winget-list-completa.txt') }
            }
            (Invoke-AldiaAdopcion (Get-AldiaConfig) 'Git.Git') | Should Match 'lo mantendrá actualizado'
            { Invoke-AldiaAdopcion (Get-AldiaConfig) 'OpenJS.NodeJS.24' } | Should Throw 'no se pudo confirmar'
            Invoke-AldiaAdopcion (Get-AldiaConfig) 'Git.Git' -Demo | Should Match 'simulada'
            Assert-MockCalled Invoke-AldiaComando -Scope It -Times 1 -Exactly -ParameterFilter { $Argumentos[0] -eq 'install' -and $Argumentos[2] -eq 'Git.Git' }
            Assert-MockCalled Invoke-AldiaComando -Scope It -Times 1 -Exactly -ParameterFilter { $Argumentos[0] -eq 'list' -and $Argumentos[2] -eq 'Git.Git' }
        }

        It 'deshace una versión disponible de winget, fija el Id y registra revertido' {
            $c = Get-AldiaConfig
            $item = New-AldiaResultado apps 'Wibu-Systems.CodeMeterRuntimeKit' actualizado 0 '' '8.40.7144.504' '9.10.8178.501'
            Mock Invoke-AldiaComando { @{ Codigo=0; Salida=Read-AldiaFixtureRondaB 'winget-show-versions.txt' } }
            Mock Assert-AldiaPermisos {}
            Mock Save-AldiaFijados {} -ParameterFilter { $RutaConfig -like '*\config.json' }
            Mock Add-AldiaHistorial {}
            $configRuta = Join-Path (Get-PSDrive TestDrive).Root 'config.json'
            $historial = Join-Path (Get-PSDrive TestDrive).Root 'historial.jsonl'
            $plan = Get-AldiaPlanDeshacer $item
            $plan.Disponible | Should Be $true
            (Invoke-AldiaDeshacer $c $plan $configRuta $historial).Resultados[0].Estado | Should Be 'revertido'
            $c.fijados[0].version | Should Be '8.40.7144.504'
            @(Get-AldiaOrdenApps @(@{ Id=$item.Id }) $c).Count | Should Be 0
            Assert-MockCalled Save-AldiaFijados -Scope It -Times 1 -Exactly
            Assert-MockCalled Add-AldiaHistorial -Scope It -Times 1 -Exactly
            Assert-MockCalled Invoke-AldiaComando -Scope It -Times 1 -Exactly -ParameterFilter { $Argumentos[0] -eq 'install' -and $Argumentos -contains '--force' -and $Argumentos -contains '8.40.7144.504' }
            $item.Antes = '1.0'
            (Get-AldiaPlanDeshacer $item).Disponible | Should Be $false
            $item.Antes = 'Unknown'
            (Get-AldiaPlanDeshacer $item).Disponible | Should Be $false
        }

        It 'prepara npm y Windows, bloquea inteligencia de seguridad y da alternativas para drivers' {
            Mock Get-AldiaNpmEjecutable { 'npm.cmd' }
            $n = Get-AldiaPlanDeshacer (New-AldiaResultado npm '@org/demo' actualizado 0 '' '1.2.3' '2.0.0')
            $n.Argumentos -join ' ' | Should Be 'install -g @org/demo@1.2.3'
            $item = New-AldiaResultado windows 'update-id' actualizado 2 'KB123456'
            $w = Get-AldiaPlanDeshacer $item
            $w.Argumentos -join ' ' | Should Be '/uninstall /kb:123456 /quiet /norestart'
            $item.Titulo = 'Security Intelligence Update'
            (Get-AldiaPlanDeshacer $item).Disponible | Should Be $false
            Mock Get-AldiaProteccionGui { 'desactivada' }
            $driver = Get-AldiaPlanDeshacer (New-AldiaResultado drivers 'drv' actualizado 2 '')
            $driver.Controlador | Should Be $true
            $driver.Restaurar | Should Be $false
            (Get-AldiaPlanDeshacer $driver.Resultado -Demo).Restaurar | Should Be $true
        }

        It 'valida, guarda y lee fijados, incluso al desmarcar uno en modo demo' {
            $c = Get-AldiaConfig
            $entrada = [pscustomobject]@{ fuente='windows'; id='actualizacion'; version='KB123456'; fecha='2026-11-22'; motivo='Deshecho' }
            Merge-AldiaConfig $c ([pscustomobject]@{ fijados=@($entrada) })
            $c.fijados.Count | Should Be 1
            Test-AldiaWUFijada $c @{ Identity=@{ UpdateID='otro-id' }; KBArticleIDs=@('123456') } | Should Be $true
            Merge-AldiaConfig $c ([pscustomobject]@{ fijados=@([pscustomobject]@{ id='incompleto' }) })
            $c.fijados[0].id | Should Be 'actualizacion'
            Mock Assert-AldiaPermisos {}
            Mock Set-AldiaPropietarioAdmin {}
            $ruta = Join-Path (Get-PSDrive TestDrive).Root 'fijados.json'
            Save-AldiaFijados $c $ruta
            (Get-AldiaConfig $ruta).fijados[0].id | Should Be 'actualizacion'
            $cola = [Collections.Concurrent.ConcurrentQueue[object]]::new()
            $estado = @{ ConfigDemo=$c }
            Invoke-AldiaTrabajoGui desfijar $entrada $true $cola $estado
            $c.fijados.Count | Should Be 0
        }
    }
}
Describe 'Ronda B: integración de las órdenes y la ventana' {
    InModuleScope Aldia {
        It 'lista adopciones y fijados sin elevar y respeta la cancelación al adoptar' {
            Mock Get-AldiaAdopciones { [pscustomobject]@{ Nombre='Node.js'; Id='OpenJS.NodeJS.24' } }
            Mock Show-AldiaTabla {}
            Mock Test-AldiaAdmin { $true }
            Mock Read-Host { 'n' }
            Mock Invoke-AldiaCambioCli { throw 'No debe aplicar el cambio.' }
            Invoke-AldiaCli @('adoptar') 'prueba.ps1' | Should Be 0
            Invoke-AldiaCli @('fijados') 'prueba.ps1' | Should Be 0
            Assert-MockCalled Test-AldiaAdmin -Scope It -Times 0 -Exactly
            Assert-MockCalled Show-AldiaTabla -Scope It -Times 1 -Exactly -ParameterFilter { $Titulo -eq 'Programas que puedes adoptar' }
            Assert-MockCalled Show-AldiaTabla -Scope It -Times 1 -Exactly -ParameterFilter { $Titulo -eq 'Programas fijados' }
            Invoke-AldiaCli @('adoptar','--id','OpenJS.NodeJS.24') 'prueba.ps1' | Should Be 3
            Assert-MockCalled Invoke-AldiaCambioCli -Scope It -Times 0 -Exactly
        }

        It 'no guarda el fijado ni registra el historial si falla el comando de reversión' {
            Mock Assert-AldiaPermisos {}
            Mock Save-AldiaFijados {}
            Mock Add-AldiaHistorial {}
            Mock Invoke-AldiaComando { @{ Codigo=5; Timeout=$false } }
            $c = Get-AldiaConfig
            $item = New-AldiaResultado apps 'Ejemplo.App' actualizado 0 '' '1.0' '2.0'
            $plan = Get-AldiaPlanDeshacer $item -Demo
            $ruta = Join-Path (Get-PSDrive TestDrive).Root 'config-fallo.json'
            { Invoke-AldiaDeshacer $c $plan $ruta $ruta } | Should Throw 'No se pudo deshacer'
            $c.fijados.Count | Should Be 0
            Assert-MockCalled Save-AldiaFijados -Scope It -Times 0 -Exactly
            Assert-MockCalled Add-AldiaHistorial -Scope It -Times 0 -Exactly
        }

        It 'omite un paquete npm fijado y deja actualizar otro del mismo nombre en otra fuente' {
            Mock Get-AldiaNpmEjecutable { 'npm.cmd' }
            Mock Get-AldiaNpm {
                @{ Id='demo'; Version='1.0.0'; Disponible='2.0.0' }
                @{ Id='otro'; Version='1.0.0'; Disponible='2.0.0' }
            }
            Mock Invoke-AldiaComando { @{ Codigo=0 } }
            $c = Get-AldiaConfig
            $c.fijados = @([pscustomobject]@{ fuente='npm'; id='demo'; version='1.0.0' })
            (Update-AldiaNpm $c).Id | Should Be 'otro'
            @(Get-AldiaOrdenApps @(@{Id='demo'}) $c).Count | Should Be 1
            Assert-MockCalled Invoke-AldiaComando -Scope It -Times 1 -Exactly -ParameterFilter { $Argumentos -contains 'otro@latest' }
        }

        It 'muestra botones y disponibilidad de adopción, reversión y fijados en WPF' {
            $ventana = New-AldiaVentanaGui
            $script:AldiaGui = @{ Ventana=$ventana; Controles=@{} }
            try {
                foreach ($nombre in 'Inventario','Fijados','DetalleHistorial') {
                    $script:AldiaGui.Controles[$nombre] = $ventana.FindName($nombre)
                }
                $c = $script:AldiaGui.Controles
                Show-AldiaAdopcionesGui @(@{ Nombre='Node.js'; Id='ARP\Demo\Node'; Version='24.22.2' }) @(
                    @{ ArpId='ARP\Demo\Node'; Id='OpenJS.NodeJS.24'; Confianza='alta' }
                )
                $c.Inventario.Children[0].Child.Children[0].Content | Should Be 'Adoptar'
                $app = New-AldiaResultado apps 'Ejemplo.App' actualizado 0 '' '1.0' '2.0'
                $win = New-AldiaResultado windows 'update-id' actualizado 2 'KB123456' -Titulo 'Security Intelligence'
                Show-AldiaDetalleHistorialGui @((Get-AldiaPlanDeshacer $app -Demo),(Get-AldiaPlanDeshacer $win -Demo))
                $c.DetalleHistorial.Items[0].Disponible | Should Be $true
                $c.DetalleHistorial.Items[1].Disponible | Should Be $false
                $c.DetalleHistorial.Items[1].Motivo | Should Match 'inteligencia de seguridad'
                Show-AldiaFijadosGui @(@{ fuente='apps'; id='Ejemplo.App'; version='1.0' })
                $c.Fijados.Children[0].Child.Children[0].Content | Should Be 'Dejar de fijar'
            } finally { $ventana.Close(); $script:AldiaGui = $null }
        }
    }
}