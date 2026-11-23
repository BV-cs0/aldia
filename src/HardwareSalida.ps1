$script:AldiaTextoVirtualHardware = 'Máquina virtual: el hardware lo simula el programa de virtualización.'

function Format-AldiaUnidadHardware {
    param($Unidad)
    if ($null -eq $Unidad.Libre) { return ('{0}: · Espacio libre sin datos' -f $Unidad.Letra) }
    '{0}: · {1:N1} GB libres' -f $Unidad.Letra,($Unidad.Libre / 1GB)
}

function Format-AldiaDiscoHardware {
    param($Disco,[switch]$SinVida)
    $partes = @($Disco.Tipo)
    if ($Disco.Tamano) { $partes += ('{0:N0} GB' -f ($Disco.Tamano / 1GB)) }
    if ($null -ne $Disco.Temperatura) { $partes += "$($Disco.Temperatura) °C" }
    if (!$SinVida -and $null -ne $Disco.Vida) { $partes += "$($Disco.Vida) % de vida restante" }
    if ($null -ne $Disco.Horas) {
        $tiempo = '{0:N0} h' -f $Disco.Horas
        if ($Disco.Horas -ge 8760) { $tiempo += ' · {0:N1} años' -f ($Disco.Horas / 8760) }
        elseif ($Disco.Horas -ge 720) { $tiempo += ' · {0:N0} meses' -f [math]::Floor($Disco.Horas / 720) }
        elseif ($Disco.Horas -ge 24) { $tiempo += ' · {0:N0} días' -f [math]::Floor($Disco.Horas / 24) }
        $partes += $tiempo
    }
    if ($null -ne $Disco.Errores) { $partes += "$($Disco.Errores) errores sin corregir" }
    ($partes + $Disco.Detalle) -join ' · '
}

function Format-AldiaBateriaHardware {
    param($Bateria)
    $partes = @($Bateria.Detalle)
    if ($null -ne $Bateria.Salud -and $Bateria.Estado -ne 'bien') { $partes += ('{0:N1} % de capacidad' -f $Bateria.Salud) }
    if ($null -ne $Bateria.Ciclos) { $partes += "$($Bateria.Ciclos) ciclos de carga" }
    if ($Bateria.Quimica) { $partes += $Bateria.Quimica }
    $partes -join ' · '
}

function Get-AldiaFilasHardwareInforme {
    param($Hardware, $Velocidad)
    if (!$Hardware) { return }
    if ($Hardware.Virtual) { $script:AldiaTextoVirtualHardware }
    else {
        if (!$Hardware.Discos.Count) { 'Discos · Windows no pudo leer los discos.' }
        $i = 0
        foreach ($d in $Hardware.Discos) {
            $i++
            # Usar un nombre genérico: algunos controladores incluyen el número de serie en el nombre.
            "Disco $i · $(Format-AldiaDiscoHardware $d)"
            foreach ($u in $d.Unidades) { Format-AldiaUnidadHardware $u }
        }
        foreach ($b in $Hardware.Baterias) { "Batería · $(Format-AldiaBateriaHardware $b)" }
        "Memoria · $($Hardware.Memoria.Detalle)"
    }
    "Estabilidad (30 días) · $($Hardware.Estabilidad.Detalle)"
    foreach ($v in $Velocidad) { "Velocidad · $($v.Detalle)" }
}

function Show-AldiaHardwareCli {
    param($Hardware)
    $estado,$resumen = Get-AldiaResumenHardware $Hardware
    $color = @{ bien='Green'; aviso='Yellow'; mal='Red'; desconocido='Gray' }
    Write-Host $resumen -ForegroundColor $color[$estado]
    if ($Hardware.FechaDatos) { Write-Host $Hardware.FechaDatos }
    if ($Hardware.Virtual) { Write-Host $script:AldiaTextoVirtualHardware }
    else {
        if (!$Hardware.Discos.Count) { Write-Host 'Windows no pudo leer los discos.' }
        $discos = foreach ($d in $Hardware.Discos) {
            [pscustomobject]@{ Nombre=$d.Nombre; Tipo=$d.Tipo; Estado=$d.Estado }
        }
        Show-AldiaTabla 'Discos' @($discos) ([ordered]@{ Nombre=34; Tipo=25; Estado=12 })
        foreach ($d in $Hardware.Discos) {
            Write-Host "$($d.Nombre) · $(Format-AldiaDiscoHardware $d)"
            foreach ($u in $d.Unidades) { Write-Host "  $(Format-AldiaUnidadHardware $u)" }
        }
        $i = 0
        $baterias = foreach ($b in $Hardware.Baterias) {
            $i++
            [pscustomobject]@{ Bateria=$i; Estado=$b.Estado; Detalle=Format-AldiaBateriaHardware $b }
        }
        if ($i) { Show-AldiaTabla 'Batería' @($baterias) ([ordered]@{ Bateria=8; Estado=12; Detalle=65 }) }
        Show-AldiaTabla 'Memoria' @($Hardware.Memoria) ([ordered]@{ Detalle=100 })
    }
    Show-AldiaTabla 'Estabilidad (30 días)' @($Hardware.Estabilidad) ([ordered]@{ Estado=12; Detalle=100 })
}
