Import-Module (Join-Path (Split-Path $PSScriptRoot) 'Aldia.psd1') -Force

Describe 'Ronda C: revisión en otro PC' {
    InModuleScope Aldia {
        It 'detecta winget ausente y distingue el mínimo 1.6' {
            Mock Get-AldiaRutaWinget {}
            Mock Invoke-AldiaComando { throw 'No debe llamarse sin winget.' }
            (Get-AldiaEstadoWinget).Estado | Should Be 'ausente'
            Assert-MockCalled Invoke-AldiaComando -Times 0 -Exactly -Scope It
            Mock Get-AldiaRutaWinget { 'winget.exe' }
            Mock Invoke-AldiaComando { @{ Codigo=0; Salida='v1.5.2602' } }
            (Get-AldiaEstadoWinget).Estado | Should Be 'antiguo'
            Mock Invoke-AldiaComando { @{ Codigo=0; Salida='v1.6.0' } }
            (Get-AldiaEstadoWinget).Estado | Should Be 'ok'
        }

        It 'usa las opciones sin preguntas y reintenta el origen cuando falla Store' {
            Mock Write-AldiaLog {}
            Mock Invoke-AldiaComando {
                if ($Argumentos -contains 'msstore') { return @{ Codigo=[int]0x8A15000F } }
                @{ Codigo=0; Salida='OK' }
            }
            foreach ($orden in 'list','show','search','upgrade','install','--version') {
                (Invoke-AldiaWinget @($orden)).Codigo | Should Be 0
            }
            (Invoke-AldiaWinget @('list','--source','msstore')).Codigo | Should Be 0
            Assert-MockCalled Invoke-AldiaComando -Scope It -Times 8 -Exactly -ParameterFilter {
                $Ejecutable -eq 'winget.exe' -and $Argumentos -contains '--accept-source-agreements' -and
                $Argumentos -contains '--disable-interactivity'
            }
            Assert-MockCalled Invoke-AldiaComando -Scope It -Times 1 -Exactly -ParameterFilter { $Argumentos -contains 'winget' }
            Assert-MockCalled Write-AldiaLog -Scope It -Times 1 -Exactly
        }

        It 'centraliza las llamadas a winget y no consulta las fuentes sin conexión' {
            $raiz = Split-Path $PSScriptRoot
            $llamadas = @(Get-ChildItem (Join-Path $raiz 'src') -Filter '*.ps1' |
                Select-String -Pattern 'Invoke-AldiaComando\s+winget\.exe')
            foreach ($llamada in $llamadas) { $llamada.Filename | Should Be 'Requisitos.ps1' }
            Mock Invoke-WebRequest { throw 'Sin conexión.' }
            Mock Invoke-AldiaRevision { throw 'No debe buscar actualizaciones.' }
            Mock Get-AldiaEstadoWinget { throw 'No debe ejecutar winget.' }
            Mock Write-Host {}
            Invoke-AldiaCli @('revisar') 'prueba.ps1' | Should Be 3
            Assert-MockCalled Invoke-WebRequest -Scope It -Times 1 -Exactly -ParameterFilter { $Uri -like 'http://www.msftconnecttest.com/*' }
            Assert-MockCalled Invoke-WebRequest -Scope It -Times 1 -Exactly -ParameterFilter { $Uri -like 'https://www.microsoft.com/*' }
            Assert-MockCalled Invoke-AldiaRevision -Scope It -Times 0 -Exactly
        }

        It 'lee la marca de la placa, recomienda dos GPU y omite herramientas en una máquina virtual' {
            Mock Get-ItemProperty {}
            Mock Get-CimInstance {
                switch ($ClassName) {
                    Win32_ComputerSystem { @{ Manufacturer='System manufacturer'; Model='PC' } }
                    Win32_BaseBoard { @{ Manufacturer='ASRock' } }
                    Win32_Processor { @{ Manufacturer='AuthenticAMD' } }
                }
            }
            $gpu = @(@{ Name='Intel UHD' },@{ Name='NVIDIA GeForce' },@{ Name='NVIDIA GeForce' })
            $r = @(Get-AldiaRecomendaciones $gpu)
            @($r | Where-Object Herramienta -like 'ASRock*').Count | Should Be 1
            @($r | Where-Object Herramienta -like '*chipset AMD').Count | Should Be 1
            if ($env:PROCESSOR_ARCHITECTURE -ne 'ARM64' -and $env:PROCESSOR_ARCHITEW6432 -ne 'ARM64') {
                @($r | Where-Object Herramienta -like 'Intel*').Count | Should Be 1
                @($r | Where-Object Herramienta -eq 'NVIDIA App').Count | Should Be 1
            }
            Mock Get-CimInstance { @{ Manufacturer='Microsoft Corporation'; Model='Virtual Machine' } } -ParameterFilter { $ClassName -eq 'Win32_ComputerSystem' }
            $vm = @(Get-AldiaRecomendaciones $gpu)
            $vm.Count | Should Be 1
            $vm[0].Herramienta | Should Match 'Máquina virtual'
            @(Get-AldiaGpuAntiguas $gpu).Count | Should Be 0
        }

        It 'omite la Store sin administrador y simula sin llamar al método' {
            Mock Test-AldiaAdmin { $false }
            Mock Get-CimInstance { throw 'No se debe acceder al dispositivo.' }
            Mock Invoke-CimMethod { throw 'No se debe ejecutar el método.' }
            Mock Write-Host {}
            (Update-AldiaStore).Estado | Should Be 'omitido'
            (Update-AldiaStore -Simular).Estado | Should Be 'simulado'
            Assert-MockCalled Invoke-CimMethod -Scope It -Times 0 -Exactly
        }

        It 'guarda las fuentes nuevas y la clave desde los ajustes de la ventana' {
            $c = Get-AldiaConfig
            $c = Set-AldiaConfigGui $c @{
                Hora='10:00'; Activa=$true; ClaveNvd=' ejemplo '
                Fuentes=@{ apps=$true; windows=$true; drivers=$true; npm=$true; office=$false; store=$false }
            }
            $c.fuentes.office | Should Be $false
            $c.fuentes.store | Should Be $false
            $c.vulnerabilidades.nvdApiKey | Should Be 'ejemplo'
        }

        It 'registra una omisión con conexión medida antes de lanzar cambios' {
            $programado = $true
            Mock Get-AldiaCosteInternet { 'medido' }
            Mock Read-AldiaHistorial {}
            Mock Write-AldiaLog {}
            Mock Add-AldiaHistorial {}
            Mock New-AldiaPuntoRestauracion { throw 'No debe crear un punto de restauración.' }
            Mock Update-AldiaWindows { throw 'No debe buscar ni instalar actualizaciones.' }
            Invoke-AldiaActualizacion (Get-AldiaConfig) @('windows') 'prueba.jsonl' | Should Be 3
            Assert-MockCalled Add-AldiaHistorial -Scope It -Times 1 -Exactly -ParameterFilter {
                $Entrada.Codigo -eq 3 -and !$Entrada.Completa -and $Entrada.Resultados[0].Estado -eq 'omitido'
            }
            Assert-MockCalled New-AldiaPuntoRestauracion -Scope It -Times 0 -Exactly
            Assert-MockCalled Update-AldiaWindows -Scope It -Times 0 -Exactly
        }

        It 'simula Office sin esperar ni pedir que se cierren sus programas' {
            Mock Get-AldiaOffice { @{ Version='16.0.1000'; Nombre='Microsoft 365 / Office' } }
            Mock Test-Path { $true }
            Mock Invoke-AldiaComando { @{ Codigo=0 } }
            $config = @{ timeoutMinutosPorPaquete=1 }
            (Update-AldiaOffice $config -Simular).Estado | Should Be 'simulado'
            Assert-MockCalled Invoke-AldiaComando -Scope It -Times 1 -Exactly -ParameterFilter {
                $Simular -and $Ejecutable -like '*OfficeC2RClient.exe' -and $Argumentos -contains 'forceappshutdown=false'
            }
        }

        It 'usa otros productos de Microsoft solo cuando el servicio está disponible y el equipo no está gestionado' {
            Mock Test-AldiaMicrosoftUpdate { $true }
            Mock Test-AldiaEquipoGestionado { $false }
            $buscador = [pscustomobject]@{ ServerSelection=0; ServiceID=''; Criterio='' }
            $buscador | Add-Member ScriptMethod Search {
                param($Criterio)
                $this.Criterio = $Criterio
                @{ Updates=@() }
            }
            $sesion = [pscustomobject]@{ Buscador=$buscador }
            $sesion | Add-Member ScriptMethod CreateUpdateSearcher { $this.Buscador }
            $null = Find-AldiaActualizacionesWU $sesion Software
            $buscador.ServerSelection | Should Be 3
            $buscador.ServiceID | Should Be '7971f918-a847-4430-9279-4a52d1efe18d'
            $buscador.Criterio | Should Match "Type='Software'"
            $buscador.ServerSelection = 0
            Mock Test-AldiaEquipoGestionado { $true }
            $null = Find-AldiaActualizacionesWU $sesion Driver
            $buscador.ServerSelection | Should Be 0
        }

        It 'lee Windows por compilación, edición y fecha, y destaca Insider' {
            Mock Get-ItemProperty {}
            Mock Get-AldiaVersionWindows { @{ CurrentBuildNumber=26100; EditionID='Professional' } }
            (Get-AldiaSoporteWindows -Ahora ([datetime]'2026-08-01')).Estado | Should Be 'aviso'
            (Get-AldiaSoporteWindows -Ahora ([datetime]'2026-10-14')).Estado | Should Be 'mal'
            Mock Get-AldiaVersionWindows { @{ CurrentBuildNumber=26100; EditionID='IoTEnterprise' } }
            (Get-AldiaSoporteWindows -Ahora ([datetime]'2026-10-14')).Estado | Should Be 'bien'
            Mock Get-ItemProperty { @{ BranchName='Dev' } }
            (Get-AldiaSoporteWindows -Ahora ([datetime]'2026-10-14')).Detalle | Should Match 'Insider'
        }

        It 'escapa HTML y oculta nombres, rutas y direcciones en el informe' {
            Mock Get-CimInstance { @{ SerialNumber='SERIE-PRIVADA-1' } }
            Mock Get-AldiaDireccionesPrivadas { '192.168.1.25','fe80::1234','a0:bb:cc:dd:ee:10' }
            $programa = "<script> $env:USERNAME $env:COMPUTERNAME 192.168.1.25 fe80::1234 a0:bb:cc:dd:ee:10 C:\Users\Otro\archivo SERIE-PRIVADA-1 Python 3.10.8.0 a las 12:30:05"
            $datos = @{ Equipo=@{ Modelo=$programa }; Salud=@(); Filas=@(); Historial=@() }
            $ruta = Join-Path $TestDrive 'informe.html'
            $null = Save-AldiaInforme (Get-AldiaConfig) $ruta '' $datos
            $html = Get-Content -LiteralPath $ruta -Raw -Encoding UTF8
            $html | Should Match '&lt;script&gt;'
            $html | Should Not Match '<script>|192\.168\.1\.25|fe80::1234|a0:bb:cc:dd:ee:10|Users\\Otro|SERIE-PRIVADA-1'
            if ($env:USERNAME) { $html | Should Not Match ([regex]::Escape("&gt; $env:USERNAME ")) }
            $html | Should Match 'Python 3\.10\.8\.0 a las 12:30:05'
        }

        It 'solo cuenta ejecuciones completas o antiguas con un modo válido' {
            Mock Get-AldiaBateria { @{ EnBateria=$false } }
            $ahora = [datetime]'2026-11-22T12:00:00'
            foreach ($modo in 'ventana','adoptar','deshacer','') {
                $h = [pscustomobject]@{ Modo=$modo; Codigo=0; Fin=$ahora.AddHours(-1) }
                Get-AldiaMotivoOmision @{} @($h) -Ahora $ahora | Should BeNullOrEmpty
            }
            $h = [pscustomobject]@{ Modo='interactivo'; Codigo=1; Fin=$ahora.AddHours(-1); Completa=$false }
            Get-AldiaMotivoOmision @{} @($h) -Ahora $ahora | Should BeNullOrEmpty
            $h.Completa = $true
            Get-AldiaMotivoOmision @{} @($h) -Ahora $ahora | Should Match '20 horas'
        }

        It 'separa Bonjour, Epic y un hallazgo vigente por el año del CVE' {
            $ahora = [datetime]'2026-11-22'
            $contexto = @{ Kev=@{}; Epss=@{} }
            $casos = @(
                @{ Nombre='Bonjour'; Version='3.1.0.1'; Id='CVE-2011-0220'; Fecha='2020-01-01'; AlDia=$false; Riesgo='Bajo'; Dudoso=$true; Texto='dato antiguo' }
                @{ Nombre='Epic Games Launcher'; Version='1.3.210.0'; Id='CVE-2018-17707'; AlDia=$true; Riesgo='Bajo'; Dudoso=$true; Texto='probablemente no afecta' }
                @{ Nombre='Programa de prueba'; Version='1'; Id='CVE-2025-12345'; AlDia=$false; Riesgo='Alto'; Dudoso=$false; Texto='2025' }
            )
            foreach ($c in $casos) {
                $p = @{ Nombre=$c.Nombre; Version=$c.Version; Fuente='apps' }
                $datos = @{ Datos=@(@{ Id=$c.Id; Cvss=8; Published=$c.Fecha }); Disponible=$true; Edad=0 }
                $informe = New-AldiaInformePrograma $p $datos $contexto -AlDia:$c.AlDia -Ahora $ahora
                $informe.Riesgo | Should Be $c.Riesgo
                $informe.Dudoso | Should Be $c.Dudoso
                $informe.Detalle | Should Match $c.Texto
            }
        }

        It 'avisa al deshacer solo con los CVE de la versión anterior en caché' {
            Mock Get-AldiaCpe { @{ Datos='demo:programa' } }
            Mock Get-AldiaCvesNvd { @{ Datos=@(@{ Id='CVE-2025-12345' }) } }
            Mock Invoke-AldiaHttp { throw 'No se debe usar la red.' }
            (Get-AldiaAvisoDeshacer @{ Fuente='apps'; Id='Demo.Programa' } '1.2.3') | Should Match 'Ojo:.*CVE-2025-12345'
            Assert-MockCalled Get-AldiaCvesNvd -Scope It -ParameterFilter { $Version -eq '1.2.3' }
            Assert-MockCalled Invoke-AldiaHttp -Scope It -Times 0 -Exactly
        }
    }
}