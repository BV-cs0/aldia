function Get-AldiaHardwareDemo {
    [pscustomobject]@{
        Discos=@(
            [pscustomobject]@{ Nombre='Disco principal'; Tipo='SSD NVMe'; Tamano=512GB; Vida=96; Temperatura=35; Estado='bien'; Detalle='En buen estado.'
                Unidades=@([pscustomobject]@{Letra='C'; Libre=150GB}) }
            [pscustomobject]@{ Nombre='Disco de archivos'; Tipo='SSD SATA'; Tamano=256GB; Vida=24; Temperatura=37; Estado='aviso'
                Detalle='Se está desgastando: piensa en cambiarlo.'; Unidades=@([pscustomobject]@{Letra='D'; Libre=50GB}) }
        )
        Baterias=@([pscustomobject]@{ Nombre='Batería'; Salud=72; Estado='aviso'; Ciclos=380; Quimica='Litio'; Detalle='Dura menos que nueva.' })
        Memoria=@{ Detalle='16 GB · 2 módulos · 5200 MT/s' }
        Estabilidad=@{ Estado='bien'; Detalle='0 apagados inesperados · 0 pantallazos azules · 0 errores de hardware' }
    }
}

function Add-AldiaTarjetaHardwareGui {
    param($Panel,$Titulo,$Detalle,$Estado,$Grande,$Disco)
    $tarjeta = [Windows.Controls.StackPanel]::new()
    $nombre = New-AldiaTextoGui $Titulo -Negrita
    if ($Estado) { $nombre.Foreground = $script:AldiaColoresHardware[$Estado] }
    $null = $tarjeta.Children.Add($nombre)
    if ($Grande) {
        $destacado = New-AldiaTextoGui $Grande -Negrita
        $destacado.FontSize = 24
        $destacado.Foreground = $script:AldiaColoresHardware[$Estado]
        $null = $tarjeta.Children.Add($destacado)
    }
    $null = $tarjeta.Children.Add((New-AldiaTextoGui $Detalle))
    foreach ($unidad in $Disco.Unidades) {
        $fila = [Windows.Controls.StackPanel]::new()
        $fila.Orientation = 'Horizontal'
        $null = $fila.Children.Add((New-AldiaTextoGui (Format-AldiaUnidadHardware $unidad)))
        $boton = New-AldiaBotonGui 'Probar velocidad' $unidad.Letra {
            param($sender,$e)
            $g = $script:AldiaGui
            if ($g.Operacion -or $g.Ocupado) { return }
            $g.ControlVelocidad = [hashtable]::Synchronized(@{ Cancelar=$false })
            Start-AldiaOperacionGui velocidadHardware @{ Unidad=$sender.Tag; Control=$g.ControlVelocidad }
        }
        $null = $fila.Children.Add($boton)
        $null = $tarjeta.Children.Add($fila)
    }
    New-AldiaTarjetaGui $Panel $tarjeta
}

$script:AldiaColoresHardware = @{ bien='#186532'; aviso='#804B00'; mal='#A52121'; desconocido='#48596B' }

function Show-AldiaHardwareGui {
    param($Hardware)
    $g = $script:AldiaGui
    $g.HardwareCargado = $true
    $alerta = Get-AldiaAlertaDisco $Hardware.Discos
    if ($g.ResultadosSalud -and ($alerta -or $g.ResultadosSalud.ContainsKey('discoDanado'))) {
        $g.ResultadosSalud.Remove('discoDanado')
        Show-AldiaSaludGui @($alerta | Where-Object { $_ })
    }
    $c = $g.Controles
    $panel = $c.TarjetasHardware
    $panel.Children.Clear()
    $estado,$resumen = Get-AldiaResumenHardware $Hardware
    $c.ResumenHardware.Text = "● $resumen"
    $c.ResumenHardware.Foreground = $script:AldiaColoresHardware[$estado]
    $c.DetallesHardware.Visibility = if ($Hardware.Virtual -or $g.Demo -or (Test-AldiaAdmin)) { 'Collapsed' } else { 'Visible' }
    $c.FechaHardware.Text = $Hardware.FechaDatos
    if ($Hardware.Virtual) {
        $null = $panel.Children.Add((New-AldiaTextoGui $script:AldiaTextoVirtualHardware))
    } else {
        if (!$Hardware.Discos.Count) { Add-AldiaTarjetaHardwareGui $panel 'Discos' 'Windows no pudo leer los discos.' desconocido }
        foreach ($d in $Hardware.Discos) {
            $vida = if ($null -ne $d.Vida) { "$($d.Vida) % de vida restante" }
            Add-AldiaTarjetaHardwareGui $panel "Disco · $($d.Nombre)" (Format-AldiaDiscoHardware $d -SinVida) $d.Estado $vida $d
        }
        $i = 0
        foreach ($b in $Hardware.Baterias) {
            $i++
            Add-AldiaTarjetaHardwareGui $panel "Batería $i" (Format-AldiaBateriaHardware $b) $b.Estado
        }
        Add-AldiaTarjetaHardwareGui $panel 'Memoria' $Hardware.Memoria.Detalle
    }
    Add-AldiaTarjetaHardwareGui $panel 'Estabilidad (30 días)' $Hardware.Estabilidad.Detalle $Hardware.Estabilidad.Estado
    foreach ($v in $g.Estado.VelocidadHardware.Values) { Add-AldiaTarjetaHardwareGui $panel 'Velocidad del disco' $v.Detalle }
}

function Initialize-AldiaHardwareGui {
    $c = $script:AldiaGui.Controles
    if (!$script:AldiaGui.Demo -and !(Test-AldiaCuentaAdmin)) {
        $c.DetallesHardware.Content = 'Ver detalles (pide la contraseña de un administrador)'
    }
    $c.PestanaHardware.AddHandler([Windows.Controls.Primitives.Selector]::SelectedEvent, [Windows.RoutedEventHandler]{
        $g = $script:AldiaGui
        if ($g.Controles.PestanaHardware.IsSelected -and !$g.HardwareCargado -and (!$g.Pendiente -or $g.Operacion -in 'seguridad',$null)) {
            $g.HardwareCargado = $true
            Start-AldiaOperacionGui hardware
        }
    })
    $c.DetallesHardware.Add_Click({ Start-AldiaOperacionGui detallesHardware })
    $c.CancelarVelocidad.Add_Click({
        $script:AldiaGui.ControlVelocidad.Cancelar = $true
        $script:AldiaGui.Controles.CancelarVelocidad.IsEnabled = $false
    })
}

function Invoke-AldiaHardwareTrabajoGui {
    param($Operacion,$Datos,[bool]$Demo,$Config,$Estado)
    switch ($Operacion) {
        'detallesHardware' {
            if (!$Demo -and !(Test-AldiaAdmin)) {
                $programa = Get-AldiaProgramFiles
                $entrada = Join-Path $programa 'aldia.ps1'
                if (Test-Path -LiteralPath $entrada) {
                    Assert-AldiaPermisos $programa
                    Assert-AldiaPermisos $entrada
                } else {
                    $entrada = Join-Path (Split-Path $PSScriptRoot) 'aldia.ps1'
                }
                $ps = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
                $r = Invoke-AldiaComando $ps @('-NoProfile','-ExecutionPolicy','Bypass','-File',$entrada,'diagnostico','--guardar') -Elevar -Oculto -Timeout 120
                if ($r.Timeout -or $r.Codigo -ne 0) { throw 'No se pudieron guardar los detalles del disco.' }
            }
        }
        'velocidadHardware' {
            if (!$Estado.VelocidadHardware) { $Estado.VelocidadHardware = @{} }
            try {
                $r = if ($Demo) { [pscustomobject]@{ Detalle=('{0}: · Escritura 1210 MB/s · Lectura 1900 MB/s (ejemplo)' -f $Datos.Unidad) } }
                else {
                    Test-AldiaVelocidadDisco $Datos.Unidad -Config $Config -Hardware $Estado.HardwareInforme -Control $Datos.Control -Progreso {
                        param($Porcentaje)
                        Send-AldiaEventoGui progresoHardware $Porcentaje
                    }
                }
                $Estado.VelocidadHardware[$Datos.Unidad] = $r
                Send-AldiaEventoGui fase $r.Detalle
            } catch [OperationCanceledException] { Send-AldiaEventoGui fase 'Prueba cancelada.' }
            Send-AldiaEventoGui hardware $Estado.HardwareInforme
            return
        }
    }
    $Estado.HardwareInforme = if ($Demo) { Get-AldiaHardwareDemo } else { Get-AldiaHardware }
    Send-AldiaEventoGui hardware $Estado.HardwareInforme
}
