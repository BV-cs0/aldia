$script:AldiaNombresGui = @(
    'Demo','Ocupado','BandaReinicio','Reiniciar','Fase','Avisos','Progreso','Titular','IconoTitular',
    'ResumenInstalacion','BandaProteccion','AvisoProteccion','EstadoProteccion','ActivarProteccion','Todas','Ninguna','Seleccionadas','Analizar','Actualizar','Filas','Historial','DetalleHistorial',
    'Fabricantes','Gpu','Inventario','Fijados','Ajustes','Automatica','Hora','FuenteWindows','FuenteDrivers','FuenteApps','FuenteNpm','Guardar',
    'Seguridad','CuentaEstandar','ResumenSalud','RevisarSalud','TarjetasSalud','BandaWinget','GuardarInforme','EnlaceNvd','ClaveNvd','FuenteOffice','FuenteStore'
)
$script:AldiaEstadosGui = @{
    actualizado='Actualizado ✓'; fallo='Falló ✗'; timeout='Falló ✗'; persistente='Falló ✗'
    aviso='Aviso'; revertido='Revertido'; 'no-aplicable'='No disponible'; omitido='No disponible'
}

function New-AldiaVentanaGui {
    Add-Type -AssemblyName PresentationFramework
    $rutaXaml = Join-Path (Split-Path $PSScriptRoot) 'gui\Principal.xaml'
    $lector = [Xml.XmlReader]::Create($rutaXaml)
    try { [Windows.Markup.XamlReader]::Load($lector) }
    finally { $lector.Dispose() }
}

function Start-AldiaGui {
    param([string]$Entrada, [string[]]$Opciones)
    if (@($Opciones | Where-Object { $_ -notin '--demo','--portatil' }).Count) { throw 'La opción disponible para gui es --demo.' }
    $demo = $Opciones -contains '--demo'
    $elevar = !$demo -and '--portatil' -notin $Opciones -and !(Test-AldiaAdmin)
    if ($elevar -or [Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA') {
        $ps = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
        $r = Invoke-AldiaComando $ps (@('-NoProfile','-STA','-ExecutionPolicy','Bypass','-File',$Entrada,'gui') + $Opciones) -Oculto -Elevar:$elevar
        return $r.Codigo
    }
    Show-AldiaGui -Demo:$demo
    return 0
}

function Start-AldiaOperacionGui {
    param($Operacion, $Datos)
    $g = $script:AldiaGui
    if ($g.Pendiente) {
        if ((!$g.Operacion -or $g.Operacion -eq 'seguridad') -and $Operacion -ne 'estado') {
            $g.SiguienteOperacion = @{ Nombre=$Operacion; Datos=$Datos }
            Update-AldiaControlesGui
        }
        return
    }
    if ($Operacion -ne 'estado') {
        $g.Operacion = $Operacion
        $g.Controles.Avisos.Clear()
        $g.Controles.Avisos.Visibility = 'Collapsed'
        if ($Operacion -ne 'consultarDeshacer') {
            $g.Controles.Fase.Text = switch ($Operacion) {
                'analizar' { 'Preparando el análisis…' }
                'seguridad' { 'Comprobando seguridad…' }
                'salud' { 'Comprobando salud…' }
                'informe' { 'Preparando el informe…' }
                'accionSalud' { 'Aplicando la acción…' }
                'proteger' { 'Activando la protección del sistema…' }
                'guardar' { 'Guardando la configuración…' }
                'reiniciar' { 'Solicitando el reinicio…' }
                'deshacer' { 'Deshaciendo la actualización…' }
                'desfijar' { 'Guardando los programas fijados…' }
                default { 'Preparando la instalación…' }
            }
        }
        $g.Controles.Progreso.Value = 0
        $g.Controles.Progreso.IsIndeterminate = $true
        $g.Controles.Progreso.Visibility = 'Visible'
        Update-AldiaControlesGui
    }
    $g.Pipeline.Commands.Clear()
    $g.Pipeline.Streams.ClearStreams()
    $null = $g.Pipeline.AddScript({
        param($Manifiesto,$Operacion,$Datos,$Demo,$Cola,$Estado)
        $modulo = Import-Module $Manifiesto -PassThru -ErrorAction Stop
        & $modulo { Invoke-AldiaTrabajoGui @args } $Operacion $Datos $Demo $Cola $Estado
    }).AddArgument($g.Manifiesto).AddArgument($Operacion).AddArgument($Datos).AddArgument($g.Demo).AddArgument($g.Cola).AddArgument($g.Estado)
    $g.Pendiente = $g.Pipeline.BeginInvoke()
}

function Update-AldiaControlesGui {
    $g = $script:AldiaGui
    $c = $g.Controles
    $libre = !$g.Operacion
    $n = @($g.Modelo | Where-Object { $_.Habilitada -and $_.Seleccionada }).Count
    $c.Seleccionadas.Text = Format-AldiaCantidadGui $n 'seleccionada' 'seleccionadas'
    $driversSeleccionados = @($g.Modelo | Where-Object { $_.Fuente -eq 'drivers' -and $_.Habilitada -and $_.Seleccionada }).Count
    $c.BandaProteccion.Visibility = if ($g.Proteccion -in 'desactivada','bloqueada' -and $driversSeleccionados) { 'Visible' } else { 'Collapsed' }
    $c.ActivarProteccion.Visibility = if ($g.Proteccion -eq 'activada') { 'Collapsed' } else { 'Visible' }
    $c.ActivarProteccion.IsEnabled = $libre -and !$g.Ocupado -and $g.Proteccion -in 'desactivada','desconocida'
    $c.Actualizar.Content = Format-AldiaCantidadGui $n 'seleccionada' 'seleccionadas' 'Actualizar {1} ({0})'
    $c.Reiniciar.IsEnabled = $libre -and !$g.Ocupado
    $c.Ajustes.IsEnabled = $libre -and !$g.Ocupado -and $g.ConfigLista
    $c.Fabricantes.IsEnabled = $libre -and !$g.Ocupado
    $c.Inventario.IsEnabled = $c.Fijados.IsEnabled = $c.DetalleHistorial.IsEnabled = $libre -and !$g.Ocupado
    $c.RevisarSalud.IsEnabled = $libre
    $c.TarjetasSalud.IsEnabled = $libre -and !$g.Ocupado
    $listaDisponible = $libre -or $g.Operacion -eq 'seguridad'
    $c.Actualizar.IsEnabled = $listaDisponible -and !$g.Ocupado -and !$g.SiguienteOperacion -and $n -gt 0
    $c.Analizar.IsEnabled = $libre
    $c.Todas.IsEnabled = $c.Ninguna.IsEnabled = $listaDisponible -and @($g.Modelo | Where-Object Habilitada).Count -gt 0
    $c.Filas.IsEnabled = $listaDisponible
}

function Open-AldiaUrlGui {
    param([string]$Url)
    $g = $script:AldiaGui
    if ($g.Demo) { $g.Controles.Fase.Text = "Demostración: $Url"; return }
    try {
        if (([uri]$Url).Scheme -ne 'https') { throw 'Solo se admiten enlaces HTTPS.' }
        $null = Invoke-AldiaComando $Url -Visible
    } catch { Add-AldiaAvisoGui $_.Exception.Message }
}

function Add-AldiaAvisoGui {
    param($Mensaje)
    $avisos = $script:AldiaGui.Controles.Avisos
    if ($avisos.Text) { $avisos.AppendText([Environment]::NewLine) }
    $avisos.AppendText([string]$Mensaje)
    $avisos.Visibility = 'Visible'
}

function New-AldiaTextoGui {
    param([string]$Texto, [switch]$Negrita)
    $textoWpf = [Windows.Controls.TextBlock]::new()
    $textoWpf.Text = $Texto
    $textoWpf.TextWrapping = 'Wrap'
    if ($Negrita) { $textoWpf.FontWeight = 'SemiBold' }
    $textoWpf
}

function New-AldiaBotonGui {
    param($Texto, $Dato, [scriptblock]$Accion)
    $boton = [Windows.Controls.Button]::new()
    $boton.Content = $Texto
    $boton.Tag = $Dato
    $boton.Add_Click($Accion)
    $boton
}

function New-AldiaTarjetaGui {
    param($Panel, $Contenido)
    $borde = [Windows.Controls.Border]::new()
    $borde.Margin = '0,0,0,5'
    $borde.Padding = '10,6'
    $borde.Background = '#FFFFFF'
    $borde.BorderBrush = '#DFE7F0'
    $borde.BorderThickness = '1'
    $borde.CornerRadius = '8'
    $borde.Child = $Contenido
    $null = $Panel.Children.Add($borde)
}

function Set-AldiaSeleccionGui {
    param([bool]$Seleccionar)
    $g = $script:AldiaGui
    $g.CargandoFilas = $true
    try {
        foreach ($fila in $g.Modelo | Where-Object Habilitada) {
            $fila.Seleccionada = $Seleccionar
            $g.Vistas[$fila.Clave].Casilla.IsChecked = $Seleccionar
        }
    } finally { $g.CargandoFilas = $false }
    Update-AldiaControlesGui
}

function New-AldiaVistaFilaGui {
    param($Fila)
    $g = $script:AldiaGui
    $panel = [Windows.Controls.DockPanel]::new()
    $casilla = [Windows.Controls.CheckBox]::new()
    $casilla.Margin = '1,0,9,0'
    $casilla.VerticalAlignment = 'Center'
    $casilla.IsChecked = $Fila.Seleccionada
    $casilla.IsEnabled = $Fila.Habilitada
    $casilla.Tag = $Fila
    [Windows.Automation.AutomationProperties]::SetName($casilla, "Seleccionar $($Fila.Nombre)")
    $casilla.Add_Click({
        param($sender,$e)
        $sender.Tag.Seleccionada = [bool]$sender.IsChecked
        if (!$script:AldiaGui.CargandoFilas) { Update-AldiaControlesGui }
    })
    $null = $panel.Children.Add($casilla)

    $icono = New-AldiaTextoGui $Fila.Icono
    $icono.FontFamily = $g.Ventana.FindResource('Iconos')
    $icono.FontSize = 18
    $icono.VerticalAlignment = 'Center'
    $icono.Margin = '0,0,9,0'
    $null = $panel.Children.Add($icono)

    if ($Fila.Hardware) {
        $acciones = [Windows.Controls.StackPanel]::new()
        $acciones.Orientation = 'Horizontal'
        [Windows.Controls.DockPanel]::SetDock($acciones,'Right')
        $buscar = New-AldiaBotonGui 'Buscar driver' $Fila.Hardware {
            param($sender,$e)
            Open-AldiaUrlGui (Get-AldiaUrlDriverGui $sender.Tag)
        }
        $copiar = New-AldiaBotonGui 'Copiar ID' $Fila.Hardware {
            param($sender,$e)
            if ($script:AldiaGui.Demo) { $script:AldiaGui.Controles.Fase.Text = "ID de ejemplo: $($sender.Tag)"; return }
            try {
                [Windows.Clipboard]::SetText([string]$sender.Tag)
                $script:AldiaGui.Controles.Fase.Text = 'ID copiado.'
            } catch { Add-AldiaAvisoGui $_.Exception.Message }
        }
        $null = $acciones.Children.Add($buscar)
        $null = $acciones.Children.Add($copiar)
        $null = $panel.Children.Add($acciones)
    }
    $etiqueta = [Windows.Controls.Border]::new()
    $etiqueta.CornerRadius = '8'
    $etiqueta.Padding = '8,3'
    $etiqueta.Margin = '8,0,0,0'
    $etiqueta.VerticalAlignment = 'Center'
    $estado = New-AldiaTextoGui $Fila.Estado -Negrita
    $etiqueta.Child = $estado
    [Windows.Controls.DockPanel]::SetDock($etiqueta,'Right')
    $null = $panel.Children.Add($etiqueta)
    $texto = [Windows.Controls.StackPanel]::new()
    $null = $texto.Children.Add((New-AldiaTextoGui $Fila.Nombre -Negrita))
    $detalle = New-AldiaTextoGui ''
    $detalle.Foreground = '#465A72'
    $null = $texto.Children.Add($detalle)
    $null = $panel.Children.Add($texto)
    $g.Vistas[$Fila.Clave] = @{ Fila=$Fila; Casilla=$casilla; Estado=$estado; Etiqueta=$etiqueta; Detalle=$detalle; Panel=$panel }
    Update-AldiaVistaFilaGui $g.Vistas[$Fila.Clave]
    $panel
}

function Update-AldiaVistaFilaGui {
    param($Vista)
    $fila = $Vista.Fila
    $Vista.Casilla.IsEnabled = $fila.Habilitada
    $Vista.Casilla.IsChecked = $fila.Seleccionada
    $Vista.Estado.Text = $fila.Estado
    $Vista.Panel.ToolTip = if ($fila.Motivo) { $fila.Motivo }
    $tamano = if ($fila.Bytes -gt 0) { '{0:N1} MB' -f ($fila.Bytes / 1MB) }
    $marca = if ($fila.Riesgo) { 'Seguridad · ' + @('','Bajo','Medio','Alto','Crítico')[$fila.Riesgo] }
    $Vista.Detalle.Text = (@($fila.Detalle,$tamano,$fila.Motivo,$marca) | Where-Object { $_ }) -join ' · '
    $fondo,$texto = Get-AldiaColoresEstadoGui $fila.Estado
    $Vista.Etiqueta.Background = $fondo
    $Vista.Estado.Foreground = $texto
    if ($fila.Riesgo -ge 3 -and $fila.Estado -eq 'Pendiente') {
        $Vista.Etiqueta.Background = if ($fila.Riesgo -eq 4) { '#FDE7E7' } else { '#FFF0D2' }
        if ($fila.Riesgo -eq 4) { $Vista.Estado.Foreground = '#A52121' }
    }
}

function Get-AldiaColoresEstadoGui {
    param($Estado)
    switch ($Estado) {
        'Pendiente' { '#FFF0D2'; '#804B00' }
        'Instalando…' { '#E1ECFA'; '#1F3A5F' }
        'Actualizado ✓' { '#DDF3E3'; '#186532' }
        'Necesita reinicio' { '#FFF0C2'; '#694400' }
        'Falló ✗' { '#FDE7E7'; '#A52121' }
        default { '#E9EDF2'; '#465A72' }
    }
}

function Show-AldiaFilasGui {
    param($Filas)
    $g = $script:AldiaGui
    $c = $g.Controles
    $g.Modelo = @($Filas)
    $g.Vistas.Clear()
    $c.Filas.Children.Clear()
    foreach ($fuente in 'seguridad','pnp','drivers','windows','apps','npm') {
        $grupo = if ($fuente -eq 'seguridad') {
            @($Filas | Where-Object { $_.Riesgo -and $_.Habilitada } | Sort-Object Riesgo -Descending)
        } else { @($Filas | Where-Object { ($_.Fuente -eq $fuente -or ($fuente -eq 'apps' -and $_.Fuente -in 'office','store')) -and !($_.Riesgo -and $_.Habilitada) }) }
        $grupo = @($grupo | Where-Object { $_ })
        if (!$grupo.Count) { continue }
        $categoria = if ($fuente -eq 'seguridad') { 'Actualizaciones de seguridad' } else { $grupo[0].Categoria }
        $titulo = New-AldiaTextoGui "$categoria ($($grupo.Count))" -Negrita
        $titulo.FontSize = 16
        $titulo.Margin = '0,8,0,4'
        $null = $c.Filas.Children.Add($titulo)
        foreach ($f in $grupo) { New-AldiaTarjetaGui $c.Filas (New-AldiaVistaFilaGui $f) }
    }
    Update-AldiaTitularGui
    $c.Fase.Text = 'Análisis completado.'
}

function Update-AldiaTitularGui {
    param([switch]$TrasInstalar)
    $c = $script:AldiaGui.Controles
    $filas = $script:AldiaGui.Modelo
    $n = @($filas | Where-Object Habilitada).Count
    $pnp = @($filas | Where-Object Fuente -eq pnp).Count
    $c.Titular.Text = if ($TrasInstalar -and !$n) { 'Todo está al día' }
        elseif ($TrasInstalar) { Format-AldiaCantidadGui $n 'pendiente' 'pendientes' }
        elseif ($n) { Format-AldiaCantidadGui $n 'actualización disponible' 'actualizaciones disponibles' }
        elseif ($c.Avisos.Text) { 'Análisis parcial' }
        elseif ($pnp) { 'Hay dispositivos que revisar' }
        elseif (@($Filas).Count) { 'Sin actualizaciones instalables' }
        else { 'Todo está al día' }
    $todoAlDia = $c.Titular.Text -eq 'Todo está al día'
    $c.Titular.Foreground = if ($todoAlDia) { '#2E9E4F' } else { '#946000' }
    $c.IconoTitular.Foreground = $c.Titular.Foreground
    $c.IconoTitular.Text = if ($todoAlDia) { [string][char]0xE73E } else { [string][char]0xE895 }
}

function Show-AldiaHistorialGui {
    param($Historial)
    $c = $script:AldiaGui.Controles
    $c.Historial.ItemsSource = @(foreach ($h in $Historial) {
        $resumen = Get-AldiaResumenGui $h.Resultados
        $fecha = $h.Inicio
        try { $fecha = ([datetime]$fecha).ToString('dd/MM/yyyy HH:mm',[cultureinfo]::InvariantCulture) } catch {}
        [pscustomobject]@{
            Fecha=$fecha; Modo=$h.Modo; Actualizadas=$resumen.Actualizadas; Fallidas=$resumen.Fallidas
            Reinicio=if ($h.RequiereReinicio) { 'Sí' } else { 'No' }
            Resultados=$h.Resultados
        }
    })
    if ($c.Historial.Items.Count) { $c.Historial.SelectedIndex = 0 }
}

function Show-AldiaHerramientasGui {
    param($Datos)
    $g = $script:AldiaGui
    $c = $g.Controles
    $c.Fabricantes.Children.Clear()
    foreach ($r in $Datos.Recomendaciones) {
        $panel = [Windows.Controls.DockPanel]::new()
        if ($r.Instalado -ne 'sí') {
            $boton = if ($r.Id) {
                New-AldiaBotonGui 'Instalar' $r.Id { param($sender,$e) Start-AldiaOperacionGui fabricante $sender.Tag }
            } else {
                New-AldiaBotonGui 'Abrir web' $r.Url { param($sender,$e) Open-AldiaUrlGui $sender.Tag }
            }
            [Windows.Controls.DockPanel]::SetDock($boton,'Right')
            $null = $panel.Children.Add($boton)
        }
        $textos = [Windows.Controls.StackPanel]::new()
        $null = $textos.Children.Add((New-AldiaTextoGui $r.Herramienta -Negrita))
        $descripcion = if ($r.SoloMensaje) { '' } elseif ($r.Instalado -eq 'sí') {
            if ($r.Version) { "Instalada · versión $($r.Version)" } else { 'Instalada · versión desconocida' }
        } else { "No instalada · recomendada para tu $($r.Equipo)" }
        $detalle = New-AldiaTextoGui $descripcion
        $detalle.Foreground = '#465A72'
        $null = $textos.Children.Add($detalle)
        $null = $panel.Children.Add($textos)
        New-AldiaTarjetaGui $c.Fabricantes $panel
    }
    if (!$Datos.Recomendaciones) {
        $null = $c.Fabricantes.Children.Add((New-AldiaTextoGui 'Sin recomendaciones del fabricante.'))
    }
    $c.Gpu.Children.Clear()
    foreach ($aviso in $Datos.Gpu) {
        New-AldiaTarjetaGui $c.Gpu (New-AldiaTextoGui "$($aviso.Nombre) · $($aviso.Aviso)")
    }
    Show-AldiaAdopcionesGui $Datos.Inventario $Datos.Adopciones
    Show-AldiaFijadosGui $Datos.Config.fijados
    $c.Automatica.IsChecked = $Datos.Activa
    $c.Hora.Text = $Datos.Config.horaDiaria
    $c.FuenteWindows.IsChecked = $Datos.Config.fuentes.windows
    $c.FuenteDrivers.IsChecked = $Datos.Config.fuentes.drivers
    $c.FuenteApps.IsChecked = $Datos.Config.fuentes.apps
    $c.FuenteNpm.IsChecked = $Datos.Config.fuentes.npm
    $c.FuenteOffice.IsChecked = $Datos.Config.fuentes.office
    $c.FuenteStore.IsChecked = $Datos.Config.fuentes.store
    $c.ClaveNvd.Password = [string]$Datos.Config.vulnerabilidades.nvdApiKey
    $g.ConfigLista = !@($Datos.Errores | Where-Object { $_ -like 'Activa:*' }).Count
    foreach ($errorHerramienta in $Datos.Errores) { Add-AldiaAvisoGui $errorHerramienta }
}

function Receive-AldiaEventoGui {
    param($Evento)
    $g = $script:AldiaGui
    $c = $g.Controles
    $d = $Evento.Datos
    switch ($Evento.Tipo) {
        'ocupado' {
            $g.Ocupado = $d
            $c.Ocupado.Visibility = if ($d) { 'Visible' } else { 'Collapsed' }
        }
        'fase' { $c.Fase.Text = $d }
        'proteccion' {
            $g.Proteccion = $d
            $aviso = 'La protección del sistema está desactivada: si un driver da problemas no podrás volver atrás.'
            $c.AvisoProteccion.Text = if ($d -eq 'bloqueada') { "$aviso La organización controla este ajuste." }
                else { "$aviso Actívala en Herramientas." }
            $estado = switch ($d) {
                'activada' { 'Activada' }
                'desactivada' { 'Desactivada' }
                'bloqueada' { 'Desactivada por la organización' }
                default { 'Estado sin confirmar' }
            }
            $unidad = if ($g.Demo) { 'C:' } else { $env:SystemDrive }
            $c.EstadoProteccion.Text = "$estado en la unidad del sistema ($unidad)"
        }
        'aviso' { Add-AldiaAvisoGui $d }
        'winget' { Show-AldiaAvisoWingetGui $d }
        'filas' { $c.Seguridad.Children.Clear(); Show-AldiaFilasGui $d }
        'seguridadEnCurso' { $g.Operacion = 'seguridad'; Update-AldiaControlesGui }
        'seguridad' { Show-AldiaSeguridadGui $d }
        'salud' { Show-AldiaSaludGui $d }
        'historial' { Show-AldiaHistorialGui $d }
        'planesDeshacer' { if ($d.Seleccion -eq $g.SeleccionHistorial) { Show-AldiaDetalleHistorialGui $d.Planes } }
        'fijados' { Show-AldiaFijadosGui $d }
        'reinicioPendiente' { $c.BandaReinicio.Visibility = 'Visible' }
        'herramientas' { Show-AldiaHerramientasGui $d }
        'instalando' {
            $vista = $g.Vistas[$d.Clave]
            $vista.Fila.Estado = 'Instalando…'
            Update-AldiaVistaFilaGui $vista
            $c.Fase.Text = "$($d.Actual) de $($d.Total) — Instalando $($d.Nombre)…"
            $c.Progreso.IsIndeterminate = $false
            $c.Progreso.Maximum = $d.Total
            $c.Progreso.Value = $d.Actual - 1
        }
        'resultado' {
            $vista = $g.Vistas[$d.Clave]
            $r = $d.Resultado
            $vista.Fila.Seleccionada = $false
            $vista.Fila.Habilitada = $r.Estado -in 'fallo','timeout','persistente'
            $vista.Fila.Estado = if ($r.Estado -eq 'actualizado' -and $r.RequiereReinicio) { 'Necesita reinicio' }
                else { $script:AldiaEstadosGui[$r.Estado] }
            $vista.Fila.Motivo = if ($r.Estado -eq 'timeout' -and !$r.Mensaje) { 'Se agotó el tiempo de espera.' }
                elseif ($r.Estado -eq 'fallo' -and !$r.Mensaje -and $null -eq $r.Codigo) { 'No se pudo completar la instalación.' }
                else { $r.Mensaje }
            if ($r.Estado -in 'fallo','timeout','persistente' -and $null -ne $r.Codigo) {
                $vista.Fila.Motivo = (@($r.Mensaje,"Código de error: $($r.Codigo)") | Where-Object { $_ }) -join ' · '
            }
            Update-AldiaVistaFilaGui $vista
            $c.Progreso.Value++
        }
        'resumen' {
            $actualizadas = Format-AldiaCantidadGui $d.Actualizadas 'actualizada' 'actualizadas'
            $fallidas = Format-AldiaCantidadGui $d.Fallidas 'fallida' 'fallidas'
            $c.Fase.Text = "$actualizadas, $fallidas."
            $c.ResumenInstalacion.Text = "Última instalación · $($c.Fase.Text)"
            $c.ResumenInstalacion.Visibility = 'Visible'
            Update-AldiaTitularGui -TrasInstalar
            if ($d.Reinicio) { $c.BandaReinicio.Visibility = 'Visible' }
        }
    }
}

function Update-AldiaVentanaGui {
    $g = $script:AldiaGui
    $evento = $null
    while ($g.Cola.TryDequeue([ref]$evento)) { Receive-AldiaEventoGui $evento }
    if ($g.Pendiente -and $g.Pendiente.IsCompleted) {
        try { $null = $g.Pipeline.EndInvoke($g.Pendiente) }
        catch { Add-AldiaAvisoGui $_.Exception.Message }
        $g.Pendiente = $null
        # El worker puede haber publicado su último evento después de la primera lectura.
        while ($g.Cola.TryDequeue([ref]$evento)) { Receive-AldiaEventoGui $evento }
        $g.Operacion = $null
        $g.Controles.Progreso.Visibility = 'Collapsed'
        $g.ProximaConsulta = [datetime]::UtcNow.AddSeconds(2)
        Update-AldiaControlesGui
        if ($g.PreguntandoCierre) { return }
        if ($g.CerrarAlTerminar) { $g.Ventana.Close(); return }
        if ($g.SiguienteOperacion) {
            $siguiente = $g.SiguienteOperacion
            $g.SiguienteOperacion = $null
            Start-AldiaOperacionGui $siguiente.Nombre $siguiente.Datos
        } elseif ($g.ConsultaHistorial) {
            $consulta = $g.ConsultaHistorial
            $g.ConsultaHistorial = $null
            Start-AldiaOperacionGui consultarDeshacer $consulta
        }
    } elseif (!$g.Pendiente -and !$g.PreguntandoCierre -and !$g.Demo -and [datetime]::UtcNow -ge $g.ProximaConsulta) {
        Start-AldiaOperacionGui estado
    }
}

function Connect-AldiaEventosGui {
    $g = $script:AldiaGui
    $c = $g.Controles
    $c.Analizar.Add_Click({ Start-AldiaOperacionGui analizar })
    $c.RevisarSalud.Add_Click({ Start-AldiaOperacionGui salud })
    $c.Todas.Add_Click({ Set-AldiaSeleccionGui $true })
    $c.Ninguna.Add_Click({ Set-AldiaSeleccionGui $false })
    $c.Actualizar.Add_Click({
        $trabajos = @(Get-AldiaTrabajosGui $script:AldiaGui.Modelo)
        if ($trabajos.Count) { Start-AldiaOperacionGui instalar $trabajos }
    })
    $c.Reiniciar.Add_Click({
        $g = $script:AldiaGui
        if ([Windows.MessageBox]::Show($g.Ventana,'¿Reiniciar ahora? Guarda primero tus archivos abiertos.','Al Día','YesNo','Question','No') -eq 'Yes') {
            Start-AldiaOperacionGui reiniciar
        }
    })
    $c.ActivarProteccion.Add_Click({
        Start-AldiaAccionSaludGui @{ Id='restauracion' } proteger
    })
    $c.GuardarInforme.Add_Click({ Request-AldiaInformeGui })
    $c.EnlaceNvd.Add_Click({ Open-AldiaUrlGui 'https://nvd.nist.gov/developers/request-an-api-key' })
    $c.Guardar.Add_Click({
        $c = $script:AldiaGui.Controles
        Start-AldiaOperacionGui guardar @{
            Hora=$c.Hora.Text; ClaveNvd=$c.ClaveNvd.Password; Activa=[bool]$c.Automatica.IsChecked
            Fuentes=@{ windows=[bool]$c.FuenteWindows.IsChecked; drivers=[bool]$c.FuenteDrivers.IsChecked
                apps=[bool]$c.FuenteApps.IsChecked; npm=[bool]$c.FuenteNpm.IsChecked; office=[bool]$c.FuenteOffice.IsChecked; store=[bool]$c.FuenteStore.IsChecked }
        }
    })
    $c.Historial.Add_SelectionChanged({ Request-AldiaDetalleHistorialGui })
    $c.DetalleHistorial.AddHandler([Windows.Controls.Button]::ClickEvent, [Windows.RoutedEventHandler]{
        param($sender,$e)
        if ($e.Source -is [Windows.Controls.Button] -and $e.Source.Tag) { Invoke-AldiaBotonHistorialGui $e.Source }
    })
    $g.Ventana.Add_Closing({
        param($sender,$e)
        $g = $script:AldiaGui
        if ($g.Pendiente) {
            $e.Cancel = $true
            $g.SiguienteOperacion = $null
            if ($g.Operacion -in 'instalar','fabricante','guardar','reiniciar','proteger','accionSalud','adoptar','deshacer','desfijar') {
                $g.PreguntandoCierre = $true
                try {
                    if ([Windows.MessageBox]::Show($g.Ventana,'Hay una operación en curso. ¿Cerrar la ventana cuando termine?','Al Día','YesNo','Question','No') -ne 'Yes') { return }
                } finally { $g.PreguntandoCierre = $false }
            }
            if ($g.Pendiente) {
                $g.CerrarAlTerminar = $true
                $g.Controles.Fase.Text = 'La ventana se cerrará cuando termine la operación.'
            } else { $e.Cancel = $false }
        }
    })
}

function Initialize-AldiaGui {
    param([switch]$Demo)
    $ventana = New-AldiaVentanaGui
    $controles = @{}
    foreach ($nombre in $script:AldiaNombresGui) { $controles[$nombre] = $ventana.FindName($nombre) }
    $runspace = [runspacefactory]::CreateRunspace()
    $runspace.ApartmentState = 'STA'
    $runspace.ThreadOptions = 'ReuseThread'
    $runspace.Open()
    $pipeline = [powershell]::Create()
    $pipeline.Runspace = $runspace
    $script:AldiaGui = @{
        Ventana=$ventana; Controles=$controles; Pipeline=$pipeline
        Manifiesto=Join-Path (Split-Path $PSScriptRoot) 'Aldia.psd1'
        Cola=[Collections.Concurrent.ConcurrentQueue[object]]::new()
        SeleccionHistorial=$null; ConsultaHistorial=$null; Estado=@{ ConfigDemo=$null; ActivaDemo=$true; HistorialDemo=@(); ProteccionDemo=$false; CambiosSaludDemo=@{} }
        Demo=[bool]$Demo; Modelo=@(); Vistas=@{}; ConfigLista=$false; ResultadosSalud=@{}
    }
    if ($Demo) { $controles.Demo.Visibility = 'Visible' }
    Connect-AldiaEventosGui
    if (!$Demo -and !(Test-AldiaCuentaAdmin)) { $controles.CuentaEstandar.Visibility = 'Visible' }
    Update-AldiaControlesGui
}

function Close-AldiaGui {
    $g = $script:AldiaGui
    $runspace = $g.Pipeline.Runspace
    $g.Pipeline.Dispose()
    $runspace.Dispose()
    $script:AldiaGui = $null
}

function Show-AldiaGui {
    param([switch]$Demo)
    Initialize-AldiaGui -Demo:$Demo
    $timer = [Windows.Threading.DispatcherTimer]::new()
    $timer.Interval = [timespan]::FromMilliseconds(120)
    try {
        $timer.Add_Tick({
            try { Update-AldiaVentanaGui }
            catch { Add-AldiaAvisoGui $_.Exception.Message }
        })
        Start-AldiaOperacionGui analizar
        $timer.Start()
        $null = $script:AldiaGui.Ventana.ShowDialog()
    } finally {
        $timer.Stop()
        Close-AldiaGui
    }
}