function Show-AldiaAdopcionesGui {
    param($Inventario, $Adopciones)
    $panel = $script:AldiaGui.Controles.Inventario
    $panel.Children.Clear()
    $candidatos = @{}
    foreach ($c in $Adopciones) { $candidatos[$c.ArpId] = $c }
    $script:AldiaGui.CandidatosAdopcion = $candidatos
    foreach ($p in $Inventario) {
        $texto = "$($p.Nombre) · $($p.Version)"
        $c = if ($p.Id) { $candidatos[$p.Id] }
        if (!$c) { $null = $panel.Children.Add((New-AldiaTextoGui $texto)); continue }
        $fila = [Windows.Controls.DockPanel]::new()
        $boton = New-AldiaBotonAdopcionGui $c.Id
        [Windows.Controls.DockPanel]::SetDock($boton,'Right')
        $null = $fila.Children.Add($boton)
        $null = $fila.Children.Add((New-AldiaTextoGui "$texto · Posible paquete: $($c.Id) (coincidencia $($c.Confianza))"))
        New-AldiaTarjetaGui $panel $fila
    }
}

function Show-AldiaFijadosGui {
    param($Fijados)
    $panel = $script:AldiaGui.Controles.Fijados
    $panel.Children.Clear()
    if (!$Fijados) { $null = $panel.Children.Add((New-AldiaTextoGui 'No hay programas fijados.')) }
    foreach ($p in $Fijados) {
        $fila = [Windows.Controls.DockPanel]::new()
        $boton = New-AldiaBotonGui 'Dejar de fijar' $p {
            param($sender,$e)
            if (Confirm-AldiaCambioGui "¿Volver a permitir las actualizaciones de $($sender.Tag.id)?") {
                Start-AldiaOperacionGui desfijar $sender.Tag
            }
        }
        [Windows.Controls.DockPanel]::SetDock($boton,'Right')
        $null = $fila.Children.Add($boton)
        $null = $fila.Children.Add((New-AldiaTextoGui "$($p.id) · $($p.version) · $($p.motivo)"))
        New-AldiaTarjetaGui $panel $fila
    }
}

function Confirm-AldiaCambioGui {
    param([string]$Mensaje, [string]$AvisoSeguridad)
    if ($AvisoSeguridad) {
        $ventana = [Windows.Window]::new()
        $ventana.Owner = $script:AldiaGui.Ventana
        $ventana.Title = 'Al Día'
        $ventana.WindowStartupLocation = 'CenterOwner'
        $ventana.SizeToContent = 'Height'
        $ventana.Width = 450
        $panel = [Windows.Controls.StackPanel]::new()
        $panel.Margin = '14'
        $aviso = New-AldiaTextoGui $AvisoSeguridad -Negrita
        $aviso.Foreground = '#A52121'
        $null = $panel.Children.Add($aviso)
        $null = $panel.Children.Add((New-AldiaTextoGui $Mensaje))
        $aceptar = New-AldiaBotonGui 'Volver a la versión anterior' $ventana { param($sender,$e) $sender.Tag.DialogResult = $true }
        $cancelar = New-AldiaBotonGui 'Cancelar' $ventana { param($sender,$e) $sender.Tag.DialogResult = $false }
        $cancelar.IsCancel = $true
        $null = $panel.Children.Add($aceptar)
        $null = $panel.Children.Add($cancelar)
        $ventana.Content = $panel
        return ($ventana.ShowDialog() -eq $true)
    }
    [Windows.MessageBox]::Show($script:AldiaGui.Ventana,$Mensaje,'Al Día','YesNo','Question','No') -eq 'Yes'
}

function Request-AldiaDetalleHistorialGui {
    $g = $script:AldiaGui
    $g.SeleccionHistorial = [guid]::NewGuid()
    $g.ConsultaHistorial = $null
    $resultados = @($g.Controles.Historial.SelectedItem.Resultados | Where-Object { $_ })
    Show-AldiaDetalleHistorialGui @(foreach ($r in $resultados) {
        @{ Resultado=$r; Disponible=$false; Motivo='Comprobando…' }
    })
    if (!@($resultados | Where-Object Estado -eq actualizado).Count) { return }
    $consulta = @{ Seleccion=$g.SeleccionHistorial; Resultados=$resultados }
    if ($g.Pendiente) { $g.ConsultaHistorial = $consulta }
    else { Start-AldiaOperacionGui consultarDeshacer $consulta }
}

function Show-AldiaDetalleHistorialGui {
    param($Planes)
    $script:AldiaGui.Controles.DetalleHistorial.ItemsSource = @(foreach ($plan in $Planes) {
        $r = $plan.Resultado
        $estado = if ($r.Estado -eq 'actualizado' -and $r.RequiereReinicio) { 'Necesita reinicio' }
            else { $script:AldiaEstadosGui[[string]$r.Estado] }
        $fondo,$color = Get-AldiaColoresEstadoGui $estado
        [pscustomobject]@{
            Nombre=if ($r.Titulo) { $r.Titulo } else { $r.Id }
            Estado=if ($estado) { $estado } else { $r.Estado }
            Color=$color; Mensaje=$r.Mensaje; Disponible=[bool]$plan.Disponible; Plan=$plan
            Motivo=if ($r.Estado -eq 'actualizado') { $plan.Motivo } else { '' }
            MostrarDeshacer=if ($r.Estado -eq 'actualizado' -and !$plan.Controlador) { 'Visible' } else { 'Collapsed' }
            MostrarRestaurar=if ($plan.Restaurar) { 'Visible' } else { 'Collapsed' }
            MostrarControlador=if ($plan.Controlador) { 'Visible' } else { 'Collapsed' }
        }
    })
}

function Invoke-AldiaBotonHistorialGui {
    param($Boton)
    $g = $script:AldiaGui
    $plan = $Boton.Tag
    if ($Boton.Content -eq 'Deshacer') {
        if ($plan.Disponible -and (Confirm-AldiaCambioGui "¿Volver a $($plan.Version) y fijar $($plan.Resultado.Id)?" $plan.AvisoSeguridad)) {
            Start-AldiaOperacionGui deshacer $plan.Resultado
        }
        return
    }
    $exe = switch ($Boton.Content) {
        'Abrir Restaurar sistema' { if ($plan.Restaurar) { 'rstrui.exe' } }
        'Administrador de dispositivos' { if ($plan.Controlador) { 'devmgmt.msc' } }
    }
    if (!$exe) { return }
    if ($g.Demo) { $g.Controles.Fase.Text = "Demostración: $exe"; return }
    try { $null = Invoke-AldiaComando (Join-Path $env:SystemRoot "System32\$exe") -Visible }
    catch { Add-AldiaAvisoGui $_.Exception.Message }
}
function New-AldiaBotonAdopcionGui {
    param([string]$Id)
    New-AldiaBotonGui 'Adoptar' $Id {
        param($sender,$e)
        $g = $script:AldiaGui
        if ($g.Ocupado -or ($g.Operacion -and $g.Operacion -ne 'seguridad')) { return }
        if (Confirm-AldiaCambioGui "$($sender.Tag) · $script:AldiaAvisoAdopcion") { Start-AldiaOperacionGui adoptar $sender.Tag }
    }
}