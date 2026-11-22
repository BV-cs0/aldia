Import-Module (Join-Path (Split-Path $PSScriptRoot) 'Aldia.psd1') -Force

Describe 'Vulnerabilidades conocidas' {
    InModuleScope Aldia {
        function Read-AldiaFixtureSeguridad($Nombre) {
            $raiz = Split-Path $PSScriptRoot
            Get-Content -LiteralPath (Join-Path $raiz "tests\fixtures\$Nombre") -Raw -Encoding UTF8 | ConvertFrom-Json
        }

        It 'envía la clave, aplica la pausa de NVD y reintenta un 429 una vez' {
            Mock Start-Sleep {}
            Mock Invoke-RestMethod {
                $ex = [InvalidOperationException]::new('Límite')
                $ex | Add-Member NoteProperty Response @{ StatusCode=429 }
                throw $ex
            }
            $script:AldiaUltimaNvd = [datetime]::UtcNow
            { Invoke-AldiaHttp 'https://services.nvd.nist.gov/rest/json/cves/2.0' -Headers @{apiKey='prueba'} } | Should Throw
            Assert-MockCalled Invoke-RestMethod -Times 2 -Exactly -ParameterFilter { $Headers.apiKey -eq 'prueba' }
            Assert-MockCalled Start-Sleep -Times 1 -Exactly -ParameterFilter { $Seconds -eq 30 }
            Assert-MockCalled Start-Sleep -ParameterFilter { $Milliseconds -gt 0 -and $Milliseconds -le 700 }
        }

        It 'permite las dos órdenes de diagnóstico sin comprobar elevación' {
            Mock Show-AldiaVulnerabilidadesCli {}
            Mock Show-AldiaSaludCli {}
            Mock Test-AldiaAdmin { throw 'No requiere administración.' }
            Invoke-AldiaCli @('vulnerabilidades') 'prueba.ps1' | Should Be 0
            Invoke-AldiaCli @('salud') 'prueba.ps1' | Should Be 0
            Assert-MockCalled Show-AldiaVulnerabilidadesCli -Times 1 -Exactly
            Assert-MockCalled Show-AldiaSaludCli -Times 1 -Exactly
            Assert-MockCalled Test-AldiaAdmin -Times 0 -Exactly
        }

        It 'conserva las cinco filas de winget list, incluso los Id con espacios y las filas sin origen' {
            $texto = Get-Content (Join-Path (Split-Path $PSScriptRoot) 'tests\fixtures\winget-list.txt') -Raw -Encoding UTF8
            $filas = @(ConvertFrom-AldiaWinget $texto -ListaCompleta)
            $filas.Count | Should Be 5
            $filas[1].Id | Should Be 'ARP\User\X64\Utilidad con espacios'
            $filas[1].Version | Should Be '2.0'
            $filas[1].Origen | Should BeNullOrEmpty
            $filas[2].Origen | Should Be 'msstore'
        }

        It 'lee Publisher y npm global y omite MSIX de Microsoft y versiones desconocidas' {
            Mock Get-ItemProperty { [pscustomobject]@{ DisplayName='CodeMeter'; DisplayVersion='7.50'; Publisher='Wibu' } }
            Mock Get-AldiaApps {
                @{ Nombre='CodeMeter'; Id='ARP\Machine\CodeMeter'; Version='7.50' }
                @{ Nombre='Sistema'; Id='MSIX\Microsoft.Windows'; Version='1' }
                @{ Nombre='Sin versión'; Id='Demo.Unknown'; Version='Unknown'; VersionDesconocida=$true }
            } -ParameterFilter { $ListaCompleta }
            Mock Get-AldiaNpmEjecutable { 'npm.cmd' }
            Mock Invoke-AldiaComando { @{ Codigo=1; Salida='{"dependencies":{"@org/demo":{"version":"1.0.0"}}}' } }
            $i = Get-AldiaInventarioSeguridad (Get-AldiaConfig)
            $i.Apps.Count | Should Be 1
            $i.Apps[0].Publisher | Should Be 'Wibu'
            $i.Npm[0].Id | Should Be '@org/demo'
            Assert-MockCalled Invoke-AldiaComando -ParameterFilter { ($Argumentos -join ' ') -eq 'ls -g --json --depth 0' }
        }

        It 'combina NVD, CISA y EPSS y conserva los avisos de OSV de las fixtures reales' {
            Mock Get-AldiaInventarioSeguridad {
                @{
                    Apps=@(
                        @{ Nombre='CodeMeter Runtime'; Id='Wibu-Systems.CodeMeterRuntimeKit'; Version='7.50'; Fuente='apps' }
                        @{ Nombre='CodeMeter nuevo'; Id='Wibu-Systems.CodeMeterRuntimeKit'; Version='8.20'; Fuente='apps' }
                    )
                    Npm=@(
                        @{ Nombre='demo-a'; Id='demo-a'; Version='1.0'; Fuente='npm' }
                        @{ Nombre='demo-b'; Id='demo-b'; Version='1.0'; Fuente='npm' }
                    )
                    Avisos=@()
                }
            }
            Mock Invoke-AldiaHttp {
                switch -Wildcard ($Uri) {
                    '*cves/2.0*7.50*' { Read-AldiaFixtureSeguridad 'nvd-cves-codemeter-7.50.json' }
                    '*cves/2.0*8.20*' { Read-AldiaFixtureSeguridad 'nvd-cves-vacio.json' }
                    '*known_exploited*' { Read-AldiaFixtureSeguridad 'cisa-kev.json' }
                    '*first.org*' { Read-AldiaFixtureSeguridad 'epss.json' }
                    '*querybatch' { Read-AldiaFixtureSeguridad 'osv-querybatch.json' }
                    '*GHSA-29mw-wpgm-hmr9' { @{ aliases=@('CVE-2025-22224') }; break }
                    '*osv.dev/v1/vulns/*' { @{ aliases=@() } }
                    default { throw 'Consulta inesperada.' }
                }
            }
            $config = Get-AldiaConfig
            $config.vulnerabilidades.nvdApiKey = 'clave-de-prueba'
            $cache = Join-Path (Get-PSDrive TestDrive).Root 'integracion'
            $r = Get-AldiaVulnerabilidades $config -Cache $cache -Pendientes @(@{Id='Wibu-Systems.CodeMeterRuntimeKit';Disponible='8.20'})
            $r.Programas.Count | Should Be 4
            $viejo = $r.Programas | Where-Object Version -eq '7.50'
            $viejo.Peor | Should Be 'CVE-2023-3935'
            $viejo.Riesgo | Should Be 'Crítico'
            $viejo.Fallos[0].Cvss | Should Be 9.8
            $viejo.Fallos[0].Epss | Should Be 0.01971
            $viejo.Accion | Should Match 'Se actualiza con Al Día'
            ($r.Programas | Where-Object Version -eq '8.20').Nivel | Should Be 0
            $npm = $r.Programas | Where-Object Id -eq 'demo-a'
            $npm.Fallos.Count | Should Be 5
            $npm.Peor | Should Be 'CVE-2025-22224'
            $npm.Explotado | Should Be $true
            $npm.Fallos[0].FechaLimite | Should Match '\d{4}-\d{2}-\d{2}'
            ($r.Programas | Where-Object Id -eq 'demo-b').Nivel | Should Be 0
            (Get-AldiaResumenSeguridad $r) | Should Match 'Quedan 2 programas'
            Assert-MockCalled Invoke-AldiaHttp -ParameterFilter { $Uri -like '*cves*' -and $Headers.apiKey -eq 'clave-de-prueba' } -Times 2 -Exactly
            Assert-MockCalled Invoke-AldiaHttp -ParameterFilter { $Uri -like '*querybatch' -and ($Body | ConvertFrom-Json).queries.Count -eq 2 } -Times 1 -Exactly
        }

        It 'busca el CPE con tokens de producto y fabricante y cachea también la ausencia de coincidencia' {
            Mock Invoke-AldiaHttp { Read-AldiaFixtureSeguridad 'nvd-cpes-codemeter.json' }
            $cache = Join-Path (Get-PSDrive TestDrive).Root 'cpe'
            $p = @{ Nombre='CodeMeter Runtime 7.50 (64-bit) (User)'; Id='ARP\User\Demo'; Publisher='Wibu Systems' }
            (Get-AldiaCpe $p @() @{} $cache).Datos | Should Be 'wibu:codemeter_runtime'
            (Get-AldiaCpe $p @() @{} $cache).Datos | Should Be 'wibu:codemeter_runtime'
            $p.Publisher = 'Otro fabricante'
            (Get-AldiaCpe $p @() @{} $cache).Datos | Should BeNullOrEmpty
            (Get-AldiaCpe $p @() @{} $cache).Disponible | Should Be $true
            Assert-MockCalled Invoke-AldiaHttp -ParameterFilter { $Uri -like '*keywordSearch=CodeMeter%20Runtime' } -Times 2 -Exactly
        }

        It 'muestra caché caducada sin conexión y distingue la falta de caché' {
            $cache = Join-Path (Get-PSDrive TestDrive).Root 'offline'
            (Get-AldiaCacheSeguridad demo 24 { 'dato' } $cache).Datos | Should Be 'dato'
            $ruta = (Get-ChildItem -LiteralPath $cache -Filter '*.json').FullName
            [IO.File]::WriteAllText($ruta, (@{ Fecha=[datetime]::UtcNow.AddHours(-26).ToString('o'); Datos='dato' } | ConvertTo-Json))
            $r = Get-AldiaCacheSeguridad demo 24 { throw 'sin conexión' } $cache
            $r.Datos | Should Be 'dato'
            $r.Edad | Should Be 27
            (Get-AldiaCacheSeguridad ausente 24 { throw 'sin conexión' } $cache).Disponible | Should Be $false
            $p = @{ Id='Demo'; Nombre='Programa'; Version='1.0'; Fuente='apps' }
            $ctx = @{ Kev=@{}; Epss=@{} }
            (New-AldiaInformePrograma $p $r $ctx).Detalle | Should Match 'resultados de hace 27 h'
            $sinConexion = Get-AldiaCacheSeguridad ausente 24 { throw 'sin conexión' } $cache
            (New-AldiaInformePrograma $p $sinConexion $ctx).Detalle | Should Be 'No se pudo comprobar (sin conexión)'
        }

        It 'descarta Rejected, elige CVSS 3.1 y aplica los umbrales de riesgo' {
            $nvd = @{ vulnerabilities=@(
                @{cve=@{id='CVE-2025-1000';vulnStatus='Rejected'}}
                @{cve=@{id='CVE-2025-1001';metrics=@{
                    cvssMetricV31=@(@{cvssData=@{baseScore=4}})
                    cvssMetricV30=@(@{cvssData=@{baseScore=9}})
                }}}
                @{cve=@{id='CVE-2025-1002';metrics=@{cvssMetricV2=@(@{cvssData=@{baseScore=2}})}}}
            ) }
            $c = @(ConvertFrom-AldiaNvd $nvd)
            $c.Count | Should Be 2
            $p = @{ Id='Demo'; Nombre='Programa'; Version='1.0'; Fuente='apps' }
            $ctx = @{ Kev=@{}; Epss=@{} }
            (New-AldiaInformePrograma $p @{ Disponible=$true; Edad=0; Datos=$c } $ctx).Riesgo | Should Be 'Medio'
            $ctx.Epss[$c[1].Id] = 0.1
            (New-AldiaInformePrograma $p @{ Disponible=$true; Edad=0; Datos=$c } $ctx).Riesgo | Should Be 'Alto'
            $ctx.Kev[$c[1].Id] = @{ knownRansomwareCampaignUse='Known'; dueDate='2025-01-01' }
            $r = New-AldiaInformePrograma $p @{ Disponible=$true; Edad=0; Datos=$c } $ctx
            $r.Riesgo | Should Be 'Crítico'
            $r.Ransomware | Should Be $true
        }

        It 'valida la configuración y traduce severidad de Windows Update' {
            $c = Get-AldiaConfig
            $c.vulnerabilidades.activado | Should Be $true
            Merge-AldiaConfig $c ('{"vulnerabilidades":{"activado":false,"nvdApiKey":"ejemplo"}}' | ConvertFrom-Json)
            $c.vulnerabilidades.activado | Should Be $false
            $c.vulnerabilidades.nvdApiKey | Should Be 'ejemplo'
            Merge-AldiaConfig $c ('{"vulnerabilidades":{"activado":"false","nvdApiKey":"a\nb"}}' | ConvertFrom-Json)
            $c.vulnerabilidades.nvdApiKey | Should Be 'ejemplo'
            $fila = ConvertTo-AldiaFilaGui windows @{ Title='Parche'; MsrcSeverity='Critical'; KBArticleIDs=@('123'); Identity=@{UpdateID='x'} } $c
            $fila.Detalle | Should Be 'KB123 · Seguridad · Crítica'
        }

        It 'en modo tarea comprueba después de actualizar y agrega los casos graves al toast' {
            Mock Get-AldiaMotivoOmision {}
            Mock Get-AldiaCosteInternet { 'normal' }
            Mock Test-AldiaDiscoBajo { $false }
            Mock Read-AldiaHistorial {}
            Mock Add-AldiaHistorial {}
            Mock Clear-AldiaLogs {}
            Mock Write-AldiaLog {}
            Mock New-AldiaPuntoRestauracion {}
            Mock Update-AldiaApps { New-AldiaResultado apps prueba actualizado 0 '' }
            Mock Get-AldiaVulnerabilidades { @{ Programas=@(@{ Nombre='Ejemplo'; Nivel=4; Explotado=$true }); Avisos=@() } }
            Mock Send-AldiaToast {}
            $programado = $true
            $c = Get-AldiaConfig
            Invoke-AldiaActualizacion $c @('apps') 'mock.jsonl' | Should Be 0
            Assert-MockCalled Get-AldiaVulnerabilidades -Times 1 -Exactly
            Assert-MockCalled Send-AldiaToast -Times 1 -Exactly -ParameterFilter { $Mensaje -match 'Queda 1 programa.*Ejemplo \(explotado activamente\)' }
            $c.vulnerabilidades.activado = $false
            Invoke-AldiaActualizacion $c @('apps') 'mock.jsonl' | Should Be 0
            Assert-MockCalled Get-AldiaVulnerabilidades -Times 1 -Exactly
        }

        It 'incluye datos de CPE al instalar y comprueba los permisos de la copia' {
            $origen = Split-Path $PSScriptRoot
            Mock Get-AldiaProgramFiles { Join-Path (Get-PSDrive TestDrive).Root 'destino' }
            Mock New-AldiaDirectorioProtegido {}
            Mock Copy-Item {}
            Mock Unblock-File {}
            Mock Set-AldiaPropietarioAdmin {}
            Mock Assert-AldiaPermisos {}
            Mock Get-AldiaConfig {}
            Mock Register-AldiaTarea {}
            Mock Set-AldiaAccesosDirectos {}
            Mock Get-ChildItem {} -ParameterFilter { $LiteralPath -like '*\destino' -and $Force }
            Install-Aldia $origen
            Assert-MockCalled New-AldiaDirectorioProtegido -ParameterFilter { $Ruta -like '*\destino\datos' } -Times 1 -Exactly
            Assert-MockCalled Copy-Item -ParameterFilter { $LiteralPath -like '*\datos\cpe.json' -and $Destination -like '*\destino\datos\cpe.json' } -Times 1 -Exactly
            Assert-MockCalled Assert-AldiaPermisos -ParameterFilter { $Ruta -like '*\destino\datos\cpe.json' } -Times 1 -Exactly
            Assert-MockCalled Register-AldiaTarea -Times 1 -Exactly
        }

        It 'prioriza filas con riesgo en WPF y conserva la selección' {
            Initialize-AldiaGui -Demo
            try {
                $filas = @(Get-AldiaDemoGui (Get-AldiaConfig))
                $fila = $filas | Where-Object Id -eq 'Microsoft.VisualStudioCode'
                $fila.Seleccionada = $false
                Show-AldiaFilasGui $filas
                $informe = Get-AldiaInformeDemoGui
                $informe.Programas[0].Id = $fila.Id
                Show-AldiaSeguridadGui $informe
                $script:AldiaGui.Controles.Filas.Children[0].Text | Should Be 'Actualizaciones de seguridad (1)'
                $script:AldiaGui.Vistas[$fila.Clave].Detalle.Text | Should Match 'Seguridad · Crítico'
                $script:AldiaGui.Vistas[$fila.Clave].Casilla.IsChecked | Should Be $false
            } finally { Close-AldiaGui }
        }
    }
}

Describe 'Salud del PC' {
    InModuleScope Aldia {
        It 'lee Defender, avisa de firmas antiguas y busca antivirus alternativo' {
            Mock Get-MpComputerStatus { @{ AntivirusEnabled=$true; RealTimeProtectionEnabled=$true; AntivirusSignatureAge=3 } }
            (Get-AldiaComprobacionSalud antivirus).Estado | Should Be 'bien'
            Mock Get-MpComputerStatus { @{ AntivirusEnabled=$true; RealTimeProtectionEnabled=$true; AntivirusSignatureAge=4 } }
            (Get-AldiaComprobacionSalud antivirus).Estado | Should Be 'aviso'
            Mock Get-MpComputerStatus { @{ AntivirusEnabled=$true; RealTimeProtectionEnabled=$false } }
            (Get-AldiaComprobacionSalud antivirus).Estado | Should Be 'mal'
            Mock Get-MpComputerStatus { @{ AntivirusEnabled=$false } }
            Mock Get-CimInstance { @{ displayName='Alternativo'; productState=0x041000 } } -ParameterFilter { $ClassName -eq 'AntiVirusProduct' }
            (Get-AldiaComprobacionSalud antivirus).Detalle | Should Be 'Alternativo'
            Mock Get-CimInstance { throw 'acceso denegado' } -ParameterFilter { $ClassName -eq 'AntiVirusProduct' }
            (Get-AldiaComprobacionSalud antivirus).Estado | Should Be 'desconocido'
        }

        It 'lee los perfiles del firewall, activa solo el desactivado y vuelve a consultar' {
            Mock Get-NetFirewallProfile { @{Name='Public';Enabled=$false}; @{Name='Private';Enabled=$true} }
            Mock Set-NetFirewallProfile {
                if ("$Name" -ne 'Public' -or "$Enabled" -notin 'True','1') { throw "Parámetros del firewall inesperados: $Name / $Enabled" }
            }
            $r = Get-AldiaComprobacionSalud firewall
            $r.Estado | Should Be 'mal'
            $r.Datos[0] | Should Be 'Public'
            $null = Invoke-AldiaAccionSalud firewall
            Assert-MockCalled Set-NetFirewallProfile -Times 1 -Exactly
            Assert-MockCalled Get-NetFirewallProfile -Times 3 -Exactly
            Mock Get-NetFirewallProfile { @{Name='Public';Enabled=$true} }
            (Get-AldiaComprobacionSalud firewall).Estado | Should Be 'bien'
            Mock Get-NetFirewallProfile { throw 'acceso denegado' }
            (Get-AldiaComprobacionSalud firewall).Estado | Should Be 'desconocido'
        }

        It 'distingue restauración activa, desactivada, bloqueada y desconocida' {
            Mock Get-AldiaProteccionGui { 'desactivada' }
            (Get-AldiaComprobacionSalud restauracion).Accion | Should Be 'Activar'
            (Get-AldiaComprobacionSalud restauracion).Estado | Should Be 'aviso'
            Mock Enable-ComputerRestore {}
            $null = Invoke-AldiaAccionSalud restauracion
            Assert-MockCalled Enable-ComputerRestore -Times 1 -Exactly
            Mock Get-AldiaProteccionGui { 'bloqueada' }
            (Get-AldiaComprobacionSalud restauracion).Accion | Should BeNullOrEmpty
            Mock Get-AldiaProteccionGui { 'activada' }
            (Get-AldiaComprobacionSalud restauracion).Estado | Should Be 'bien'
            Mock Get-AldiaProteccionGui { 'desconocida' }
            (Get-AldiaComprobacionSalud restauracion).Estado | Should Be 'desconocido'
        }

        It 'distingue cifrado activo, inactivo y sin acceso y solo abre su configuración' {
            Mock Get-BitLockerVolume { @{ ProtectionStatus='On' } }
            (Get-AldiaComprobacionSalud cifrado).Estado | Should Be 'bien'
            Mock Get-BitLockerVolume { @{ ProtectionStatus='Off' } }
            (Get-AldiaComprobacionSalud cifrado).Estado | Should Be 'aviso'
            Mock Invoke-AldiaComando {}
            $null = Invoke-AldiaAccionSalud cifrado
            Assert-MockCalled Invoke-AldiaComando -Times 1 -Exactly -ParameterFilter { $Ejecutable -eq 'ms-settings:deviceencryption' -and $Visible }
            Mock Get-BitLockerVolume { throw 'sin acceso' }
            (Get-AldiaComprobacionSalud cifrado).Estado | Should Be 'desconocido'
        }

        It 'valida los dos valores de UAC y abre sus ajustes' {
            Mock Get-ItemProperty { @{EnableLUA=1;ConsentPromptBehaviorAdmin=5} }
            (Get-AldiaComprobacionSalud uac).Estado | Should Be 'bien'
            Mock Get-ItemProperty { @{EnableLUA=1;ConsentPromptBehaviorAdmin=0} }
            (Get-AldiaComprobacionSalud uac).Estado | Should Be 'mal'
            Mock Invoke-AldiaComando {}
            $null = Invoke-AldiaAccionSalud uac
            Assert-MockCalled Invoke-AldiaComando -Times 1 -Exactly -ParameterFilter { $Ejecutable -like '*UserAccountControlSettings.exe' }
            Mock Get-ItemProperty { @{EnableLUA=1} }
            (Get-AldiaComprobacionSalud uac).Estado | Should Be 'desconocido'
        }

        It 'detecta SMBv1 y solicita desactivación sin reinicio automático' {
            Mock Get-WindowsOptionalFeature { @{State='Enabled'} }
            (Get-AldiaComprobacionSalud smb1).Estado | Should Be 'mal'
            Mock Disable-WindowsOptionalFeature {}
            $null = Invoke-AldiaAccionSalud smb1
            Assert-MockCalled Disable-WindowsOptionalFeature -Times 1 -Exactly -ParameterFilter { $FeatureName -eq 'SMB1Protocol' -and $Online -and $NoRestart }
            Mock Get-WindowsOptionalFeature { @{State='DisablePending'} }
            (Get-AldiaComprobacionSalud smb1).Estado | Should Be 'aviso'
            Mock Get-WindowsOptionalFeature { @{State='DisabledWithPayloadRemoved'} }
            (Get-AldiaComprobacionSalud smb1).Estado | Should Be 'bien'
            Mock Get-WindowsOptionalFeature { throw 'requiere elevación' }
            (Get-AldiaComprobacionSalud smb1).Estado | Should Be 'desconocido'
        }

        It 'distingue arranque seguro activo, inactivo y BIOS sin soporte' {
            Mock Confirm-SecureBootUEFI { $true }
            (Get-AldiaComprobacionSalud arranque).Estado | Should Be 'bien'
            Mock Confirm-SecureBootUEFI { $false }
            (Get-AldiaComprobacionSalud arranque).Estado | Should Be 'aviso'
            Mock Confirm-SecureBootUEFI { throw 'BIOS heredada' }
            (Get-AldiaComprobacionSalud arranque).Estado | Should Be 'desconocido'
        }

        It 'distingue TPM listo, ausente y desconocido' {
            Mock Get-Tpm { @{TpmPresent=$true;TpmReady=$true} }
            (Get-AldiaComprobacionSalud tpm).Estado | Should Be 'bien'
            Mock Get-Tpm { @{TpmPresent=$false;TpmReady=$false} }
            (Get-AldiaComprobacionSalud tpm).Estado | Should Be 'aviso'
            Mock Get-Tpm { throw 'sin acceso' }
            (Get-AldiaComprobacionSalud tpm).Estado | Should Be 'desconocido'
        }

        It 'detecta cada indicio de reinicio y usa el comando central para la acción' {
            Mock Get-ItemProperty { @{} }
            Mock Test-Path { $false }
            (Get-AldiaComprobacionSalud reinicio).Estado | Should Be 'bien'
            Mock Test-Path { $true } -ParameterFilter { $LiteralPath -like '*RebootPending' }
            (Get-AldiaComprobacionSalud reinicio).Estado | Should Be 'aviso'
            Mock Test-Path { $false } -ParameterFilter { $LiteralPath -like '*RebootPending' }
            Mock Test-Path { $true } -ParameterFilter { $LiteralPath -like '*RebootRequired' }
            (Get-AldiaComprobacionSalud reinicio).Estado | Should Be 'aviso'
            Mock Test-Path { $false } -ParameterFilter { $LiteralPath -like '*RebootRequired' }
            Mock Get-ItemProperty { @{PendingFileRenameOperations=@('archivo')} }
            (Get-AldiaComprobacionSalud reinicio).Estado | Should Be 'aviso'
            Mock Invoke-AldiaComando { @{Codigo=0} }
            $null = Invoke-AldiaAccionSalud reinicio
            Assert-MockCalled Invoke-AldiaComando -Times 1 -Exactly -ParameterFilter { $Ejecutable -like '*shutdown.exe' -and ($Argumentos -join ' ') -eq '/r /t 0' }
            Mock Get-ItemProperty { throw 'sin acceso' }
            (Get-AldiaComprobacionSalud reinicio).Estado | Should Be 'desconocido'
        }

        It 'aplica ambos umbrales de espacio y distingue la falta de datos' {
            Mock Get-AldiaDiscoSalud { @{FreeSpace=30GB;Size=100GB} }
            (Get-AldiaComprobacionSalud espacio).Estado | Should Be 'bien'
            Mock Get-AldiaDiscoSalud { @{FreeSpace=19GB;Size=100GB} }
            (Get-AldiaComprobacionSalud espacio).Estado | Should Be 'aviso'
            Mock Get-AldiaDiscoSalud { @{FreeSpace=24GB;Size=600GB} }
            (Get-AldiaComprobacionSalud espacio).Estado | Should Be 'mal'
            Mock Get-AldiaDiscoSalud { @{FreeSpace=4GB;Size=30GB} }
            (Get-AldiaComprobacionSalud espacio).Estado | Should Be 'mal'
            Mock Get-AldiaDiscoSalud { throw 'sin acceso' }
            (Get-AldiaComprobacionSalud espacio).Estado | Should Be 'desconocido'
        }

        It 'ignora desinstalaciones y fallos del historial y aplica los umbrales de antigüedad' {
            Mock New-AldiaSesionWU {
                $buscador = New-Object psobject
                $buscador | Add-Member ScriptMethod GetTotalHistoryCount { 3 }
                $buscador | Add-Member ScriptMethod QueryHistory {
                    @{ Operation=2; ResultCode=2; Date=(Get-Date) }
                    @{ Operation=1; ResultCode=4; Date=(Get-Date) }
                    @{ Operation=1; ResultCode=2; Date=(Get-Date).AddDays(-16) }
                }
                $s = New-Object psobject
                $s | Add-Member NoteProperty Buscador $buscador
                $s | Add-Member ScriptMethod CreateUpdateSearcher { $this.Buscador }
                $s
            }
            (Get-AldiaComprobacionSalud actualizacion).Estado | Should Be 'aviso'
            Mock Get-AldiaFechaActualizacionSalud { (Get-Date).AddDays(-1) }
            (Get-AldiaComprobacionSalud actualizacion).Estado | Should Be 'bien'
            Mock Get-AldiaFechaActualizacionSalud { (Get-Date).AddDays(-31) }
            (Get-AldiaComprobacionSalud actualizacion).Estado | Should Be 'mal'
            Mock Get-AldiaFechaActualizacionSalud {}
            (Get-AldiaComprobacionSalud actualizacion).Estado | Should Be 'desconocido'
        }

        It 'excluye el loopback y solo avisa de puertos sensibles en todas las interfaces' {
            Mock Get-NetTCPConnection {
                @{ LocalAddress='127.0.0.1'; LocalPort=21; OwningProcess=10 }
                @{ LocalAddress='::1'; LocalPort=445; OwningProcess=10 }
                @{ LocalAddress='10.0.0.1'; LocalPort=23; OwningProcess=10 }
                @{ LocalAddress='::'; LocalPort=22352; OwningProcess=10 }
            }
            Mock Get-Process { @{ProcessName='Demo';Path='C:\demo.exe'} }
            $r = Get-AldiaComprobacionSalud red
            $r.Estado | Should Be 'aviso'
            $r.Datos.Count | Should Be 2
            ($r.Datos | Where-Object Riesgo).Puerto | Should Be 22352
            $r.Datos[0].Ruta | Should Be 'C:\demo.exe'
            Assert-MockCalled Get-Process -Times 1 -Exactly
            Mock Get-NetTCPConnection { @{ LocalAddress='10.0.0.1'; LocalPort=23; OwningProcess=10 } }
            (Get-AldiaComprobacionSalud red).Estado | Should Be 'bien'
            Mock Get-NetTCPConnection { throw 'sin acceso' }
            (Get-AldiaComprobacionSalud red).Estado | Should Be 'desconocido'
        }

        It 'muestra doce tarjetas en WPF y simula la acción sin cambiar el equipo' {
            Initialize-AldiaGui -Demo
            try {
                $g = $script:AldiaGui
                Show-AldiaSaludGui @(Get-AldiaSaludDemo @{})
                $g.Controles.TarjetasSalud.Children.Count | Should Be 12
                $g.Controles.ResumenSalud.Text | Should Match '6 de 12 bien'
                Invoke-AldiaTrabajoGui accionSalud firewall $true $g.Cola $g.Estado
                Update-AldiaVentanaGui
                $g.ResultadosSalud.firewall.Estado | Should Be 'bien'
                $g.Controles.ResumenSalud.Text | Should Match '7 de 12 bien'
            } finally { Close-AldiaGui }
        }
    }
}
