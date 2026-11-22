$script:raizPruebas = Split-Path $PSScriptRoot
$script:fixtures = Join-Path $PSScriptRoot 'fixtures'
Import-Module (Join-Path $script:raizPruebas 'Aldia.psd1') -Force

Describe 'Proceso elevado' {
    It 'cachea el handle elevado antes de esperar y leer el código de salida' {
        InModuleScope Aldia {
            Mock Start-Process {
                $p = [pscustomobject]@{ HandleConsultado=$false }
                $p | Add-Member ScriptProperty Handle { $this.HandleConsultado = $true; [IntPtr]1 }
                $p | Add-Member ScriptMethod WaitForExit {
                    param($Milisegundos)
                    if (!$this.HandleConsultado) { throw 'Handle sin cachear' }
                    $true
                }
                $p | Add-Member ScriptProperty ExitCode { if ($this.HandleConsultado) { 37 } }
                $p | Add-Member ScriptMethod Dispose {}
                $p
            }
            $r = Invoke-AldiaComando powershell.exe @('-NoProfile') -Elevar
            $r.Codigo | Should Be 37
            $r.Timeout | Should Be $false
        }
    }
}

Describe 'Parser de winget' {
    BeforeAll {
        $script:raizPruebas = Split-Path $PSScriptRoot
        $script:fixtures = Join-Path $PSScriptRoot 'fixtures'
        . (Join-Path $script:raizPruebas 'src/Registro.ps1')
        . (Join-Path $script:raizPruebas 'src/Winget.ps1')
        . (Join-Path $script:raizPruebas 'src/Deshacer.ps1')
        function Read-FixtureWinget($Nombre) {
            ConvertFrom-AldiaWinget (Get-Content -LiteralPath (Join-Path $script:fixtures "winget-upgrade-$Nombre.txt") -Raw -Encoding UTF8)
        }
    }
    It 'lee las 20 filas reales, incluidas las desalineadas y msstore' {
        $items = @(Read-FixtureWinget en)
        $items.Count | Should Be 20
        ($items | Where-Object Id -eq 'Microsoft.VCRedist.2015+.x64').Disponible | Should BeExactly '14.52.37029.0'
        ($items | Where-Object Id -eq 'XP8K17RNMM8MTN').Origen | Should BeExactly 'msstore'
    }
    It 'lee los encabezados y caracteres en español' {
        $r = Read-FixtureWinget es
        $r.Nombre | Should BeExactly 'Aplicación Ñ'
        $r.VersionDesconocida | Should Be $true
    }
    It 'ignora el progreso y las actualizaciones de la misma línea' {
        (Read-FixtureWinget progress).Id | Should BeExactly 'Publisher.App'
    }
    It 'recupera un nombre truncado con caracteres anchos' {
        $r = Read-FixtureWinget truncated
        $r.Nombre | Should BeExactly '工具程序…'
        $r.Id | Should BeExactly 'Example.Publisher'
    }
    It 'conserva la versión con límite inferior' {
        $r = Read-FixtureWinget unknown
        $r.Version | Should BeExactly '< 3.10.8'
        $r.VersionDesconocida | Should Be $true
    }
    It 'informa por separado los paquetes fijados' {
        $r = @(Read-FixtureWinget pinned)
        $r.Count | Should Be 2
        $r[0].Explicito | Should Be $false
        $r[1].Explicito | Should Be $true
    }
    It 'acepta una salida sin resultados en ambos idiomas' {
        @(Read-FixtureWinget empty-en).Count | Should Be 0
        @(Read-FixtureWinget empty-es).Count | Should Be 0
    }
    It 'interpreta los códigos de winget usando hexadecimal sin signo' {
        (ConvertTo-AldiaEstadoWinget 0).Estado | Should Be actualizado
        (ConvertTo-AldiaEstadoWinget 0x8A15002B).Estado | Should Be no-aplicable
        foreach ($hex in '8A150109','8A15010A') {
            $r = ConvertTo-AldiaEstadoWinget ([Convert]::ToInt32($hex,16))
            $r.Codigo | Should BeExactly "0x$hex"
            $r.RequiereReinicio | Should Be $true
        }
        foreach ($hex in '8A150101','8A150103') {
            (ConvertTo-AldiaEstadoWinget ([Convert]::ToInt32($hex,16))).Mensaje | Should BeExactly 'La aplicación está abierta; ciérrala.'
        }
        (ConvertTo-AldiaEstadoWinget 0x8A150107).Mensaje | Should BeExactly 'Sin red.'
        (ConvertTo-AldiaEstadoWinget 7).Estado | Should Be fallo
        (ConvertTo-AldiaEstadoWinget -Timeout).Estado | Should Be timeout
    }
    It 'deja AppInstaller al final y excluye paquetes configurados y fijados' {
        $items = @(Read-FixtureWinget en) + @(Read-FixtureWinget pinned)
        $orden = @(Get-AldiaOrdenApps $items @{ excluir = @('GitHub.cli'); incluirVersionDesconocida = $true })
        $orden[-1].Id | Should BeExactly 'Microsoft.AppInstaller'
        ($orden.Id -contains 'GitHub.cli') | Should Be $false
        ($orden.Id -contains 'Example.Pinned') | Should Be $false
    }
}

Describe 'Configuración' {
    It 'carga valores por defecto cuando falta el archivo' {
        InModuleScope Aldia {
            $r = Get-AldiaConfig
            $r.horaDiaria | Should BeExactly '12:00'
            $r.fuentes.drivers | Should Be $true
        }
    }
    It 'conserva datos válidos, completa claves y avisa de tipos inválidos' {
        InModuleScope Aldia {
            Mock Test-Path { $true }
            Mock Get-Content { '{"fuentes":{"npm":false},"bateriaMinima":"10","adicional":false}' } -ParameterFilter { $LiteralPath -like '*config.json' }
            Mock Write-AldiaLog {}
            $r = Get-AldiaConfig (Join-Path (Get-Location) 'config.json')
            $r.fuentes.npm | Should Be $false
            $r.fuentes.apps | Should Be $true
            $r.bateriaMinima | Should Be 50
            Assert-MockCalled Write-AldiaLog -Times 2 -Exactly -Scope It
        }
    }
}

Describe 'Ejecución' {
    It 'omite con códigos 0 y 1 dentro de las 20 h y respeta el límite' {
        InModuleScope Aldia {
            Mock Get-AldiaBateria { @{ EnBateria = $false; Carga = 10 } }
            $ahora = [datetime]'2026-11-22 12:00'
            $h = @(@{ Modo = 'interactivo'; Codigo = 0; Fin = $ahora.AddHours(-19) })
            foreach ($codigo in 0,1) {
                $h[0].Codigo = $codigo
                (Get-AldiaMotivoOmision @{ bateriaMinima = 50 } $h -Ahora $ahora) | Should Match '20 horas'
            }
            foreach ($codigo in 2,3,$null) {
                $h[0].Codigo = $codigo
                @(Get-AldiaMotivoOmision @{ bateriaMinima = 50 } $h -Ahora $ahora).Count | Should Be 0
            }
            $h[0].Codigo = 1
            @(Get-AldiaMotivoOmision @{ bateriaMinima = 50 } $h -Ahora $ahora -Forzar).Count | Should Be 0
            $h[0].Fin = $ahora.AddHours(-20)
            @(Get-AldiaMotivoOmision @{ bateriaMinima = 50 } $h -Ahora $ahora).Count | Should Be 0
        }
    }
    It 'omite con batería baja incluso con forzar y acepta el umbral exacto' {
        InModuleScope Aldia {
            Mock Get-AldiaBateria { @{ EnBateria = $true; Carga = 49 } }
            (Get-AldiaMotivoOmision @{ bateriaMinima = 50 } @() -Forzar) | Should Match 'Batería'
            @(Get-AldiaMotivoOmision @{ bateriaMinima = 49 } @()).Count | Should Be 0
        }
    }
    It 'encuentra tres fallos consecutivos y corta la racha al faltar el elemento' {
        InModuleScope Aldia {
            $r = New-AldiaResultado apps 'Demo.App' fallo 7 '' -Titulo 'Demo'
            $h = @(@{ Resultados = @($r) }, @{ Resultados = @($r) })
            (Get-AldiaFallosRepetidos $h @($r)) | Should BeExactly 'Demo'
            $h[1].Resultados = @()
            @(Get-AldiaFallosRepetidos $h @($r)).Count | Should Be 0
        }
    }
    It 'consulta las cuatro fuentes y solo muestra las operaciones de escritura' {
        InModuleScope Aldia {
            Mock Get-Command { @{ Source = 'winget.exe' } } -ParameterFilter { $Name -eq 'winget.exe' }
            Mock Get-AldiaNpmEjecutable { 'npm.cmd' }
            Mock Invoke-AldiaComando {
                if ($Simular) { return @{ Codigo=0; Timeout=$false } }
                switch ($Argumentos[0]) {
                    'upgrade' {
                        if ($Argumentos -contains '--id') { throw 'Actualización real' }
                        $fixture = Join-Path (Get-Module Aldia).ModuleBase 'tests/fixtures/winget-upgrade-es.txt'
                        return @{ Codigo=0; Timeout=$false; Salida=(Get-Content $fixture -Raw -Encoding UTF8) }
                    }
                    'outdated' { return @{ Codigo=1; Timeout=$false; Salida='{"@example/tool":{"current":"1","latest":"2"}}' } }
                    default { throw 'Operación real' }
                }
            }
            Mock New-AldiaSesionWU { @{} }
            Mock Find-AldiaActualizacionesWU {
                $u = [pscustomobject]@{ Title=$Tipo; Identity=@{ UpdateID="demo-$Tipo" }; EulaAccepted=$false }
                $u | Add-Member -MemberType ScriptMethod -Name AcceptEula -Value { throw 'EULA real' } -PassThru
            }
            Mock New-AldiaColeccionWU { throw 'Colección COM real' }
            Mock Invoke-AldiaDescargaWU { throw 'Descarga real' }
            Mock Invoke-AldiaInstalacionWU { throw 'Instalación real' }
            Mock Get-AldiaProblemasPnP { @{ Nombre='Demo'; HardwareID='PCI\DEMO'; Codigo=28 } }
            Mock Get-AldiaDell { 'C:\Program Files\Dell\dcu-cli.exe' }
            Mock Checkpoint-Computer { throw 'Punto real' }
            Mock Read-AldiaHistorial { throw 'Lectura de historial' }
            Mock Add-AldiaHistorial { throw 'Historial real' }
            Mock Send-AldiaToast { throw 'Notificación real' }
            Mock Get-AldiaConfig {
                @{ puntoRestauracion=$true; incluirVersionDesconocida=$true; timeoutMinutosPorPaquete=1
                   fuentes=@{ apps=$true; windows=$true; drivers=$true; npm=$true }
                   drivers=@{ rescanearDispositivos=$true; excluirClases=@() } }
            }
            Mock Write-Host {}
            Mock Test-AldiaInternet { $true }
            Mock Get-AldiaEstadoWinget { @{ Estado='ok' } }
            Mock Test-AldiaDiscoBajo { $false }
            Mock Update-AldiaOffice {}
            Mock Update-AldiaStore {}
            Invoke-AldiaCli @('actualizar','--simular') | Should Be 0
            Assert-MockCalled Invoke-AldiaComando -Times 2 -Exactly -Scope It -ParameterFilter { !$Simular }
            Assert-MockCalled Invoke-AldiaComando -Times 1 -Exactly -Scope It -ParameterFilter { $Simular -and $Argumentos -contains '--id' }
            Assert-MockCalled Invoke-AldiaComando -Times 1 -Exactly -Scope It -ParameterFilter { $Simular -and $Argumentos -contains '@example/tool@latest' }
            Assert-MockCalled Invoke-AldiaComando -Times 1 -Exactly -Scope It -ParameterFilter { $Simular -and $Argumentos -contains '/applyUpdates' }
            Assert-MockCalled Invoke-AldiaComando -Times 1 -Exactly -Scope It -ParameterFilter { $Simular -and $Argumentos -contains '/scan-devices' }
            Assert-MockCalled Find-AldiaActualizacionesWU -Times 1 -Exactly -Scope It -ParameterFilter { $Tipo -eq 'Software' }
            Assert-MockCalled Find-AldiaActualizacionesWU -Times 1 -Exactly -Scope It -ParameterFilter { $Tipo -eq 'Driver' }
            Assert-MockCalled Get-AldiaProblemasPnP -Times 1 -Exactly -Scope It
            foreach ($nombre in 'Checkpoint-Computer','New-AldiaColeccionWU','Invoke-AldiaDescargaWU','Invoke-AldiaInstalacionWU','Read-AldiaHistorial','Add-AldiaHistorial','Send-AldiaToast') {
                Assert-MockCalled $nombre -Times 0 -Exactly -Scope It
            }
            Assert-MockCalled Write-Host -Times 1 -Exactly -Scope It -ParameterFilter { $Object -eq 'Se actualizarían 5 elementos' }
        }
    }
    It 'relanza con pausa y devuelve el código del proceso elevado' {
        InModuleScope Aldia {
            Mock Test-AldiaAdmin { $false }
            Mock Invoke-AldiaComando { @{ Codigo=1; Timeout=$false } }
            Mock Read-Host {}
            Invoke-AldiaCli @('actualizar','--solo','apps') 'D:\Rutas con espacios\aldia.ps1' | Should Be 1
            Assert-MockCalled Invoke-AldiaComando -Times 1 -Exactly -Scope It -ParameterFilter {
                $Elevar -and ($Argumentos -join '|') -like '*|-File|D:\Rutas con espacios\aldia.ps1|actualizar|--solo|apps|--pausar'
            }
            Assert-MockCalled Read-Host -Times 0 -Exactly -Scope It
        }
    }
    It 'pausa tras obtener el resultado en la consola hija' {
        InModuleScope Aldia {
            Mock Test-AldiaAdmin { $true }
            Mock Assert-AldiaRutaNormal {}
            Mock Get-AldiaConfig { @{ fuentes=@{ apps=$true } } }
            Mock Invoke-AldiaActualizacion { 1 }
            Mock Read-Host { 'Enter' }
            Mock Test-AldiaInternet { $true }
            Mock Get-AldiaEstadoWinget { @{ Estado='ok' } }
            Invoke-AldiaCli @('actualizar','--pausar') | Should Be 1
            Assert-MockCalled Read-Host -Times 1 -Exactly -Scope It -ParameterFilter { $Prompt -eq 'Pulsa Enter para cerrar' }
        }
    }
    It 'conserva las columnas de apps, trunca con puntos suspensivos y muestra los totales' {
        InModuleScope Aldia {
            Mock Get-AldiaApps {
                [pscustomobject]@{ Nombre=('A'*90); Id='Demo.App'; Version='1'; Disponible='2'; Origen='winget' }
            }
            Mock Get-AldiaNpm {}
            Mock Write-Host {}
            Invoke-AldiaRevision @{} @('apps','npm') | Should Be 0
            Assert-MockCalled Write-Host -Times 1 -Exactly -Scope It -ParameterFilter {
                $Object -match '^Nombre\s+Id\s+Versión\s+Disponible\s+Origen$'
            }
            Assert-MockCalled Write-Host -Times 1 -Exactly -Scope It -ParameterFilter {
                $Object -match '^A{1,39}…\s+Demo\.App\s+1\s+2\s+winget$'
            }
            Assert-MockCalled Write-Host -Times 1 -Exactly -Scope It -ParameterFilter {
                $Object -eq 'Totales por fuente: apps=1 · npm=0'
            }
        }
    }
    It 'conserva solo los Id ARP clásicos tal como aparecen, sin avisos por fila' {
        InModuleScope Aldia {
            Mock Write-AldiaLog {}
            $fixture = Join-Path (Get-Module Aldia).ModuleBase 'tests/fixtures/winget-list.txt'
            $items = @(ConvertFrom-AldiaWinget (Get-Content $fixture -Raw -Encoding UTF8) -Inventario)
            $items.Count | Should Be 2
            $items[0].Id | Should BeExactly 'ARP\Machine\X64\{12345678}'
            $items[1].Id | Should BeExactly 'ARP\User\X64\Utilidad con espacios'
            $items[1].Version | Should BeExactly '2.0'
            Assert-MockCalled Write-AldiaLog -Times 0 -Exactly -Scope It
        }
    }
}

Describe 'Drivers y npm' {
    It 'traduce códigos de dispositivos y distingue incidencias' {
        InModuleScope Aldia {
            Mock Get-CimInstance {
                foreach ($codigo in 28,22,45,0) {
                    [pscustomobject]@{ Name='Demo'; ConfigManagerErrorCode=$codigo; HardwareID=@('PCI\DEMO','otro') }
                }
            }
            $r = @(Get-AldiaProblemasPnP)
            $r.Count | Should Be 3
            $r[0].Mensaje | Should BeExactly 'no tiene driver instalado'
            $r[0].HardwareID | Should BeExactly 'PCI\DEMO'
            $r[1].Problema | Should Be $false
            $r[2].Problema | Should Be $false
        }
    }
    It 'filtra las clases excluidas de Windows Update' {
        InModuleScope Aldia {
            Mock Find-AldiaActualizacionesWU {
                [pscustomobject]@{ DriverClass = 'Display' }
                [pscustomobject]@{ DriverClass = 'Net' }
            }
            $r = @(Get-AldiaDriversWU $null @{ drivers = @{ excluirClases = @('display') } })
            $r.Count | Should Be 1
            $r[0].DriverClass | Should BeExactly 'Net'
        }
    }
    It 'recomienda por equipo y GPU e ignora los adaptadores virtuales' {
        InModuleScope Aldia {
            Mock Get-CimInstance { [pscustomobject]@{ Manufacturer = 'LENOVO' } } -ParameterFilter { $ClassName -eq 'Win32_ComputerSystem' }
            Mock Get-CimInstance {
                foreach ($nombre in 'NVIDIA GeForce','AMD Virtual','Microsoft Basic','Intel Remote','Meta Virtual') {
                    [pscustomobject]@{ Name = $nombre; DriverDate = [datetime]'2024-01-01' }
                }
            } -ParameterFilter { $ClassName -eq 'Win32_VideoController' }
            Mock Invoke-AldiaComando { throw 'winget real' }
            Mock Get-ItemProperty {
                [pscustomobject]@{ DisplayName='Lenovo System Update'; DisplayVersion='5.1' }
                [pscustomobject]@{ DisplayName='NVIDIA App Helper'; DisplayVersion='99' }
                [pscustomobject]@{ DisplayName='NVIDIA App 11.0'; DisplayVersion='11.0' }
            }
            $gpu = @(Get-AldiaGpu)
            $gpu.Count | Should Be 1
            $r = @(Get-AldiaRecomendaciones $gpu)
            ($r.Herramienta -join ', ') | Should BeExactly 'Lenovo System Update, NVIDIA App'
            ($r.Version -join ', ') | Should BeExactly '5.1, 11.0'
            $r[1].ComoConseguirla | Should BeExactly 'winget install --id XP8CLZL93F5Z4P --exact'
            $amd = Get-AldiaRecomendaciones @(@{ Name='AMD Radeon' }) | Where-Object Herramienta -eq 'AMD Software Adrenalin'
            $amd.Instalado | Should BeExactly 'no'
            $amd.ComoConseguirla | Should Match '^https://www\.amd\.com/'
            Assert-MockCalled Get-ItemProperty -Times 2 -Exactly -Scope It -ParameterFilter {
                $Path.Count -eq 3 -and ($Path -like 'HKLM:\*\WOW6432Node\*') -and ($Path -like 'HKCU:\*')
            }
            Assert-MockCalled Invoke-AldiaComando -Times 0 -Exactly -Scope It
            @(Get-AldiaGpuAntiguas $gpu -Ahora ([datetime]'2026-11-22')).Count | Should Be 1
        }
    }
    It 'lee el JSON de npm con código 1' {
        InModuleScope Aldia {
            Mock Invoke-AldiaComando {
                $modulo = Get-Module Aldia
                @{ Codigo=1; Timeout=$false; Salida=(Get-Content -LiteralPath (Join-Path $modulo.ModuleBase 'tests/fixtures/npm-outdated.json') -Raw -Encoding UTF8) }
            }
            $r = @(Get-AldiaNpm 'npm.cmd')
            $r.Count | Should Be 2
            $r[1].Id | Should BeExactly '@example/tool'
        }
    }
}
