function Get-AldiaDiscosFisicos { Get-PhysicalDisk -ErrorAction Stop }
function Get-AldiaDiscosWindows { Get-Disk -ErrorAction Stop }

function Get-AldiaContadoresDisco {
    param($Disco)
    Get-StorageReliabilityCounter -PhysicalDisk $Disco -ErrorAction Stop
}

function Get-AldiaParticionesDisco {
    param($Numero)
    Get-Partition -DiskNumber $Numero -ErrorAction Stop
}

function Get-AldiaVolumenDisco {
    param($Letra)
    Get-Volume -DriveLetter $Letra -ErrorAction Stop
}

function Get-AldiaTipoDisco {
    param($Disco)
    switch -Regex ([string]$Disco.BusType) {
        '^(USB|7)$' { return 'USB' }
        '^(SD|MMC|12|13)$' { return 'Memoria interna (eMMC)' }
        '^(NVMe|17)$' { return 'SSD NVMe' }
    }
    if ($Disco.MediaType -in 'HDD',3 -or $Disco.SpindleSpeed -gt 0) { return 'Disco duro' }
    if ($Disco.MediaType -in 'SSD',4 -or ($null -ne $Disco.SpindleSpeed -and $Disco.SpindleSpeed -eq 0)) {
        if ($Disco.BusType -in 'SATA','ATA',11,3) { return 'SSD SATA' }
        return 'SSD'
    }
    'Disco'
}

function Get-AldiaEstadoDisco {
    param($Salud, $Operacion, $Prediccion, $Errores, $Vida, $Temperatura, $Tipo, [switch]$Raid)
    if ($Prediccion -or $Errores -gt 0 -or ($null -ne $Vida -and $Vida -le 10) -or ($Salud -in 'Unhealthy',2 -and !$Raid)) {
        return 'mal','Este disco puede fallar pronto. Copia tus archivos importantes ya.'
    }
    if ($Raid) { return 'desconocido','Este disco está detrás de un controlador RAID: Windows no da su salud.' }
    if ($null -ne $Vida -and $Vida -le 30) { return 'aviso','Se está desgastando: piensa en cambiarlo.' }
    if (($Tipo -like 'SSD*' -and $Temperatura -ge 70) -or ($Tipo -eq 'Disco duro' -and $Temperatura -ge 55)) {
        return 'aviso','Está muy caliente.'
    }
    if ($Salud -in 'Warning',1 -or @($Operacion | Where-Object { $_ -and $_ -notin 'OK',2 }).Count) {
        return 'aviso','Windows ha detectado un problema con este disco.'
    }
    if ($Salud -in 'Healthy',0) { return 'bien','En buen estado.' }
    'desconocido','Windows no pudo comprobar el estado.'
}

function Get-AldiaRutaHardware {
    Join-Path (Join-Path $env:ProgramData Aldia) hardware.json
}

function Get-AldiaCacheHardware {
    param([string]$Ruta = (Get-AldiaRutaHardware), [datetime]$Ahora = (Get-Date))
    try {
        Assert-AldiaRutaNormal $Ruta
        $cache = [IO.File]::ReadAllText($Ruta) | ConvertFrom-Json -ErrorAction Stop
        if ($cache.Version -ne 1) { return }
        $edad = $Ahora.ToUniversalTime() - [datetime]::Parse($cache.Fecha,[cultureinfo]::InvariantCulture).ToUniversalTime()
        if ($edad.TotalSeconds -lt 0) { return }
        $texto = if ($edad.TotalHours -lt 1) { 'Datos de hace menos de una hora' } else { 'Datos de hace {0} h' -f [math]::Floor($edad.TotalHours) }
        if ($edad.TotalDays -gt 7) { $texto += ' (más de 7 días)' }
        [pscustomobject]@{ Discos=$cache.Discos; Antiguo=($edad.TotalDays -gt 7); Texto=$texto }
    } catch {}
}

function Find-AldiaDiscoWindows {
    param($Disco, $DiscosWindows, $DiscosFisicos)
    $id = ([string]$Disco.UniqueId).Trim()
    if ($id -and $id -notmatch '^0+$') {
        $coinciden = @($DiscosWindows | Where-Object { ([string]$_.UniqueId).Trim() -eq $id })
        $fisicos = @($DiscosFisicos | Where-Object { ([string]$_.UniqueId).Trim() -eq $id })
        if ($coinciden.Count -eq 1 -and $fisicos.Count -eq 1) { return $coinciden[0] }
    }
    $serie = ([string]$Disco.SerialNumber).Trim()
    if ($serie -and $serie -notmatch '^0+$|^Unknown$|^None$') {
        $coinciden = @($DiscosWindows | Where-Object { ([string]$_.SerialNumber).Trim() -eq $serie })
        $fisicos = @($DiscosFisicos | Where-Object { ([string]$_.SerialNumber).Trim() -eq $serie })
        if ($coinciden.Count -eq 1 -and $fisicos.Count -eq 1) { $coinciden[0] }
    }
}

function Get-AldiaIdentidadDisco {
    param($Disco)
    if ($Disco.UniqueId) { return [string]$Disco.UniqueId }
    if ($Disco.ObjectId) { return [string]$Disco.ObjectId }
}

function Get-AldiaDetalleDiscos {
    param($Discos, $DiscosWindows)
    $predicciones = @(try { Get-CimInstance -Namespace root/wmi -ClassName MSStorageDriver_FailurePredictStatus -ErrorAction Stop } catch {})
    $pnp = @(if ($predicciones.Count) { try { Get-CimInstance Win32_DiskDrive -ErrorAction Stop } catch {} })
    foreach ($disco in $Discos) {
        $r = try { Get-AldiaContadoresDisco $disco } catch {}
        $windows = Find-AldiaDiscoWindows $disco $DiscosWindows $Discos
        $idPnp = if ($windows) { ($pnp | Where-Object Index -eq $windows.Number).PNPDeviceID }
        $fallo = $false
        if ($idPnp -is [string] -and $idPnp) {
            $patron = '^{0}(?:_\d+)?$' -f [regex]::Escape($idPnp)
            $pred = @($predicciones | Where-Object InstanceName -match $patron)
            $fallo = $pred.Count -eq 1 -and $pred[0].PredictFailure -eq $true
        }
        $vida = $null
        if ($null -ne $r.Wear -and ($r.Wear -gt 0 -or (Get-AldiaTipoDisco $disco) -like 'SSD*') -and $r.Wear -le 100) {
            $vida = 100 - $r.Wear
        }
        $errores = if ($null -ne $r.ReadErrorsUncorrected -or $null -ne $r.WriteErrorsUncorrected) {
            [decimal]$r.ReadErrorsUncorrected + [decimal]$r.WriteErrorsUncorrected
        }
        [pscustomobject]@{
            Id=Get-AldiaIdentidadDisco $disco; Prediccion=$fallo; Vida=$vida; Errores=$errores
            Temperatura=if ($r.Temperature -gt 0) { $r.Temperature }; Horas=$r.PowerOnHours
        }
    }
}

function Save-AldiaHardware {
    param([string]$Ruta = (Get-AldiaRutaHardware))
    if (!(Test-AldiaAdmin)) { throw 'Para guardar los detalles hace falta permiso de administrador.' }
    $dir = Split-Path $Ruta
    New-AldiaDirectorioProtegido $dir
    Assert-AldiaRutaNormal $Ruta
    if ([IO.File]::Exists($Ruta)) { Assert-AldiaPermisos $Ruta }
    $lista = @(Get-AldiaDiscosFisicos)
    if (!$lista.Count) { throw 'Windows no encontró discos para guardar.' }
    $windows = @(try { Get-AldiaDiscosWindows } catch {})
    $cache = @{ Version=1; Fecha=[datetime]::UtcNow.ToString('o'); Discos=@(Get-AldiaDetalleDiscos $lista $windows) }
    $temp = Join-Path $dir ('hardware-{0}.tmp' -f [guid]::NewGuid())
    try {
        [IO.File]::WriteAllText($temp, ($cache | ConvertTo-Json -Depth 5), [Text.UTF8Encoding]::new($false))
        Set-AldiaPropietarioAdmin $temp
        if ([IO.File]::Exists($Ruta)) { [IO.File]::Replace($temp,$Ruta,[NullString]::Value) }
        else { [IO.File]::Move($temp,$Ruta) }
    } finally { [IO.File]::Delete($temp) }
}

function Get-AldiaDiscos {
    param($Cache)
    $lista = @(try { Get-AldiaDiscosFisicos } catch {})
    $windows = @(try { Get-AldiaDiscosWindows } catch {})
    $admin = Test-AldiaAdmin
    $detalles = if ($admin -and $lista.Count) { Get-AldiaDetalleDiscos $lista $windows } else { $Cache.Discos }
    if (!$lista.Count) {
        $lista = @(foreach ($w in $windows) {
            [pscustomobject]@{ FriendlyName=$w.FriendlyName; BusType=$w.BusType; Size=$w.Size; UniqueId=$w.UniqueId
                HealthStatus=$w.HealthStatus; DiscoWindows=$w }
        })
    }
    foreach ($disco in $lista) {
        $tipo = Get-AldiaTipoDisco $disco
        $nombre = $disco.FriendlyName
        if ($tipo -eq 'USB') { $nombre += ' (USB)' }
        $id = Get-AldiaIdentidadDisco $disco
        $d = @(if ($id -and @($lista | Where-Object { (Get-AldiaIdentidadDisco $_) -eq $id }).Count -eq 1) {
            $detalles | Where-Object Id -eq $id
        })
        $detalle = if ($d.Count -eq 1) { $d[0] }
        $hayDatos = $detalle -and ($detalle.Prediccion -or $null -ne $detalle.Vida -or $null -ne $detalle.Temperatura -or $null -ne $detalle.Horas -or $null -ne $detalle.Errores)
        $raid = !$hayDatos -and ($disco.BusType -in 'RAID','Spaces','Storage Spaces','Virtual','File Backed Virtual',8,14,15,16 -or $nombre -match 'Intel.*(RST|RAID)|Storage Space')
        $estado,$texto = Get-AldiaEstadoDisco $disco.HealthStatus $disco.OperationalStatus $detalle.Prediccion $detalle.Errores $detalle.Vida $detalle.Temperatura $tipo -Raid:$raid
        if (!$hayDatos -and !$raid -and !$admin -and $tipo -ne 'USB') { $texto += ' Para ver temperatura y desgaste pulsa Ver detalles.' }
        $w = if ($disco.DiscoWindows) { $disco.DiscoWindows } else { Find-AldiaDiscoWindows $disco $windows $lista }
        $unidades = @(if ($w) {
            $particiones = @(try { Get-AldiaParticionesDisco $w.Number } catch {})
            foreach ($p in $particiones) {
                if ($p.DriveLetter -notmatch '^[A-Z]$') { continue }
                $v = try { Get-AldiaVolumenDisco $p.DriveLetter } catch {}
                [pscustomobject]@{ Letra=[string]$p.DriveLetter; Libre=$v.SizeRemaining }
            }
        })
        [pscustomobject]@{ Nombre=$nombre; Tipo=$tipo; Tamano=$disco.Size; Estado=$estado; Detalle=$texto
            Vida=$detalle.Vida; Temperatura=$detalle.Temperatura; Horas=$detalle.Horas; Errores=$detalle.Errores; Unidades=$unidades }
    }
}

function ConvertTo-AldiaCapacidadBateria {
    param([string]$Texto)
    # El informe expresa capacidades y ciclos como enteros, con o sin grupos de miles.
    $limpio = $Texto.Trim()
    if ($limpio -match '^\d{1,3}(?:[.,\s]\d{3})+$') { $limpio = $limpio -replace '[.,\s]' }
    $numero = 0L
    if ([long]::TryParse($limpio,[Globalization.NumberStyles]::None,[cultureinfo]::InvariantCulture,[ref]$numero)) { $numero }
}

function ConvertFrom-AldiaBateriaXml {
    param([xml]$Xml)
    foreach ($b in $Xml.SelectNodes("//*[local-name()='Batteries']/*[local-name()='Battery']")) {
        $valores = @{}
        foreach ($nodo in $b.ChildNodes) { $valores[$nodo.LocalName] = $nodo.InnerText }
        $diseno = ConvertTo-AldiaCapacidadBateria $valores.DesignCapacity
        $carga = ConvertTo-AldiaCapacidadBateria $valores.FullChargeCapacity
        $salud = if ($diseno -gt 0 -and $null -ne $carga) { 100.0 * $carga / $diseno }
        $estado,$texto = if ($null -eq $salud) { 'desconocido','Windows no da la capacidad de esta batería.' }
            elseif ($salud -ge 80) { 'bien',('La batería conserva el {0:N0} % de su capacidad.' -f $salud) }
            elseif ($salud -ge 60) { 'aviso','Dura menos que nueva.' }
            else { 'mal','Conviene cambiarla.' }
        [pscustomobject]@{ Estado=$estado; Detalle=$texto; Salud=$salud
            Ciclos=ConvertTo-AldiaCapacidadBateria $valores.CycleCount
            Quimica=if ($valores.Chemistry -in 'LION','LI-I','Li-ion','LiP') { 'Litio' } else { $valores.Chemistry } }
    }
}

function Get-AldiaBateriaSalud {
    $baterias = @(try { Get-CimInstance Win32_Battery -ErrorAction Stop } catch {})
    if (!$baterias.Count) { return }
    $ruta = Join-Path ([IO.Path]::GetTempPath()) ('aldia-bateria-{0}.xml' -f [guid]::NewGuid())
    try {
        $r = Invoke-AldiaComando (Join-Path $env:SystemRoot 'System32\powercfg.exe') @('/batteryreport','/xml','/output',$ruta) -Timeout 25
        if ($r.Codigo -eq 0 -and !$r.Timeout) {
            $xml = [xml]([IO.File]::ReadAllText($ruta))
            $filas = @(ConvertFrom-AldiaBateriaXml $xml)
            if ($filas.Count) { return $filas }
        }
    } catch {}
    finally { try { [IO.File]::Delete($ruta) } catch {} }
    foreach ($b in $baterias) {
        [pscustomobject]@{ Nombre='Batería'; Estado='desconocido'; Detalle='Windows no pudo leer los datos de la batería.' }
    }
}

function Get-AldiaMemoriaHardware {
    $modulos = @(try { Get-CimInstance Win32_PhysicalMemory -ErrorAction Stop } catch {})
    if (!$modulos.Count) { return [pscustomobject]@{ Detalle='Windows no pudo leer la memoria.' } }
    $gb = ($modulos | ForEach-Object { $_.Capacity } | Measure-Object -Sum).Sum / 1GB
    $velocidades = @($modulos.ConfiguredClockSpeed | Where-Object { $_ -gt 0 } | Sort-Object -Unique)
    $texto = '{0:N1} GB · {1}' -f $gb,(Format-AldiaCantidadGui $modulos.Count 'módulo' 'módulos')
    if ($velocidades.Count) { $texto += " · $($velocidades -join ' / ') MT/s" }
    $notas = @($modulos | Where-Object { $_.ConfiguredClockSpeed -gt 0 -and $_.ConfiguredClockSpeed -lt $_.Speed } |
        ForEach-Object { "Funciona a $($_.ConfiguredClockSpeed) de $($_.Speed) MT/s (es normal en muchos portátiles)." } | Select-Object -Unique)
    [pscustomobject]@{ Detalle=(@($texto) + $notas -join ' ') }
}

# Códigos de pantallazo azul (bug check) más habituales agrupados por la pieza que suele causarlos.
$script:AldiaCausasPantallazo = @(
    @{ Grupo='grafica'; Codigos=0x116,0x117,0x119,0x10E,0x113
        Texto='la tarjeta gráfica dejó de responder y Windows no pudo recuperarla'
        Consejo='actualiza el controlador de la tarjeta gráfica y vigila que el PC no se caliente.' }
    @{ Grupo='hardware'; Codigos=0x124,0x101,0x9C
        Texto='falló el propio hardware (procesador, memoria o placa), a veces por calor'
        Consejo='limpia el polvo de las rejillas y vigila la temperatura. Si se repite, que lo revise un técnico.' }
    @{ Grupo='memoria'; Codigos=0x1A,0x50,0x4E,0x12B
        Texto='hubo un error al usar la memoria RAM (a veces lo provoca un controlador)'
        Consejo='comprueba la memoria con «Diagnóstico de memoria de Windows» (mdsched).' }
    @{ Grupo='disco'; Codigos=0x7A,0x7B,0x77,0xF4,0x24
        Texto='Windows no pudo leer el disco a tiempo'
        Consejo='revisa el estado del disco en esta misma pestaña y haz copia de tus archivos.' }
    @{ Grupo='energia'; Codigos=0x9F
        Texto='un controlador falló al suspender o despertar el PC'
        Consejo='instala los controladores del fabricante del PC (chipset y gestión de energía).' }
    @{ Grupo='atasco'; Codigos=0x133
        Texto='un controlador se quedó atascado (a menudo el del disco o el del chipset)'
        Consejo='instala los controladores del fabricante del PC y actualiza el firmware del disco.' }
    @{ Grupo='controlador'; Codigos=0xD1,0x0A,0x3B,0x7E,0x1E,0xC4,0xC5,0xD5,0x19,0xC2,0x139,0xFC
        Texto='falló un controlador'
        Consejo='actualiza los controladores desde la pestaña Escáner.' }
    @{ Grupo='windows'; Codigos=0xEF,0xC000021A
        Texto='se cerró una parte esencial de Windows'
        Consejo='repara los archivos de Windows con «sfc /scannow» en una consola de administrador.' }
)

function Get-AldiaCodigoPantallazo {
    param($Evento)
    # El primer dato del evento 1001 es el código sin traducir: «0x00000116 (0x…, …)».
    $texto = @($Evento.Properties | Select-Object -First 1 | ForEach-Object Value) + @($Evento.Message) -join ' '
    if ($texto -match '0x([0-9A-Fa-f]{1,8})\b') { [uint32]('0x' + $Matches[1]) }
}

function Get-AldiaFabricanteGrafica {
    param($Evento)
    $origen = "$($Evento.ProviderName) $(@($Evento.Properties | ForEach-Object Value) -join ' ')"
    if ($origen -match 'nvlddmkm|nvidia') { 'NVIDIA' }
    elseif ($origen -match 'amdkmdag|amdwddmg|atikmdag|\bamd\b') { 'AMD' }
    elseif ($origen -match 'igdkmd|igfx|intel') { 'Intel' }
}

function Get-AldiaRecuperacionesGrafica {
    param([datetime]$Desde)
    # Cuelgues de la gráfica que Windows sí recuperó (sin pantallazo). Si el proveedor no existe en
    # este PC (otra marca), no es un error: por eso no se suman a los errores de lectura.
    $eventos = @(
        Get-WinEvent -FilterHashtable @{LogName='System'; StartTime=$Desde; ProviderName='Display'; Id=4101} -ErrorAction SilentlyContinue
        Get-WinEvent -FilterHashtable @{LogName='System'; StartTime=$Desde; ProviderName='nvlddmkm'; Id=153} -ErrorAction SilentlyContinue
    ) | Where-Object { $_ }
    # Un mismo cuelgue deja a veces varios eventos seguidos: contar uno por minuto.
    @($eventos | Group-Object { $_.TimeCreated.ToString('yyyyMMddHHmm') } | ForEach-Object { $_.Group[0] })
}

function Get-AldiaCausasPantallazo {
    param($Pantallazos, $Recuperaciones)
    $marcas = @($Recuperaciones | ForEach-Object { Get-AldiaFabricanteGrafica $_ } | Where-Object { $_ } | Sort-Object -Unique)
    $casos = foreach ($evento in $Pantallazos) {
        $codigo = Get-AldiaCodigoPantallazo $evento
        $causa = $script:AldiaCausasPantallazo | Where-Object { $null -ne $codigo -and $_.Codigos -contains $codigo } | Select-Object -First 1
        [pscustomobject]@{ Evento=$evento; Codigo=$codigo; Causa=$causa; Clave=if ($causa) { $causa.Grupo } else { "otro-$codigo" } }
    }
    foreach ($grupo in @($casos | Group-Object Clave | Sort-Object { ($_.Group.Evento.TimeCreated | Measure-Object -Maximum).Maximum } -Descending)) {
        $c = $grupo.Group[0]
        $codigos = (@($grupo.Group | Where-Object { $null -ne $_.Codigo } | ForEach-Object { '0x{0:X}' -f $_.Codigo }) | Select-Object -Unique) -join ', '
        $ultimo = ($grupo.Group.Evento.TimeCreated | Measure-Object -Maximum).Maximum
        $veces = Format-AldiaCantidadGui $grupo.Count 'vez' 'veces'
        $datos = @($veces; "el último el $($ultimo.ToString('dd/MM/yyyy'))"; if ($codigos) { "código $codigos" }) -join ', '
        if ($c.Causa) {
            $texto = $c.Causa.Texto
            if ($c.Causa.Grupo -eq 'grafica' -and $marcas.Count -eq 1) { $texto = $texto -replace '^la tarjeta gráfica', "la tarjeta gráfica ($($marcas[0]))" }
            "Pantallazo azul: $texto ($datos). Qué hacer: $($c.Causa.Consejo)"
        } else {
            "Pantallazo azul por una causa que Al Día no reconoce ($datos). Si se repite, busca ese código o pide ayuda."
        }
    }
}

function Get-AldiaEstabilidad {
    param([datetime]$Ahora = (Get-Date))
    $desde = $Ahora.AddDays(-30)
    $errores = @()
    $apagados = @(Get-WinEvent -FilterHashtable @{LogName='System'; StartTime=$desde; ProviderName='Microsoft-Windows-Kernel-Power'; Id=41} -ErrorAction SilentlyContinue -ErrorVariable +errores)
    $azules = @(Get-WinEvent -FilterHashtable @{LogName='System'; StartTime=$desde; ProviderName='Microsoft-Windows-WER-SystemErrorReporting'; Id=1001} -ErrorAction SilentlyContinue -ErrorVariable +errores)
    $hardware = @(Get-WinEvent -FilterHashtable @{LogName='System'; StartTime=$desde; ProviderName='Microsoft-Windows-WHEA-Logger'} -ErrorAction SilentlyContinue -ErrorVariable +errores)
    $graficas = @(Get-AldiaRecuperacionesGrafica $desde)
    $causas = @(Get-AldiaCausasPantallazo $azules $graficas)
    $ultimo = (@($apagados + $azules + $hardware) | Sort-Object TimeCreated -Descending | Select-Object -First 1).TimeCreated
    $texto = @(
        Format-AldiaCantidadGui $apagados.Count 'apagado inesperado' 'apagados inesperados'
        Format-AldiaCantidadGui $azules.Count 'pantallazo azul' 'pantallazos azules'
        Format-AldiaCantidadGui $hardware.Count 'error de hardware' 'errores de hardware'
    ) -join ' · '
    if ($graficas.Count) {
        $texto += ' · ' + (Format-AldiaCantidadGui $graficas.Count 'cuelgue de la gráfica' 'cuelgues de la gráfica') + ' (Windows la recuperó)'
        if (!$azules.Count -and $graficas.Count -ge 3) {
            $causas += 'La tarjeta gráfica se cuelga a menudo aunque Windows la recupera. Qué hacer: actualiza su controlador y vigila que el PC no se caliente.'
        }
    }
    $estado = 'bien'
    if ($apagados.Count -ge 3 -or $azules.Count -or $hardware.Count -or $graficas.Count -ge 3) {
        $estado = 'aviso'
        if ($ultimo) { $texto += " · Último: $($ultimo.ToString('g'))" }
    } elseif (@($errores | Where-Object FullyQualifiedErrorId -notlike 'NoMatchingEventsFound,*').Count) {
        $estado = 'desconocido'
        $texto = 'Windows no pudo leer todos los avisos de los últimos 30 días.'
    } elseif ($apagados.Count) {
        $texto += ' (por ejemplo, se quedó sin batería o se mantuvo pulsado el botón).'
    }
    [pscustomobject]@{ Estado=$estado; Detalle=$texto; Causas=$causas; Apagados=$apagados.Count; Pantallazos=$azules.Count
        Errores=$hardware.Count; CuelguesGrafica=$graficas.Count }
}

function Get-AldiaHardware {
    $estabilidad = Get-AldiaEstabilidad
    if (Test-AldiaMaquinaVirtual) {
        return [pscustomobject]@{ Virtual=$true; Estabilidad=$estabilidad }
    }
    $cache = if (!(Test-AldiaAdmin)) { Get-AldiaCacheHardware }
    [pscustomobject]@{ Discos=@(Get-AldiaDiscos $cache); Baterias=@(Get-AldiaBateriaSalud); Memoria=Get-AldiaMemoriaHardware
        Estabilidad=$estabilidad; FechaDatos=$cache.Texto; Virtual=$false }
}

function Get-AldiaAlertaDisco {
    param($Discos)
    if ($Discos.Estado -contains 'mal') {
        [pscustomobject]@{ Id='discoDanado'; Nombre='Disco en mal estado'; Estado='mal'
            Detalle='Copia tus archivos importantes cuanto antes.'; Accion='Abrir Diagnóstico' }
    }
}

function Get-AldiaResumenHardware {
    param($Hardware)
    $estados = @($Hardware.Discos) + @($Hardware.Baterias) + @($Hardware.Estabilidad)
    $avisos = @($estados | Where-Object Estado -eq aviso).Count
    if ($estados.Estado -contains 'mal') { return 'mal','Hay un problema' }
    if ($avisos -eq 1) { return 'aviso','Hay 1 cosa que revisar' }
    if ($avisos) { return 'aviso',"Hay $avisos cosas que revisar" }
    if ($estados.Estado -contains 'desconocido' -or (!$Hardware.Virtual -and !$Hardware.Discos.Count)) {
        return 'desconocido','Faltan datos para comprobar el PC'
    }
    'bien','Todo bien'
}
