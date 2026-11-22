function Get-AldiaInformeDemoGui {
    $programa = @{ Nombre='CodeMeter Runtime'; Id='Wibu-Systems.CodeMeterRuntimeKit'; Version='7.50'; Fuente='apps' }
    $consulta = @{ Disponible=$true; Edad=0; Datos=@(
        @{ Id='CVE-2023-3935'; Cvss=9.8; Url='https://nvd.nist.gov/vuln/detail/CVE-2023-3935' }
    ) }
    @{ Programas=@(New-AldiaInformePrograma $programa $consulta @{ Kev=@{}; Epss=@{} } $null); Avisos=@() }
}

function Show-AldiaDetallesSeguridadGui {
    param($Informe)
    $g = $script:AldiaGui
    $ventana = [Windows.Window]::new()
    $ventana.Title = $Informe.Nombre
    $ventana.Owner = $g.Ventana
    $ventana.WindowStartupLocation = 'CenterOwner'
    $ventana.Width = 500
    $ventana.Height = 360
    $scroll = [Windows.Controls.ScrollViewer]::new()
    $panel = [Windows.Controls.StackPanel]::new()
    $panel.Margin = '12'
    foreach ($c in $Informe.Fallos) {
        $fila = [Windows.Controls.StackPanel]::new()
        $datos = @($c.Id)
        if ($null -ne $c.Cvss) { $datos += "CVSS $($c.Cvss)" }
        if ($null -ne $c.Epss) { $datos += ('EPSS {0:P1}' -f $c.Epss) }
        if ($c.Explotado) { $datos += 'explotado activamente' }
        if ($c.Ransomware -eq 'Known') { $datos += 'usado en ransomware' }
        if ($c.FechaLimite) { $datos += "fecha límite CISA $($c.FechaLimite)" }
        $null = $fila.Children.Add((New-AldiaTextoGui ($datos -join ' · ') -Negrita))
        $boton = New-AldiaBotonGui "Abrir $($c.Id)" $c.Url {
            param($sender,$e)
            Open-AldiaUrlGui $sender.Tag
        }
        $boton.HorizontalAlignment = 'Left'
        $null = $fila.Children.Add($boton)
        New-AldiaTarjetaGui $panel $fila
    }
    $scroll.Content = $panel
    $ventana.Content = $scroll
    $null = $ventana.ShowDialog()
}

function Show-AldiaSeguridadGui {
    param($Informe)
    $g = $script:AldiaGui
    $panel = $g.Controles.Seguridad
    $panel.Children.Clear()
    $hallazgos = @($Informe.Programas | Where-Object { $_.Nivel -gt 0 -and !$_.Dudoso })
    $porId = @{}
    foreach ($p in $hallazgos) {
        foreach ($id in @($p.Id) + @($p.Ids)) { if ($id) { $porId["$($p.Fuente)|$id"] = $p } }
    }
    foreach ($fila in $g.Modelo | Where-Object Fuente -in apps,npm) {
        $fila.Riesgo = [int]$porId["$($fila.Fuente)|$($fila.Id)"].Nivel
    }
    if ($hallazgos.Count) {
        $titulo = New-AldiaTextoGui "Programas con fallos de seguridad ($($hallazgos.Count))" -Negrita
        $titulo.FontSize = 16
        $titulo.Margin = '0,8,0,4'
        $null = $panel.Children.Add($titulo)
    }
    foreach ($p in $hallazgos) {
        $tarjeta = [Windows.Controls.StackPanel]::new()
        $encabezado = [Windows.Controls.DockPanel]::new()
        $insignia = [Windows.Controls.Border]::new()
        $insignia.CornerRadius = '8'
        $insignia.Padding = '8,2'
        $insignia.Margin = '8,0,0,0'
        $insignia.Background = if ($p.Nivel -eq 4) { '#FDE7E7' } else { '#FFF0D2' }
        $riesgo = New-AldiaTextoGui $p.Riesgo -Negrita
        $riesgo.Foreground = if ($p.Nivel -eq 4) { '#A52121' } else { '#804B00' }
        $insignia.Child = $riesgo
        [Windows.Controls.DockPanel]::SetDock($insignia,'Right')
        $null = $encabezado.Children.Add($insignia)
        $null = $encabezado.Children.Add((New-AldiaTextoGui "$($p.Nombre) $($p.Version)" -Negrita))
        $null = $tarjeta.Children.Add($encabezado)
        $null = $tarjeta.Children.Add((New-AldiaTextoGui $p.Detalle))
        $null = $tarjeta.Children.Add((New-AldiaTextoGui $p.Accion))
        $boton = New-AldiaBotonGui 'Ver detalles' $p {
            param($sender,$e)
            Show-AldiaDetallesSeguridadGui $sender.Tag
        }
        $boton.HorizontalAlignment = 'Left'
        $null = $tarjeta.Children.Add($boton)
        if (!$p.Actualizacion -and $p.Fuente -eq 'apps' -and $g.CandidatosAdopcion) {
            $candidato = foreach ($id in @($p.Id) + @($p.Ids)) {
                if ($id -and $g.CandidatosAdopcion.ContainsKey($id)) { $g.CandidatosAdopcion[$id]; break }
            }
            if ($candidato) {
                $adoptar = New-AldiaBotonAdopcionGui $candidato.Id
                $adoptar.HorizontalAlignment = 'Left'
                $null = $tarjeta.Children.Add($adoptar)
            }
        }
        New-AldiaTarjetaGui $panel $tarjeta
    }
    $dudosos = @($Informe.Programas | Where-Object Dudoso)
    if ($dudosos.Count) {
        $expansor = [Windows.Controls.Expander]::new()
        $expansor.Header = Format-AldiaCantidadGui $dudosos.Count 'programa con datos dudosos (probablemente no te afecta)' 'programas con datos dudosos (probablemente no te afectan)'
        $lista = [Windows.Controls.StackPanel]::new()
        foreach ($p in $dudosos) {
            $null = $lista.Children.Add((New-AldiaBotonGui "$($p.Nombre) · $($p.Detalle)" $p {
                param($sender,$e)
                Show-AldiaDetallesSeguridadGui $sender.Tag
            }))
        }
        $expansor.Content = $lista
        $null = $panel.Children.Add($expansor)
    }
    $null = $panel.Children.Add((New-AldiaTextoGui (Format-AldiaRevisionSeguridad $Informe)))
    $sinConexion = @($Informe.Programas | Where-Object Detalle -like 'No se pudo comprobar*').Count
    if ($sinConexion) { $null = $panel.Children.Add((New-AldiaTextoGui "No se pudo comprobar (sin conexión): $sinConexion programas.")) }
    $edad = ($Informe.Programas | Measure-Object Edad -Maximum).Maximum
    if ($edad) { $null = $panel.Children.Add((New-AldiaTextoGui "Algunos resultados son de hace $edad h.")) }
    foreach ($aviso in $Informe.Avisos) { Add-AldiaAvisoGui $aviso }
    Show-AldiaFilasGui $g.Modelo
    $g.Controles.Fase.Text = 'Comprobación de seguridad completada.'
}

function Start-AldiaAccionSaludGui {
    param($Item, [string]$Operacion = 'accionSalud')
    $mensaje = switch ($Item.Id) {
        microsoftUpdate { '¿Buscar también actualizaciones de otros programas de Microsoft?' }
        firewall { '¿Activar los perfiles del firewall que están desactivados?' }
        restauracion { '¿Activar los puntos de restauración en la unidad del sistema?' }
        smb1 { '¿Desactivar SMBv1? Es posible que tengas que reiniciar para terminar.' }
        reinicio { '¿Reiniciar el PC ahora? Guarda tu trabajo antes de continuar.' }
    }
    if ($mensaje -and !$script:AldiaGui.Demo -and [Windows.MessageBox]::Show($script:AldiaGui.Ventana,$mensaje,'Al Día','YesNo','Question','No') -ne 'Yes') { return }
    Start-AldiaOperacionGui $Operacion $Item.Id
}

function Show-AldiaSaludGui {
    param($Resultados)
    $g = $script:AldiaGui
    $colores = @{ bien='#186532'; aviso='#804B00'; mal='#A52121'; desconocido='#465A72' }
    $etiquetas = @{ bien='Bien'; aviso='Aviso'; mal='Requiere atención'; desconocido='Desconocido' }
    foreach ($item in $Resultados) { $g.ResultadosSalud[$item.Id] = $item }
    $bien = @($g.ResultadosSalud.Values | Where-Object Estado -eq bien).Count
    $estados = @($g.ResultadosSalud.Values | ForEach-Object Estado)
    $global = if ('mal' -in $estados) { 'mal' } elseif ('aviso' -in $estados) { 'aviso' }
        elseif ('desconocido' -in $estados) { 'desconocido' } else { 'bien' }
    $g.Controles.ResumenSalud.Text = "● $bien de $($g.ResultadosSalud.Count) bien"
    $g.Controles.ResumenSalud.Foreground = $colores[$global]
    $panel = $g.Controles.TarjetasSalud
    $panel.Children.Clear()
    foreach ($id in @($script:AldiaSalud.Keys) + @('versionWindows','gestion','microsoftUpdate')) {
        $item = $g.ResultadosSalud[$id]
        if (!$item) { continue }
        $tarjeta = [Windows.Controls.StackPanel]::new()
        $nombre = New-AldiaTextoGui "● $($item.Nombre) · $($etiquetas[$item.Estado])" -Negrita
        $nombre.Foreground = $colores[$item.Estado]
        $null = $tarjeta.Children.Add($nombre)
        $null = $tarjeta.Children.Add((New-AldiaTextoGui $item.Detalle))
        $null = $tarjeta.Children.Add((New-AldiaTextoGui $item.Explicacion))
        if ($id -eq 'red' -and $item.Datos.Count) {
            $lista = [Windows.Controls.StackPanel]::new()
            foreach ($c in $item.Datos) {
                $null = $lista.Children.Add((New-AldiaTextoGui "$($c.Direccion) · puerto $($c.Puerto) · $($c.Programa) $($c.Ruta) $($c.Explicacion)"))
            }
            $expansor = [Windows.Controls.Expander]::new()
            $expansor.Header = 'Ver servicios'
            $expansor.Content = $lista
            $null = $tarjeta.Children.Add($expansor)
        }
        if ($item.Accion) {
            $boton = New-AldiaBotonGui $item.Accion $item {
                param($sender,$e)
                Start-AldiaAccionSaludGui $sender.Tag
            }
            $boton.HorizontalAlignment = 'Left'
            $null = $tarjeta.Children.Add($boton)
        }
        New-AldiaTarjetaGui $panel $tarjeta
    }
}

function Invoke-AldiaSaludGui {
    param($Operacion, $Datos, [bool]$Demo)
    if ($Operacion -eq 'salud') {
        $items = if ($Demo) { Get-AldiaSaludDemo $estado.CambiosSaludDemo } else { Get-AldiaSalud }
        $estado.SaludInforme = @($items)
        Send-AldiaEventoGui salud @($items)
        Send-AldiaEventoGui fase 'Comprobación de salud completada.'
    } else {
        if ($Demo) {
            if ($Datos -in 'firewall','restauracion','smb1','reinicio') { $estado.CambiosSaludDemo[$Datos] = $true }
            $item = Get-AldiaSaludDemo $estado.CambiosSaludDemo | Where-Object Id -eq $Datos
        } else { $item = Invoke-AldiaAccionSalud $Datos }
        Send-AldiaEventoGui salud @($item)
        if ($Datos -eq 'restauracion' -and $item.Estado -eq 'bien') {
            if ($Demo) { $estado.ProteccionDemo = $true }
            Send-AldiaEventoGui proteccion 'activada'
        }
        $mensaje = if ($Demo) { 'Acción simulada.' }
            elseif ($Datos -eq 'smb1') { 'Estado de SMBv1 comprobado. Reinicia si el cambio está pendiente.' }
            else { 'Comprobación actualizada.' }
        Send-AldiaEventoGui fase $mensaje
    }
}
