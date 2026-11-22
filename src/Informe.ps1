function Get-AldiaRutaInforme {
    $escritorio = [Environment]::GetFolderPath('DesktopDirectory')
    if (!$escritorio -or !(Test-Path -LiteralPath $escritorio -PathType Container)) { $escritorio = (Get-Location).Path }
    Join-Path $escritorio ('Informe Al Día {0:yyyy-MM-dd}.html' -f (Get-Date))
}

function ConvertTo-AldiaTextoInforme {
    param([string]$Texto, [string[]]$Privados)
    foreach ($valor in $Privados | Where-Object { $_ } | Sort-Object Length -Descending -Unique) {
        $Texto = $Texto -replace ('(?<![\p{L}\p{N}])' + [regex]::Escape($valor) + '(?![\p{L}\p{N}])'),'…'
    }
    $Texto = $Texto -replace '(?i)([A-Z]:\\Users\\)[^\\/\s]+','$1…'
    $Texto = $Texto -replace '(?i)\b(?:[A-Z0-9]{5}-){4}[A-Z0-9]{5}\b','…'
    [Net.WebUtility]::HtmlEncode($Texto)
}

function Get-AldiaDireccionesPrivadas {
    try {
        foreach ($ip in Get-CimInstance Win32_NetworkAdapterConfiguration -Filter 'IPEnabled = TRUE' -ErrorAction Stop) {
            @($ip.IPAddress) | Where-Object { $_ } | ForEach-Object { ($_ -split '%')[0] }
            if ($ip.MACAddress) { $ip.MACAddress; $ip.MACAddress -replace ':','-' }
        }
    } catch { Write-AldiaLog "No se pudieron leer las direcciones de red para ocultarlas: $($_.Exception.Message)" }
}

function Get-AldiaDatosEquipoInforme {
    $pc = Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue
    $cpu = Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue
    $disco = try { Get-AldiaDiscoSalud } catch {}
    $windows = Get-AldiaVersionWindows
    $producto = if ([int]$windows.CurrentBuildNumber -ge 22000) { 'Windows 11' } else { 'Windows 10' }
    [ordered]@{
        Fabricante=if ($pc.Manufacturer) { $pc.Manufacturer } else { 'No disponible' }
        Modelo=if ($pc.Model) { $pc.Model } else { 'No disponible' }
        Windows="$producto $($windows.EditionID) $($windows.DisplayVersion) (compilación $($windows.CurrentBuildNumber))"
        Procesador=if ($cpu.Name) { $cpu.Name -join ', ' } else { 'No disponible' }
        RAM=if ($pc.TotalPhysicalMemory) { '{0:N1} GB' -f ($pc.TotalPhysicalMemory / 1GB) } else { 'No disponible' }
        'Disco libre'=('{0:N1} GB' -f ($disco.FreeSpace / 1GB))
        Arquitectura=($env:PROCESSOR_ARCHITEW6432,$env:PROCESSOR_ARCHITECTURE | Where-Object { $_ } | Select-Object -First 1)
        'Máquina virtual'=if (!$pc) { 'No se pudo comprobar' } elseif (Test-AldiaMaquinaVirtual $pc) { 'Sí' } else { 'No' }
    }
}

function Get-AldiaRevisionInforme {
    param($Config, [bool]$Internet)
    $filas = @(foreach ($fuente in 'pnp','windows','drivers','apps','npm','office','store') {
        if ($fuente -ne 'pnp' -and !$Config.fuentes.$fuente) { continue }
        if (!$Internet -and $fuente -notin 'pnp','office') { continue }
        try {
            $items = switch ($fuente) {
                pnp { Get-AldiaProblemasPnP }
                windows { Find-AldiaActualizacionesWU (New-AldiaSesionWU) Software }
                drivers { Get-AldiaDriversWU (New-AldiaSesionWU) $Config }
                apps { Get-AldiaApps $Config }
                npm { Get-AldiaNpm }
                office { Get-AldiaOffice }
                store { Get-AldiaStore }
            }
            foreach ($item in $items) { ConvertTo-AldiaFilaGui $fuente $item $Config }
        } catch {}
    })
    $filas
}

function Save-AldiaInforme {
    param($Config, [string]$Ruta, [string]$HistorialRuta, $Datos, [switch]$SoloCache)
    if (!$Ruta) { $Ruta = Get-AldiaRutaInforme }
    $soloCacheInforme = [bool]$SoloCache
    if (!$Datos) {
        $internet = if ($null -ne $internetCli) { $internetCli } else { Test-AldiaInternet }
        $filas = @(Get-AldiaRevisionInforme $Config $internet)
        $seguridad = if ($Config.vulnerabilidades.activado -and $internet) {
            Get-AldiaVulnerabilidades $Config -Pendientes @($filas | Where-Object Fuente -eq apps | ForEach-Object Paquete)
        }
        $Datos = @{
            Equipo=Get-AldiaDatosEquipoInforme; Filas=$filas; Salud=@(Get-AldiaSalud)
            Seguridad=$seguridad; Historial=@(Read-AldiaHistorial $HistorialRuta | Select-Object -Last 10)
            Aviso=if (!$internet) { 'Sin conexión. Solo se pudieron comprobar algunos datos del PC.' }
        }
    }
    # IP y MAC reales de este PC (no por patrón: un patrón de IP también borraría versiones como 3.10.8.0).
    $privados = @($env:USERNAME,$env:COMPUTERNAME,$Config.vulnerabilidades.nvdApiKey) + @(Get-AldiaDireccionesPrivadas)
    $bios = Get-CimInstance Win32_BIOS -ErrorAction SilentlyContinue
    if ($bios.SerialNumber -and $bios.SerialNumber -ne '0') { $privados += $bios.SerialNumber }
    $fallos = @($Datos.Seguridad.Programas | Where-Object { $_.Nivel -gt 0 -and !$_.Dudoso })
    $rojas = @($Datos.Salud | Where-Object Estado -eq mal)
    $pnp = @($Datos.Filas | Where-Object Fuente -eq pnp)
    $pendientes = @($Datos.Filas | Where-Object { $_.Fuente -notin 'pnp','office','store' })
    $color = if ($rojas.Count -or $fallos.Count) { 'mal' } elseif ($pnp.Count -or $pendientes.Count -or $Datos.Aviso) { 'aviso' } else { 'bien' }
    $b = [Text.StringBuilder]::new()
    [void]$b.AppendLine('<!doctype html><html lang="es"><meta charset="utf-8"><title>Informe de Al Día</title><style>body{font:16px system-ui,sans-serif;max-width:60rem;margin:2rem auto;padding:0 1rem;color:#172b43}h2{border-bottom:1px solid #bbb}li{margin:.35rem 0}section{break-inside:avoid}.mal{color:#a52121}.aviso{color:#804b00}.bien{color:#186532}@media print{body{margin:0}}</style><h1>Informe de Al Día</h1>')
    [void]$b.AppendLine("<p>Generado el $((Get-Date).ToString('dd/MM/yyyy HH:mm')).</p>")
    [void]$b.AppendLine("<p class='$color'>Actualizaciones pendientes: $($pendientes.Count) · Dispositivos con problemas: $($pnp.Count) · Programas con fallos de seguridad: $($fallos.Count) · Comprobaciones en rojo: $($rojas.Count)</p>")
    $secciones = [ordered]@{
        Equipo=@(foreach ($k in $Datos.Equipo.Keys) { "$k · $($Datos.Equipo[$k])" })
        'Actualizaciones'= @($Datos.Filas | Where-Object Fuente -ne pnp | ForEach-Object { "$($_.Nombre) · $($_.Detalle)" })
        'Dispositivos con problemas'=@($pnp | ForEach-Object { "$($_.Nombre) · $($_.Motivo)" })
        'Seguridad de los programas'=@($fallos | ForEach-Object { "$($_.Nombre) · $($_.Version) · $($_.Detalle)"; if ($_.Explotado) { '⚠ Ya se está aprovechando este fallo (KEV).' } })
        'Salud del PC'=@($Datos.Salud | ForEach-Object { "$($_.Nombre) · $($_.Estado) · $($_.Detalle)" })
        'Últimas ejecuciones'=@($Datos.Historial | Sort-Object Inicio -Descending | Select-Object -First 10 | ForEach-Object {
            $fin = try { ([datetime]$_.Fin).ToString('dd/MM/yyyy HH:mm') } catch { $_.Fin }
            "$fin · $($_.Modo) · código $($_.Codigo)"
            $_.Resultados | ForEach-Object { $nombre = if ($_.Titulo) { $_.Titulo } else { $_.Id }; "$($_.Fuente) · $nombre · $($_.Estado)" }
        })
    }
    foreach ($aviso in @($Datos.Aviso) + @($Datos.Seguridad.Avisos)) {
        if ($aviso) { [void]$b.AppendLine("<p>$(ConvertTo-AldiaTextoInforme $aviso $privados)</p>") }
    }
    foreach ($titulo in $secciones.Keys) {
        [void]$b.AppendLine("<section><h2>$(ConvertTo-AldiaTextoInforme $titulo)</h2><ul>")
        foreach ($linea in $secciones[$titulo]) { [void]$b.AppendLine("<li>$(ConvertTo-AldiaTextoInforme $linea $privados)</li>") }
        [void]$b.AppendLine('</ul></section>')
    }
    [void]$b.AppendLine('</html>')
    $rutaCompleta = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Ruta)
    [IO.File]::WriteAllText($rutaCompleta,$b.ToString(),[Text.UTF8Encoding]::new($true))
    $rutaCompleta
}