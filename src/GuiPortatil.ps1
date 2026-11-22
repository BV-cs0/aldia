function Show-AldiaAvisoWingetGui {
    param($Estado)
    $g = $script:AldiaGui
    $panel = $g.Controles.BandaWinget
    $panel.Children.Clear()
    if ($Estado.Estado -eq 'ok') { return }
    $contenido = [Windows.Controls.StackPanel]::new()
    $contenido.Background = '#FFF0D2'
    $null = $contenido.Children.Add((New-AldiaTextoGui $Estado.Mensaje))
    $boton = New-AldiaBotonGui 'Conseguirlo' $Estado {
        param($sender,$e)
        $g = $script:AldiaGui
        if ($sender.Tag.Estado -eq 'antiguo') {
            $fila = $g.Modelo | Where-Object Id -eq 'Microsoft.AppInstaller' | Select-Object -First 1
            if (!$fila) {
                $config = Get-AldiaConfig
                $fila = ConvertTo-AldiaFilaGui apps @{ Id='Microsoft.AppInstaller'; Nombre='Instalador de aplicaciones de Microsoft'
                    Version=[string]$sender.Tag.Version; Disponible='Última versión'; Origen='winget' } $config
                Show-AldiaFilasGui (@($g.Modelo) + @($fila))
            } elseif ($fila.Habilitada) { $fila.Seleccionada = $true; Show-AldiaFilasGui $g.Modelo }
        } else {
            try {
                if (!(Get-AppxPackage -Name Microsoft.WindowsStore -ErrorAction Stop)) { throw 'Store no disponible.' }
                $null = Invoke-AldiaComando 'ms-windows-store://pdp/?productid=9NBLGGH4NNS1' -Visible
            } catch { Open-AldiaUrlGui 'https://aka.ms/getwinget' }
        }
    }
    $boton.HorizontalAlignment = 'Left'
    $null = $contenido.Children.Add($boton)
    New-AldiaTarjetaGui $panel $contenido
}

function Request-AldiaInformeGui {
    $g = $script:AldiaGui
    $ruta = Get-AldiaRutaInforme
    $dialogo = [Microsoft.Win32.SaveFileDialog]::new()
    $dialogo.FileName = [IO.Path]::GetFileName($ruta)
    $dialogo.InitialDirectory = [IO.Path]::GetDirectoryName($ruta)
    $dialogo.Filter = 'Informe HTML (*.html)|*.html'
    $dialogo.DefaultExt = '.html'
    if ($dialogo.ShowDialog($g.Ventana)) { Start-AldiaOperacionGui informe $dialogo.FileName }
}