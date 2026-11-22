Import-Module (Join-Path (Split-Path $PSScriptRoot) 'Aldia.psd1') -Force

Describe 'Interfaz gráfica de Al Día' {
    InModuleScope Aldia {
        It 'forma el singular y el plural, incluido cero' {
            Format-AldiaCantidadGui 1 'actualización disponible' 'actualizaciones disponibles' | Should Be '1 actualización disponible'
            Format-AldiaCantidadGui 2 'actualización disponible' 'actualizaciones disponibles' | Should Be '2 actualizaciones disponibles'
            Format-AldiaCantidadGui 0 'fallida' 'fallidas' | Should Be '0 fallidas'
            Format-AldiaCantidadGui 1 'seleccionada' 'seleccionadas' | Should Be '1 seleccionada'
        }

        It 'detecta desactivación explícita y respeta la directiva de la organización' {
            Mock Get-ItemProperty { @{ DisableSR=1 } } -ParameterFilter { $LiteralPath -like '*CurrentVersion*' }
            Mock Get-ItemProperty {} -ParameterFilter { $LiteralPath -like '*Policies*' }
            Mock Get-CimInstance { throw 'No consultar el almacenamiento en este caso.' }
            Get-AldiaProteccionGui 'C:' | Should Be 'desactivada'
            Mock Get-ItemProperty { @{ DisableSR=1 } } -ParameterFilter { $LiteralPath -like '*Policies*' }
            Get-AldiaProteccionGui 'C:' | Should Be 'bloqueada'
            Assert-MockCalled Get-CimInstance -Times 0 -Exactly
        }

        It 'comprueba la asociación VSS de la unidad del sistema y distingue fallos de consulta' {
            Mock Get-ItemProperty { @{ RPSessionInterval=1 } } -ParameterFilter { $LiteralPath -like '*CurrentVersion*' }
            Mock Get-ItemProperty {} -ParameterFilter { $LiteralPath -like '*Policies*' }
            Mock Get-CimInstance { @{ DeviceID='\?\Volume{AAAAAAAA-0000-0000-0000-000000000000}\' } } -ParameterFilter { $ClassName -eq 'Win32_Volume' }
            Mock Get-CimInstance {
                @{ Volume='Win32_Volume.DeviceID=Volume{BBBBBBBB-0000-0000-0000-000000000000}' }
            } -ParameterFilter { $ClassName -eq 'Win32_ShadowStorage' }
            Get-AldiaProteccionGui 'D:' | Should Be 'desactivada'
            Mock Get-CimInstance {
                @{ Volume='Win32_Volume.DeviceID=Volume{AAAAAAAA-0000-0000-0000-000000000000}' }
            } -ParameterFilter { $ClassName -eq 'Win32_ShadowStorage' }
            Get-AldiaProteccionGui 'D:' | Should Be 'activada'
            Assert-MockCalled Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_Volume' -and $Filter -eq "DriveLetter = 'D:'" }
            Mock Get-CimInstance { throw 'Consulta no disponible' } -ParameterFilter { $ClassName -eq 'Win32_ShadowStorage' }
            Get-AldiaProteccionGui 'D:' | Should Be 'desconocida'
        }

        It 'extiende las tres pestañas y su contenido en ambos tamaños de ventana' {
            $ventana = New-AldiaVentanaGui
            $raiz = $ventana.Content
            $pestanas = $ventana.FindName('Pestanas')
            foreach ($tamano in [Windows.Size]::new(900,620),[Windows.Size]::new(1280,800)) {
                for ($i = 0; $i -lt $pestanas.Items.Count; $i++) {
                    $pestanas.SelectedIndex = $i
                    $raiz.Measure($tamano)
                    $raiz.Arrange([Windows.Rect]::new($tamano))
                    $raiz.UpdateLayout()
                    $pestanas.ActualWidth | Should Be $tamano.Width
                    $presentador = $pestanas.Template.FindName('PART_SelectedContentHost',$pestanas)
                    $presentador.ActualWidth | Should Be $tamano.Width
                    ($presentador.ActualHeight -gt ($tamano.Height - 180)) | Should Be $true
                    ($pestanas.SelectedContent.ActualWidth -ge ($tamano.Width - 24)) | Should Be $true
                }
            }
        }

        It 'presenta los problemas reales de dispositivos sin permitir su instalación' {
            $fila = ConvertTo-AldiaFilaGui pnp @{ Problema=$true; Nombre='Red'; Codigo=28; Mensaje='no tiene driver instalado'; HardwareID='PCI\VEN_1&DEV_2' } (Get-AldiaConfig)
            $fila.Categoria | Should Be 'Dispositivos sin driver'
            $fila.Habilitada | Should Be $false
            $fila.Seleccionada | Should Be $false
            $fila.Motivo | Should Match '28.*no tiene driver instalado'
            (ConvertTo-AldiaFilaGui pnp @{ Problema=$false; Codigo=22 } (Get-AldiaConfig)) | Should BeNullOrEmpty
        }

        It 'conserva los datos de Windows Update y bloquea la interacción requerida' {
            $u = @{ Title='Wi-Fi'; DriverManufacturer='Intel'; DriverClass='Red'; DriverVerDate=[datetime]'2025-01-02'
                MaxDownloadSize=18MB; Identity=@{ UpdateID='identificador' }; InstallationBehavior=@{ CanRequestUserInput=$true } }
            $fila = ConvertTo-AldiaFilaGui drivers $u (Get-AldiaConfig)
            $fila.Detalle | Should Be 'Intel · Red · 02/01/2025'
            $fila.Id | Should Be 'identificador'
            $fila.Bytes | Should Be 18874368
            $fila.Estado | Should Be 'No disponible'
            $fila.Motivo | Should Be 'Requiere interacción.'
            $fila.Paquete | Should BeNullOrEmpty
        }

        It 'ordena los trabajos seleccionados y deja AppInstaller al final de los programas' {
            $config = Get-AldiaConfig
            $filas = @(Get-AldiaDemoGui $config)
            $filas += ConvertTo-AldiaFilaGui apps @{ Id='Microsoft.AppInstaller'; Nombre='winget'; Origen='winget'; Version='1'; Disponible='2' } $config
            ($filas | Where-Object Id -eq 'Microsoft.VisualStudioCode').Detalle | Should Be '1.99 → 1.100'
            ($filas | Where-Object Id -eq 'Ejemplo.Aplicacion').Motivo | Should Match 'fijado'
            $trabajos = @(Get-AldiaTrabajosGui $filas)
            ($trabajos.Id -join ',') | Should Be 'demo-windows,demo-driver,Microsoft.VisualStudioCode,Microsoft.AppInstaller,typescript'
            ($filas | Where-Object Fuente -eq npm).Seleccionada = $false
            @(Get-AldiaTrabajosGui $filas).Count | Should Be 4
        }

        It 'resume fallos, tiempos agotados y reinicio sin contar elementos omitidos' {
            $resultados = @(
                (New-AldiaResultado windows a actualizado 2 '' -Reinicio $true)
                (New-AldiaResultado npm b fallo 1 '')
                (New-AldiaResultado apps c timeout $null '')
                (New-AldiaResultado apps d omitido $null '')
            )
            $resumen = Get-AldiaResumenGui $resultados
            $resumen.Actualizadas | Should Be 1
            $resumen.Fallidas | Should Be 2
            $resumen.Reinicio | Should Be $true
        }

        It 'codifica el Hardware ID completo como un solo parámetro de búsqueda' {
            Get-AldiaUrlDriverGui 'PCI\VEN_1&DEV_2 +á' | Should Be 'https://www.bing.com/search?q=PCI%5CVEN_1%26DEV_2%20%2B%C3%A1'
        }

        It 'valida todos los ajustes antes de modificar la configuración' {
            $c = Get-AldiaConfig
            $c.excluir = @('Ejemplo.Aplicacion')
            $cambios = @{ Hora='24:00'; Activa=$false; Fuentes=@{ apps=$false; windows=$true; drivers=$true; npm=$true } }
            { Set-AldiaConfigGui $c $cambios } | Should Throw
            $cambios.Hora = '07:35'
            $cambios.Fuentes.npm = 'true'
            { Set-AldiaConfigGui $c $cambios } | Should Throw
            $c.horaDiaria | Should Be '12:00'
            $cambios.Fuentes.npm = $false
            $nueva = Set-AldiaConfigGui $c $cambios
            $nueva.horaDiaria | Should Be '07:35'
            $nueva.fuentes.npm | Should Be $false
            $nueva.excluir[0] | Should Be 'Ejemplo.Aplicacion'
        }

        It 'restaura el JSON si falla el registro de la tarea y conserva los cambios al reintentar' {
            $programa = (Get-PSDrive TestDrive).Root
            $rutaConfig = Join-Path $programa 'config-gui.json'
            $config = Get-AldiaConfig
            $original = $config | ConvertTo-Json -Depth 10
            [IO.File]::WriteAllText($rutaConfig,$original)
            $cambios = @{ Hora='08:30'; Activa=$false; Fuentes=@{ apps=$true; windows=$true; drivers=$false; npm=$true } }
            Mock Assert-AldiaPermisos {}
            Mock Set-AldiaPropietarioAdmin {}
            Mock Get-AldiaTareaGui { [pscustomobject]@{ Enabled=$true } }
            Mock Register-AldiaTarea { throw 'Error de prueba al registrar.' }
            { Save-AldiaConfigGui $cambios } | Should Throw
            [IO.File]::ReadAllText($rutaConfig) | Should Be $original
            Mock Register-AldiaTarea {} -ParameterFilter { $Config.horaDiaria -eq '08:30' -and $Deshabilitada }
            $config = Get-AldiaConfig $rutaConfig
            Save-AldiaConfigGui $cambios
            $guardada = Get-AldiaConfig $rutaConfig
            $guardada.horaDiaria | Should Be '08:30'
            $guardada.fuentes.drivers | Should Be $false
        }

        It 'carga el XAML sin mostrar la ventana y encuentra todos los controles usados' {
            $ventana = New-AldiaVentanaGui
            $ventana.IsVisible | Should Be $false
            $ventana.MinWidth | Should Be 760
            foreach ($nombre in $script:AldiaNombresGui) {
                ($null -ne $ventana.FindName($nombre)) | Should Be $true
            }
        }

        It 'conecta el runspace y actualiza controles WPF en demo sin mostrar la ventana' {
            Initialize-AldiaGui -Demo
            try {
                Start-AldiaOperacionGui analizar
                $limite = [datetime]::UtcNow.AddSeconds(20)
                while ($script:AldiaGui.Pendiente -and [datetime]::UtcNow -lt $limite) {
                    Update-AldiaVentanaGui
                    Start-Sleep -Milliseconds 100
                }
                $c = $script:AldiaGui.Controles
                $c.Avisos.Text | Should BeNullOrEmpty
                $c.Titular.Text | Should Be '4 actualizaciones disponibles'
                $c.Actualizar.Content | Should Be 'Actualizar seleccionadas (4)'
                $c.Filas.Children.Count | Should Be 11
                $c.BandaProteccion.Visibility.ToString() | Should Be 'Visible'
                $c.EstadoProteccion.Text | Should Match '^Desactivada'
                $c.Fabricantes.Children[0].Child.Children[1].Children[1].Text | Should Match '^No instalada'
                $c.Fabricantes.Children[1].Child.Children[0].Children[1].Text | Should Be 'Instalada · versión 25.1'
                $c.Ninguna.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
                $c.Actualizar.IsEnabled | Should Be $false
                $c.BandaProteccion.Visibility.ToString() | Should Be 'Collapsed'
                $vistaDriver = $script:AldiaGui.Vistas.Values | Where-Object { $_.Fila.Fuente -eq 'drivers' }
                $vistaDriver.Casilla.IsChecked = $true
                $vistaDriver.Casilla.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.CheckBox]::ClickEvent))
                $c.Actualizar.Content | Should Be 'Actualizar seleccionada (1)'
                $c.Seleccionadas.Text | Should Be '1 seleccionada'
                $c.Todas.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
                $c.Actualizar.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
                $limite = [datetime]::UtcNow.AddSeconds(20)
                while ($script:AldiaGui.Pendiente -and [datetime]::UtcNow -lt $limite) {
                    Update-AldiaVentanaGui
                    Start-Sleep -Milliseconds 100
                }
                $c.Avisos.Text | Should BeNullOrEmpty
                $c.Fase.Text | Should Be '3 actualizadas, 1 fallida.'
                $c.BandaReinicio.Visibility.ToString() | Should Be 'Visible'
                $c.Historial.Items.Count | Should Be 1
                $c.DetalleHistorial.Items.Count | Should Be 4
                $c.Titular.Text | Should Be '1 pendiente'
                $c.ResumenInstalacion.Text | Should Be 'Última instalación · 3 actualizadas, 1 fallida.'
                ($c.DetalleHistorial.ItemsSource | Where-Object Estado -eq 'Falló ✗').Color | Should Be '#A52121'
                $c.ActivarProteccion.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
                $limite = [datetime]::UtcNow.AddSeconds(20)
                while ($script:AldiaGui.Pendiente -and [datetime]::UtcNow -lt $limite) {
                    Update-AldiaVentanaGui
                    Start-Sleep -Milliseconds 100
                }
                $c.EstadoProteccion.Text | Should Match '^Activada'
                $c.ActivarProteccion.Visibility.ToString() | Should Be 'Collapsed'
                $script:AldiaGui.Modelo | ForEach-Object { $_.Habilitada = $false }
                Receive-AldiaEventoGui @{ Tipo='resumen'; Datos=@{ Actualizadas=1; Fallidas=0; Reinicio=$false } }
                $c.Titular.Text | Should Be 'Todo está al día'
                $c.Titular.Foreground.ToString() | Should Be '#FF2E9E4F'
                $c.Fase.Text | Should Be '1 actualizada, 0 fallidas.'
            } finally { Close-AldiaGui }
        }

        It 'analiza e instala en demostración sin consultar el sistema ni escribir historial' {
            Mock Get-AldiaProgramFiles { throw 'No consultar Program Files en demo.' }
            Mock New-AldiaSesionWU { throw 'No consultar Windows Update en demo.' }
            Mock Get-AldiaProteccionGui { throw 'No consultar la protección real en demo.' }
            Mock Enable-ComputerRestore { throw 'No activar la protección real en demo.' }
            Mock Get-AldiaApps { throw 'No consultar winget en demo.' }
            Mock Invoke-AldiaComando { throw 'No arrancar procesos en demo.' }
            Mock Start-Sleep {}
            $cola = [Collections.Concurrent.ConcurrentQueue[object]]::new()
            $estado = @{ ConfigDemo=$null; ActivaDemo=$true; HistorialDemo=@() }
            Invoke-AldiaTrabajoGui analizar $null $true $cola $estado
            $filas = ($cola.ToArray() | Where-Object { $_.Tipo -eq 'filas' }).Datos
            $trabajos = @(Get-AldiaTrabajosGui $filas)
            $trabajos.Count | Should Be 4
            Invoke-AldiaTrabajoGui instalar $trabajos $true $cola $estado
            Invoke-AldiaTrabajoGui proteger $null $true $cola $estado
            $estado.ProteccionDemo | Should Be $true
            Assert-MockCalled Enable-ComputerRestore -Times 0 -Exactly
            Assert-MockCalled Get-AldiaProteccionGui -Times 0 -Exactly
            $estado.HistorialDemo.Count | Should Be 1
            $estado.HistorialDemo[0].Modo | Should Be 'ventana'
            $estado.HistorialDemo[0].RequiereReinicio | Should Be $true
            $estado.HistorialDemo[0].Codigo | Should Be 1
            @($cola.ToArray() | Where-Object { $_.Tipo -eq 'resultado' }).Count | Should Be 4
            @($cola.ToArray() | Where-Object { $_.Tipo -eq 'aviso' }).Count | Should Be 0
        }
    }
}
