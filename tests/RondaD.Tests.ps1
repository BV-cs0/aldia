Import-Module (Join-Path (Split-Path $PSScriptRoot) 'Aldia.psd1') -Force
& (Get-Module Aldia) { param($Xml) $script:AldiaXmlRondaD = $Xml } (Get-Content -LiteralPath (Join-Path $PSScriptRoot 'fixtures\battery-ronda-d.xml') -Raw)

Describe 'Ronda D: diagnóstico en distintos equipos' {
    InModuleScope Aldia {
        Context 'atribuye la predicción SATA solo al HDD con el PnP exacto y enlaza su unidad' {
            BeforeEach {
                Mock Test-AldiaAdmin { $false }
                Mock Get-AldiaDiscosFisicos {}
                Mock Get-AldiaDiscosWindows {}
                Mock Get-CimInstance {}
                Mock Get-AldiaContadoresDisco {}
                Mock Get-AldiaParticionesDisco {}
                Mock Get-AldiaVolumenDisco {}
            }

            It 'comprueba el resultado' {
                Mock Test-AldiaAdmin { $true }
                Mock Get-AldiaDiscosFisicos {
                    @{ FriendlyName='HDD 1'; MediaType='HDD'; BusType='SATA'; UniqueId='a'; HealthStatus='Healthy'; OperationalStatus='OK' }
                    @{ FriendlyName='HDD 2'; MediaType='HDD'; BusType='SATA'; UniqueId='b'; HealthStatus='Healthy'; OperationalStatus='OK' }
                }
                Mock Get-AldiaDiscosWindows { @{ UniqueId='a'; Number=3 }; @{ UniqueId='b'; Number=4 } }
                Mock Get-AldiaParticionesDisco { @{ DriveLetter='F' } } -ParameterFilter { $Numero -eq 3 }
                Mock Get-AldiaVolumenDisco { @{ SizeRemaining=20GB } }
                Mock Get-CimInstance {
                    @{ Index=3; PNPDeviceID='IDE\DISK\A&1' }; @{ Index=4; PNPDeviceID='IDE\DISK\A&10' }
                } -ParameterFilter { $ClassName -eq 'Win32_DiskDrive' }
                Mock Get-CimInstance { @{ InstanceName='IDE\DISK\A&1_0'; PredictFailure=$true } } -ParameterFilter { $ClassName -eq 'MSStorageDriver_FailurePredictStatus' }
                $d = @(Get-AldiaDiscos)
                $d[0].Tipo | Should Be 'Disco duro'
                $d[0].Estado | Should Be 'mal'
                ($null -eq $d[0].Vida) | Should Be $true
                $d[0].Unidades[0].Letra | Should Be 'F'
                $d[0].Unidades[0].Libre | Should Be 20GB
                $d[1].Estado | Should Be 'bien'
            }
        }

        Context 'reconoce NVMe, eMMC y la velocidad de giro cuando Windows 10 no da el tipo' {
            BeforeEach {
                Mock Test-AldiaAdmin { $false }
                Mock Get-AldiaDiscosFisicos {}
                Mock Get-AldiaDiscosWindows {}
                Mock Get-CimInstance {}
                Mock Get-AldiaContadoresDisco {}
                Mock Get-AldiaParticionesDisco {}
                Mock Get-AldiaVolumenDisco {}
            }

            It 'comprueba el resultado' {
                Mock Get-AldiaDiscosFisicos {
                    @{ MediaType='Unspecified'; BusType='NVMe' }
                    @{ MediaType=0; BusType=13 }
                    @{ MediaType='Unspecified'; BusType='SD' }
                    @{ MediaType='Unspecified'; BusType='SATA'; SpindleSpeed=0 }
                    @{ MediaType='Unspecified'; BusType='SATA'; SpindleSpeed=5400 }
                    @{ MediaType='Unspecified'; BusType='SATA' }
                }
                ((Get-AldiaDiscos).Tipo -join '|') | Should Be 'SSD NVMe|Memoria interna (eMMC)|Memoria interna (eMMC)|SSD SATA|Disco duro|Disco'
            }
        }

        Context 'deja en desconocido RAID, Intel RST y Storage Spaces sin contadores' {
            BeforeEach {
                Mock Test-AldiaAdmin { $false }
                Mock Get-AldiaDiscosFisicos {}
                Mock Get-AldiaDiscosWindows {}
                Mock Get-CimInstance {}
                Mock Get-AldiaContadoresDisco {}
                Mock Get-AldiaParticionesDisco {}
                Mock Get-AldiaVolumenDisco {}
            }

            It 'comprueba el resultado' {
                Mock Test-AldiaAdmin { $true }
                Mock Get-AldiaDiscosFisicos {
                    @{ FriendlyName='Controlador'; BusType='RAID'; HealthStatus='Warning' }
                    @{ FriendlyName='Intel RST'; HealthStatus='Healthy' }
                    @{ FriendlyName='Unidad'; BusType='Spaces'; HealthStatus='Healthy' }
                }
                Mock Get-AldiaContadoresDisco { throw 'Acceso denegado' }
                $d = @(Get-AldiaDiscos)
                ($d.Estado -join '|') | Should Be 'desconocido|desconocido|desconocido'
                $d[0].Detalle | Should Match 'controlador RAID'
            }
        }

        Context 'muestra USB sin penalizar la falta de contadores y nunca los solicita sin permiso' {
            BeforeEach {
                Mock Test-AldiaAdmin { $false }
                Mock Get-AldiaDiscosFisicos {}
                Mock Get-AldiaDiscosWindows {}
                Mock Get-CimInstance {}
                Mock Get-AldiaContadoresDisco {}
                Mock Get-AldiaParticionesDisco {}
                Mock Get-AldiaVolumenDisco {}
            }

            It 'comprueba el resultado' {
                Mock Get-AldiaDiscosFisicos { @{ FriendlyName='Externo'; BusType='USB'; HealthStatus='Healthy'; OperationalStatus='OK' } }
                $d = Get-AldiaDiscos
                $d.Nombre | Should Be 'Externo (USB)'
                $d.Estado | Should Be 'bien'
                Assert-MockCalled Get-AldiaContadoresDisco -Times 0 -Exactly -Scope It
            }
        }

        Context 'aplica los límites de temperatura, desgaste, salud y errores' {
            BeforeEach {
                Mock Test-AldiaAdmin { $false }
                Mock Get-AldiaDiscosFisicos {}
                Mock Get-AldiaDiscosWindows {}
                Mock Get-CimInstance {}
                Mock Get-AldiaContadoresDisco {}
                Mock Get-AldiaParticionesDisco {}
                Mock Get-AldiaVolumenDisco {}
            }

            It 'comprueba el resultado' {
                (Get-AldiaEstadoDisco Healthy OK $false 0 10 30 'SSD SATA')[0] | Should Be mal
                (Get-AldiaEstadoDisco Healthy OK $false 1 $null 30 'Disco duro')[0] | Should Be mal
                (Get-AldiaEstadoDisco Unhealthy OK $false 0 $null $null Disco)[0] | Should Be mal
                (Get-AldiaEstadoDisco Healthy OK $false 0 30 39 'SSD SATA')[0] | Should Be aviso
                (Get-AldiaEstadoDisco Healthy OK $false 0 100 70 'SSD SATA')[0] | Should Be aviso
                (Get-AldiaEstadoDisco Healthy OK $false 0 $null 55 'Disco duro')[0] | Should Be aviso
                (Get-AldiaEstadoDisco Warning OK $false 0 $null $null Disco)[0] | Should Be aviso
                (Get-AldiaEstadoDisco Healthy Degraded $false 0 $null $null Disco)[0] | Should Be aviso
                (Get-AldiaEstadoDisco Healthy OK $false 0 $null 54 'Disco duro')[0] | Should Be bien
            }
        }

        Context 'carga los datos guardados y etiqueta los de más de siete días' {
            BeforeEach {
                Mock Test-AldiaAdmin { $false }
                Mock Get-AldiaDiscosFisicos {}
                Mock Get-AldiaDiscosWindows {}
                Mock Get-CimInstance {}
                Mock Get-AldiaContadoresDisco {}
                Mock Get-AldiaParticionesDisco {}
                Mock Get-AldiaVolumenDisco {}
            }

            It 'comprueba el resultado' {
                $ruta = Join-Path (Get-PSDrive TestDrive).Root 'hardware.json'
                [IO.File]::WriteAllText($ruta,'{"Version":1,"Fecha":"2026-11-15T12:00:00Z","Discos":[{"Id":"a","Vida":23}]}')
                $hora = [datetime]::Parse('2026-11-23T12:00:00Z')
                (Get-AldiaCacheHardware $ruta $hora).Antiguo | Should Be $true
                $c = Get-AldiaCacheHardware $ruta $hora.AddDays(-7)
                $c.Antiguo | Should Be $false
                Mock Get-AldiaDiscosFisicos { @{ UniqueId='a'; BusType='NVMe'; HealthStatus='Healthy' } }
                (Get-AldiaDiscos $c).Vida | Should Be 23
                [IO.File]::WriteAllText($ruta,'{')
                (Get-AldiaCacheHardware $ruta $hora) | Should BeNullOrEmpty
            }
        }

        Context 'solo muestra estabilidad en una máquina virtual' {
            It 'comprueba el resultado' {
                Mock Test-AldiaMaquinaVirtual { $true }
                Mock Get-AldiaEstabilidad { @{ Estado='bien'; Detalle='Sin incidencias' } }
                Mock Get-AldiaDiscos {}
                Mock Get-AldiaBateriaSalud {}
                Mock Get-AldiaMemoriaHardware {}
                $r = Get-AldiaHardware
                $r.Virtual | Should Be $true
                $r.Estabilidad.Estado | Should Be bien
                Assert-MockCalled Get-AldiaDiscos -Times 0 -Exactly -Scope It
                Assert-MockCalled Get-AldiaBateriaSalud -Times 0 -Exactly -Scope It
                Assert-MockCalled Get-AldiaMemoriaHardware -Times 0 -Exactly -Scope It
            }
        }

        Context 'no llama a powercfg en un sobremesa' {
            It 'comprueba el resultado' {
                Mock Get-CimInstance {}
                Mock Invoke-AldiaComando {}
                (Get-AldiaBateriaSalud) | Should BeNullOrEmpty
                Assert-MockCalled Invoke-AldiaComando -Times 0 -Exactly -Scope It
            }
        }

        Context 'lee dos paquetes y una capacidad vacía con números de varios idiomas' {
            It 'comprueba el resultado' {
                Mock Get-CimInstance { @{ Name='Principal' }; @{ Name='Secundaria' } }
                Mock Invoke-AldiaComando {
                    [IO.File]::WriteAllText($Argumentos[-1],$script:AldiaXmlRondaD)
                    @{ Codigo=0; Timeout=$false }
                }
                $b = @(Get-AldiaBateriaSalud)
                $b.Count | Should Be 3
                $b[0].Salud | Should Be 72
                $b[0].Estado | Should Be aviso
                $b[0].Ciclos | Should Be 301
                $b[0].Quimica | Should Be 'Litio'
                $b[1].Estado | Should Be desconocido
                $b[2].Estado | Should Be desconocido
            }
        }

        Context 'clasifica baterías justo en los límites del 80 y 60 por ciento' {
            It 'comprueba el resultado' {
                foreach ($caso in @(@(80,'bien'),@(79,'aviso'),@(60,'aviso'),@(59,'mal'))) {
                    $xml = [xml]("<Batteries><Battery><DesignCapacity>100</DesignCapacity><FullChargeCapacity>{0}</FullChargeCapacity></Battery></Batteries>" -f $caso[0])
                    (ConvertFrom-AldiaBateriaXml $xml).Estado | Should Be $caso[1]
                }
            }
        }

        Context 'usa fechas e identificadores estables y distingue los apagados aislados' {
            It 'comprueba el resultado' {
                Mock Get-WinEvent {}
                Mock Get-WinEvent { @{ TimeCreated=[datetime]'2026-11-22' } } -ParameterFilter { $FilterHashtable.Id -eq 41 }
                $ahora = [datetime]'2026-11-23'
                $r = Get-AldiaEstabilidad $ahora
                $r.Estado | Should Be bien
                $r.Detalle | Should Match '1 apagado inesperado'
                Assert-MockCalled Get-WinEvent -Times 1 -Scope It -ParameterFilter {
                    $FilterHashtable.StartTime -eq [datetime]'2026-10-24' -and $FilterHashtable.ProviderName -eq 'Microsoft-Windows-Kernel-Power'
                }
                Mock Get-WinEvent { @{ TimeCreated=[datetime]'2026-11-21' } } -ParameterFilter { $FilterHashtable.ProviderName -eq 'Microsoft-Windows-WHEA-Logger' }
                (Get-AldiaEstabilidad $ahora).Estado | Should Be aviso
                Mock Get-WinEvent { @{ TimeCreated=[datetime]'2026-11-23' } } -ParameterFilter { $FilterHashtable.Id -eq 1001 -and $FilterHashtable.ProviderName -eq 'Microsoft-Windows-WER-SystemErrorReporting' }
                (Get-AldiaEstabilidad $ahora).Pantallazos | Should Be 1
            }
        }

        Context 'muestra la memoria por módulos sin marcar una velocidad menor en rojo' {
            It 'comprueba el resultado' {
                Mock Get-CimInstance { @{Capacity=8GB; ConfiguredClockSpeed=5200; Speed=5600}; @{Capacity=8GB; ConfiguredClockSpeed=5200; Speed=5600} }
                $r = Get-AldiaMemoriaHardware
                $r.Detalle | Should Match '2 módulos'
                $r.Detalle | Should Match '5200 de 5600'
                $r.Estado | Should BeNullOrEmpty
            }
        }

        Context 'mide en TestDrive, elimina su archivo y omite la comparación para tipo desconocido' {
            BeforeEach {
                Mock Get-AldiaBateria { @{ EnBateria=$false; Carga=100 } }
                Mock Get-AldiaVolumenDisco { @{ SizeRemaining=4GB } }
                Mock Get-AldiaRutasVelocidad { (Get-PSDrive TestDrive).Root }
            }

            It 'comprueba el resultado' {
                $h = @{ Discos=@(@{ Tipo='Disco'; Unidades=@(@{ Letra='T' }) }) }
                $r = Test-AldiaVelocidadDisco T -Tamano 2MB -Hardware $h
                ($r.Escritura -gt 0 -and $r.Lectura -gt 0) | Should Be $true
                $r.Detalle | Should Not Match 'normal'
                @(Get-ChildItem TestDrive:\ -Filter 'aldia-velocidad-*.tmp').Count | Should Be 0
            }
        }

        Context 'usa la carpeta temporal de la misma unidad cuando una cuenta estándar no puede escribir en la raíz' {
            BeforeEach {
                Mock Get-AldiaBateria { @{ EnBateria=$false; Carga=100 } }
                Mock Get-AldiaVolumenDisco { @{ SizeRemaining=4GB } }
                Mock Get-AldiaRutasVelocidad { (Get-PSDrive TestDrive).Root }
            }

            It 'comprueba el resultado' {
                Mock Test-AldiaAdmin { $false }
                Mock Get-AldiaRutasVelocidad { Join-Path (Get-PSDrive TestDrive).Root 'raiz-sin-permiso'; (Get-PSDrive TestDrive).Root }
                $r = Test-AldiaVelocidadDisco C -Tamano 1MB
                ($r.Lectura -gt 0) | Should Be $true
                @(Get-ChildItem TestDrive:\ -Filter 'aldia-velocidad-*.tmp').Count | Should Be 0
            }
        }

        Context 'respeta los 3 GB incluso cuando hay BitLocker y tampoco mide con poca batería' {
            BeforeEach {
                Mock Get-AldiaBateria { @{ EnBateria=$false; Carga=100 } }
                Mock Get-AldiaVolumenDisco { @{ SizeRemaining=4GB } }
                Mock Get-AldiaRutasVelocidad { (Get-PSDrive TestDrive).Root }
            }

            It 'comprueba el resultado' {
                Mock Get-AldiaVolumenDisco { @{ SizeRemaining=2GB; ProtectionStatus=1 } }
                Mock Measure-AldiaVelocidadUnidad { throw 'No se debe abrir ningún archivo.' }
                { Test-AldiaVelocidadDisco C -Tamano 1MB } | Should Throw '3 GB libres'
                Mock Get-AldiaVolumenDisco { @{ SizeRemaining=4GB; ProtectionStatus=1 } }
                Mock Get-AldiaBateria { @{ EnBateria=$true; Carga=5 } }
                { Test-AldiaVelocidadDisco C -Tamano 1MB } | Should Throw 'Conecta el PC'
                Assert-MockCalled Measure-AldiaVelocidadUnidad -Times 0 -Exactly -Scope It
            }
        }

        Context 'elimina el archivo si se cancela la prueba' {
            BeforeEach {
                Mock Get-AldiaBateria { @{ EnBateria=$false; Carga=100 } }
                Mock Get-AldiaVolumenDisco { @{ SizeRemaining=4GB } }
                Mock Get-AldiaRutasVelocidad { (Get-PSDrive TestDrive).Root }
            }

            It 'comprueba el resultado' {
                { Test-AldiaVelocidadDisco T -Tamano 2MB -Control @{ Cancelar=$true } } | Should Throw 'Prueba cancelada'
                @(Get-ChildItem TestDrive:\ -Filter 'aldia-velocidad-*.tmp').Count | Should Be 0
            }
        }

        Context 'mantiene seis discos dentro de un panel con desplazamiento' {
            It 'comprueba el resultado' {
                Mock Get-AldiaDiscosFisicos { 1..6 | ForEach-Object { @{ FriendlyName="Disco $_"; HealthStatus='Healthy'; BusType='NVMe' } } }
                Mock Get-AldiaDiscosWindows {}
                Mock Test-AldiaAdmin { $false }
                $h = Get-AldiaHardwareDemo
                $h.Discos = @(Get-AldiaDiscos)
                $v = New-AldiaVentanaGui
                $panel = $v.FindName('TarjetasHardware')
                $panel.Parent.VerticalScrollBarVisibility | Should Be Auto
                $nombres = @{}
                foreach ($nombre in $script:AldiaNombresGui) { $nombres[$nombre] = $v.FindName($nombre) }
                $anterior = $script:AldiaGui
                try {
                    $script:AldiaGui = @{ Controles=$nombres; Demo=$true; Estado=@{} }
                    Show-AldiaHardwareGui $h
                    $panel.Children.Count | Should Be 9
                } finally { $script:AldiaGui = $anterior }
            }
        }

        Context 'escritura protegida y atómica de los detalles' {
            It 'reemplaza la copia anterior y borra su temporal' {
                Mock Test-AldiaAdmin { $true }
                Mock New-AldiaDirectorioProtegido {}
                Mock Assert-AldiaPermisos {}
                Mock Set-AldiaPropietarioAdmin {}
                Mock Get-AldiaDiscosFisicos { @{ UniqueId='a'; BusType='NVMe' } }
                Mock Get-AldiaDiscosWindows {}
                Mock Get-AldiaDetalleDiscos { @{ Id='a'; Vida=90 } }
                $ruta = Join-Path (Get-PSDrive TestDrive).Root 'hardware-protegido.json'
                [IO.File]::WriteAllText($ruta,'{}')
                Save-AldiaHardware $ruta
                (Get-AldiaCacheHardware $ruta).Discos[0].Vida | Should Be 90
                @(Get-ChildItem TestDrive:\ -Filter 'hardware-*.tmp').Count | Should Be 0
                Assert-MockCalled Assert-AldiaPermisos -Times 1 -Exactly -Scope It
            }
        }

        Context 'Ver detalles en una cuenta estándar' {
            It 'pide permiso con la orden interna y vuelve a cargar los datos' {
                Mock Test-AldiaAdmin { $false }
                Mock Assert-AldiaPermisos {}
                Mock Invoke-AldiaComando { @{ Codigo=0; Timeout=$false } }
                Mock Send-AldiaEventoGui {}
                Mock Get-AldiaHardware { @{ FechaDatos='Datos recientes' } }
                $estado = @{}
                Invoke-AldiaHardwareTrabajoGui detallesHardware $null $false @{} $estado
                $estado.HardwareInforme.FechaDatos | Should Be 'Datos recientes'
                Assert-MockCalled Invoke-AldiaComando -Times 1 -Exactly -Scope It -ParameterFilter {
                    $Elevar -and $Argumentos[-2] -eq 'diagnostico' -and $Argumentos[-1] -eq '--guardar'
                }
            }
        }

        Context 'guarda el hardware y la velocidad en el informe sin el número de serie' {
            It 'comprueba el resultado' {
                Mock Get-AldiaDireccionesPrivadas {}
                Mock Get-CimInstance {}
                $ruta = Join-Path (Get-PSDrive TestDrive).Root 'hardware.html'
                $h = Get-AldiaHardwareDemo
                $h.Discos[0].Nombre = 'SSD SERIAL-RONDA-D'
                $h.Discos[0] | Add-Member NoteProperty SerialNumber 'SERIAL-RONDA-D'
                $null = Save-AldiaInforme (Get-AldiaConfig) $ruta '' @{
                    Hardware=$h; Velocidad=@(@{ Detalle='C Lectura 1900 MB/s' })
                }
                $html = [IO.File]::ReadAllText($ruta)
                $html | Should Match '<h2>Hardware</h2>'
                $html | Should Match 'Lectura 1900 MB/s'
                $html | Should Not Match 'SERIAL-RONDA-D'
            }
        }
    }
}
