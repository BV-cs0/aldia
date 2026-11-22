function Send-AldiaEventoGui {
    param($Tipo, $Datos)
    $cola.Enqueue(@{ Tipo=$Tipo; Datos=$Datos })
}

function Get-AldiaTareaGui {
    $servicio = Connect-AldiaTareas
    try { $servicio.GetFolder('\Aldia').GetTask('Al Día') }
    catch { if (($_.Exception.GetBaseException().HResult -band 65535) -notin 2,3) { throw } }
}

function Get-AldiaHerramientasGui {
    param($Config, [switch]$Demo)
    if ($Demo) {
        return @{
            Recomendaciones=@(
                @{ Herramienta='Intel Driver & Support Assistant'; Instalado='no'; Equipo='equipo Intel'; Id='Intel.IntelDriverAndSupportAssistant' }
                @{ Herramienta='AMD Software Adrenalin'; Instalado='sí'; Version='25.1'; Equipo='GPU AMD'; Url='https://www.amd.com/' }
            )
            Gpu=@(@{ Nombre='Gráficos de ejemplo'; Aviso='Driver de GPU con más de 12 meses.' })
            Inventario=@(@{ Nombre='Programa de ejemplo'; Version='1.0' })
            Config=$Config; Activa=$estado.ActivaDemo; Errores=@()
        }
    }
    $herramientas = @{ Config=$Config; Activa=$false; Errores=@() }
    foreach ($seccion in 'Gpu','Recomendaciones','Inventario','Activa') {
        try {
            switch ($seccion) {
                'Gpu' {
                    $gpu = @(Get-AldiaGpu)
                    $herramientas.Gpu = @(Get-AldiaGpuAntiguas $gpu)
                }
                'Recomendaciones' { $herramientas.Recomendaciones = @(Get-AldiaRecomendaciones $gpu) }
                'Inventario' { $herramientas.Inventario = @(Get-AldiaApps $Config -Inventario) }
                'Activa' {
                    $tarea = Get-AldiaTareaGui
                    if ($tarea) { $herramientas.Activa = [bool]$tarea.Enabled }
                }
            }
        } catch { $herramientas.Errores += ('{0}: {1}' -f $seccion,$_.Exception.Message) }
    }
    $herramientas
}

function Get-AldiaProteccionGui {
    param([string]$Unidad = $env:SystemDrive)
    try {
        $politica = Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\SystemRestore' -ErrorAction SilentlyContinue
        if ($politica.DisableSR -eq 1) { return 'bloqueada' }
        $registro = Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore' -ErrorAction Stop
        if ($registro.DisableSR -eq 1) { return 'desactivada' }
        if ($Unidad -notmatch '^[A-Za-z]:$') { return 'desconocida' }
        $volumen = Get-CimInstance Win32_Volume -Filter "DriveLetter = '$Unidad'" -ErrorAction Stop
        if (!$volumen.DeviceID) { return 'desconocida' }
        # Win32_ShadowStorage expone las mismas asociaciones por volumen que vssadmin.
        $id = [regex]::Match($volumen.DeviceID, '\{[0-9A-Fa-f-]+\}').Value
        if (!$id) { return 'desconocida' }
        $almacen = Get-CimInstance Win32_ShadowStorage -ErrorAction Stop |
            Where-Object { ($_.Volume.DeviceID, [string]$_.Volume -join " ") -match [regex]::Escape($id) } | Select-Object -First 1
        if (!$almacen) { return 'desactivada' }
        if ($registro.RPSessionInterval -gt 0 -or @(Get-ComputerRestorePoint -ErrorAction Stop).Count -gt 0) {
            return 'activada'
        }
    } catch { return 'desconocida' }
    'desconocida'
}

function Save-AldiaConfigGui {
    param($Cambios, [switch]$Demo)
    $horaAnterior = $Config.horaDiaria
    $configNueva = Set-AldiaConfigGui $Config $Cambios
    if ($Demo) {
        $estado.ConfigDemo = $configNueva
        $estado.ActivaDemo = $Cambios.Activa
        return
    }
    Assert-AldiaPermisos $programa
    if (Test-Path -LiteralPath $rutaConfig) { Assert-AldiaPermisos $rutaConfig }
    $tarea = Get-AldiaTareaGui
    $rutaTemporal = Join-Path $programa ("config-{0}.tmp" -f [guid]::NewGuid())
    $copiaAnterior = "$rutaTemporal.bak"
    $existia = [IO.File]::Exists($rutaConfig)
    try {
        [IO.File]::WriteAllText($rutaTemporal, ($configNueva | ConvertTo-Json -Depth 10), [Text.UTF8Encoding]::new($false))
        Set-AldiaPropietarioAdmin $rutaTemporal
        if ($existia) { [IO.File]::Replace($rutaTemporal, $rutaConfig, $copiaAnterior) }
        else { [IO.File]::Move($rutaTemporal, $rutaConfig) }
        try {
            if ((!$tarea -and $Cambios.Activa) -or ($tarea -and $horaAnterior -ne $configNueva.horaDiaria)) {
                Assert-AldiaPermisos (Join-Path $programa 'aldia.ps1')
                Register-AldiaTarea $programa $configNueva -Deshabilitada:(!$Cambios.Activa)
            } elseif ($tarea) { $tarea.Enabled = $Cambios.Activa }
        } catch {
            if ($existia) { [IO.File]::Replace($copiaAnterior, $rutaConfig, [NullString]::Value) }
            else { [IO.File]::Delete($rutaConfig) }
            throw
        }
        if ($existia) { [IO.File]::Delete($copiaAnterior) }
    } finally {
        if ([IO.File]::Exists($rutaTemporal)) { [IO.File]::Delete($rutaTemporal) }
    }
}

function Find-AldiaFilasGui {
    param($Config, [switch]$Demo)
    $filas = @(foreach ($fuente in 'windows','pnp','drivers','apps','npm') {
        $fase = switch ($fuente) {
            'windows' { 'Buscando actualizaciones de Windows…' }
            { $_ -in 'pnp','drivers' } { 'Revisando drivers…' }
            { $_ -in 'apps','npm' } { 'Revisando programas…' }
        }
        Send-AldiaEventoGui fase $fase
        if ($Demo) {
            Start-Sleep -Milliseconds 240
            Get-AldiaDemoGui $Config | Where-Object Fuente -eq $fuente
            continue
        }
        try {
            $elementos = @(switch ($fuente) {
                'windows' { Find-AldiaActualizacionesWU (New-AldiaSesionWU) Software }
                'drivers' { Get-AldiaDriversWU (New-AldiaSesionWU) $Config }
                'pnp' { Get-AldiaProblemasPnP }
                'apps' {
                    if (!(Get-Command winget.exe -CommandType Application -ErrorAction SilentlyContinue)) {
                        throw 'winget no está disponible.'
                    }
                    Get-AldiaApps $Config
                }
                'npm' { Get-AldiaNpm }
            })
            foreach ($elemento in $elementos) { ConvertTo-AldiaFilaGui $fuente $elemento $Config }
        } catch {
            Send-AldiaEventoGui aviso ('{0}: {1}' -f $fuente,$_.Exception.Message)
        }
    })
    Send-AldiaEventoGui filas $filas
}

function Update-AldiaTrabajoGui {
    param($Trabajo, $Config, $CacheWU, [switch]$Demo)
    $j = $Trabajo
    if ($Demo) {
        Start-Sleep -Milliseconds 550
        if ($j.Fuente -eq 'npm') { return (New-AldiaResultado npm $j.Id fallo 1 'Ejemplo: no se pudo descargar el paquete.' -Titulo $j.Nombre) }
        return (New-AldiaResultado $j.Fuente $j.Id actualizado 0 '' -Reinicio ($j.Fuente -eq 'windows') -Titulo $j.Nombre)
    }
    if ($j.Fuente -in 'apps','npm' -and $j.Id -in $Config.excluir) {
        return (New-AldiaResultado $j.Fuente $j.Id omitido $null 'Excluido en la configuración.' -Titulo $j.Nombre)
    }
    switch ($j.Fuente) {
        'apps' { Update-AldiaAppItem $Config $j.Paquete }
        'npm' { Update-AldiaNpmItem $Config $j.Paquete }
        { $_ -in 'drivers','windows' } {
            if (!$CacheWU.Sesion) { $CacheWU.Sesion = New-AldiaSesionWU }
            if (!$CacheWU.ContainsKey($j.Fuente)) {
                $porId = @{}
                $actualizaciones = if ($j.Fuente -eq 'drivers') { Get-AldiaDriversWU $CacheWU.Sesion $Config }
                else { Find-AldiaActualizacionesWU $CacheWU.Sesion Software }
                foreach ($u in $actualizaciones) {
                    if ($u.Identity.UpdateID) { $porId[[string]$u.Identity.UpdateID] = $u }
                }
                $CacheWU[$j.Fuente] = $porId
            }
            $actualizacion = $CacheWU[$j.Fuente][$j.Id]
            if ($actualizacion) { Update-AldiaWUItem $CacheWU.Sesion $actualizacion $j.Fuente }
            else { New-AldiaResultado $j.Fuente $j.Id 'no-aplicable' $null 'Windows Update ya no ofrece esta actualización.' -Titulo $j.Nombre }
        }
    }
}

function Update-AldiaTrabajosGui {
    param($Trabajos, $Config, [switch]$Demo)
    $inicio = (Get-Date).ToString('o')
    $cacheWU = @{}
    if (!$Demo) { New-AldiaPuntoRestauracion $Config @($Trabajos.Fuente) }
    $resultados = @(for ($i=0; $i -lt $Trabajos.Count; $i++) {
        $j = $Trabajos[$i]
        Send-AldiaEventoGui instalando @{ Clave=$j.Clave; Nombre=$j.Nombre; Actual=$i+1; Total=$Trabajos.Count }
        try {
            $r = Update-AldiaTrabajoGui $j $Config $cacheWU -Demo:$Demo
            if (!$r) { throw 'El elemento ya no se puede actualizar.' }
        } catch { $r = New-AldiaResultado $j.Fuente $j.Id fallo $null $_.Exception.Message -Titulo $j.Nombre }
        Send-AldiaEventoGui resultado @{ Clave=$j.Clave; Resultado=$r }
        $r
    })
    $resumen = Get-AldiaResumenGui $resultados
    $entrada = [pscustomobject]@{
        Inicio=$inicio; Fin=(Get-Date).ToString('o'); Modo='ventana'; Codigo=[int]($resumen.Fallidas -gt 0)
        Resultados=$resultados; RequiereReinicio=$resumen.Reinicio
    }
    Send-AldiaEventoGui resumen $resumen
    if ($Demo) { $estado.HistorialDemo += $entrada }
    else { Add-AldiaHistorial $historialRuta $entrada }
}

function Invoke-AldiaTrabajoGui {
    param($Operacion, $Datos, [bool]$Demo, $Cola, $Estado)
    $ErrorActionPreference = 'Stop'
    $mutex = $null
    $adquirido = $false
    try {
        if (!$Demo) {
            $mutex = [Threading.Mutex]::new($false,'Global\Aldia')
            try { $adquirido = $mutex.WaitOne(0) }
            catch [Threading.AbandonedMutexException] { $adquirido = $true }
        }
        Send-AldiaEventoGui ocupado (!$Demo -and !$adquirido)
        if ($Operacion -eq 'estado') { return }
        if (!$Demo -and !$adquirido -and $Operacion -in 'instalar','fabricante','guardar','reiniciar','proteger') {
            Send-AldiaEventoGui aviso 'Espera a que termine la actualización en curso.'
            return
        }
        if ($Operacion -eq 'analizar' -and $adquirido) {
            $mutex.ReleaseMutex()
            $adquirido = $false
        }
        if ($Demo) {
            if (!$estado.ConfigDemo) { $estado.ConfigDemo = Get-AldiaConfig }
            $config = $estado.ConfigDemo
        } else {
            $programa = Get-AldiaProgramFiles
            $rutaConfig = Join-Path $programa 'config.json'
            $datosAldia = Join-Path $env:ProgramData 'Aldia'
            $historialRuta = Join-Path $datosAldia 'historial.jsonl'
            Assert-AldiaRutaNormal $datosAldia
            Assert-AldiaRutaNormal $historialRuta
            if ($Operacion -eq 'instalar') {
                $directorioLog = Join-Path $datosAldia 'logs'
                Assert-AldiaRutaNormal $directorioLog
            }
            $config = Get-AldiaConfig $rutaConfig
        }
        switch ($Operacion) {
            'analizar' { Find-AldiaFilasGui $config -Demo:$Demo }
            'proteger' {
                if ($Demo) { $estado.ProteccionDemo = $true }
                else { Enable-ComputerRestore -Drive "$env:SystemDrive\" -ErrorAction Stop }
                Send-AldiaEventoGui proteccion 'activada'
                Send-AldiaEventoGui fase 'Protección del sistema activada.'
            }
            'instalar' { Update-AldiaTrabajosGui $Datos $config -Demo:$Demo }
            'guardar' {
                Save-AldiaConfigGui $Datos -Demo:$Demo
                Send-AldiaEventoGui fase 'Configuración guardada.'
            }
            'fabricante' {
                if ($Datos -notmatch '^[A-Za-z0-9][A-Za-z0-9.\-_+]*$') { throw 'Identificador de paquete inválido.' }
                if ($Demo) { Start-Sleep -Milliseconds 550 }
                else {
                    $origen = if ($Datos -in '9N7R5S6B0ZZH','XP8CLZL93F5Z4P') { 'msstore' } else { 'winget' }
                    $r = Invoke-AldiaComando winget.exe @('install','--id',$Datos,'--exact','--silent','--accept-package-agreements','--accept-source-agreements','--disable-interactivity','--source',$origen) -Timeout ($config.timeoutMinutosPorPaquete * 60)
                    if ($r.Timeout -or $r.Codigo -ne 0) { throw "No se pudo instalar la herramienta. $($r.Error) (código $($r.Codigo))" }
                }
                Send-AldiaEventoGui fase $(if ($Demo) { 'Instalación de ejemplo completada.' } else { 'Herramienta instalada.' })
            }
            'reiniciar' {
                if (!$Demo) {
                    $r = Invoke-AldiaComando (Join-Path $env:SystemRoot 'System32\shutdown.exe') @('/r','/t','0')
                    if ($r.Timeout -or $r.Codigo -ne 0) { throw "No se pudo reiniciar. $($r.Error)" }
                } else { Send-AldiaEventoGui fase 'Reinicio simulado.' }
            }
        }
        if ($Operacion -in 'analizar','instalar') {
            $historial = if ($Demo) { $estado.HistorialDemo } else { Read-AldiaHistorial $historialRuta }
            Send-AldiaEventoGui historial @($historial | Sort-Object Inicio -Descending)
        }
        if ($Operacion -eq 'analizar') {
            $proteccion = if ($Demo) {
                if ($estado.ProteccionDemo) { 'activada' } else { 'desactivada' }
            } else { Get-AldiaProteccionGui }
            Send-AldiaEventoGui proteccion $proteccion
        }
        if ($Operacion -in 'analizar','fabricante') {
            Send-AldiaEventoGui herramientas (Get-AldiaHerramientasGui $config -Demo:$Demo)
        }
    } catch { Send-AldiaEventoGui aviso $_.Exception.Message }
    finally {
        if ($adquirido) { $mutex.ReleaseMutex() }
        if ($mutex) { $mutex.Dispose() }
    }
}
