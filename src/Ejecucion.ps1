function Get-AldiaBateria {
    Add-Type -AssemblyName System.Windows.Forms
    $energia = [System.Windows.Forms.SystemInformation]::PowerStatus
    [pscustomobject]@{
        EnBateria = $energia.PowerLineStatus -eq 'Offline'
        Carga = [int]($energia.BatteryLifePercent * 100)
    }
}

function Get-AldiaMotivoOmision {
    param($Config, $Historial, [switch]$Forzar, [datetime]$Ahora = (Get-Date))
    if (!$Forzar) {
        foreach ($h in $Historial) {
            $completa = if ($h -is [System.Collections.IDictionary] -and $h.Contains('Completa')) { $h.Completa -eq $true }
                elseif ($h.PSObject.Properties['Completa']) { $h.Completa -eq $true }
                else { $h.Modo -in 'programado','interactivo' }
            if ($completa -and $null -ne $h.Codigo -and $h.Codigo -in 0,1 -and $h.Fin) {
                $fin = [datetime]$h.Fin
                if ($fin -le $Ahora -and $fin -gt $Ahora.AddHours(-20)) {
                    return 'Hubo una ejecución completada hace menos de 20 horas.'
                }
            }
        }
    }
    $bateria = Get-AldiaBateria
    if ($bateria.EnBateria -and $bateria.Carga -lt $Config.bateriaMinima) { return 'Batería por debajo del mínimo configurado.' }
}

function Get-AldiaFallosRepetidos {
    param($Historial, $Actual)
    $previas = @($Historial | Where-Object Modo -ne deshacer | Select-Object -Last 2)
    if ($previas.Count -lt 2) { return }
    $vistos = @{}
    foreach ($r in $Actual) {
        if ($r.Estado -notin 'fallo','timeout','persistente') { continue }
        $clave = "$($r.Fuente)/$($r.Id)"
        if ($vistos.ContainsKey($clave)) { continue }
        $vistos[$clave] = $true
        $racha = @($previas | Where-Object {
            @($_.Resultados | Where-Object {
                $_.Fuente -eq $r.Fuente -and $_.Id -eq $r.Id -and $_.Estado -in 'fallo','timeout','persistente'
            }).Count
        })
        if ($racha.Count -eq 2) { if ($r.Titulo) { $r.Titulo } else { $r.Id } }
    }
}

function Show-AldiaTabla {
    param([string]$Titulo, $Elementos, [System.Collections.Specialized.OrderedDictionary]$Columnas,
          [ConsoleColor]$Color = [ConsoleColor]::White)
    if ($Titulo) { Write-Host "=== $Titulo ===" }
    if (!@($Elementos).Count) { Write-Host 'Sin resultados.' -ForegroundColor Green; return }

    $anchos = @($Columnas.Values)
    $claves = @($Columnas.Keys)
    $rotulos = @{ Version = 'Versión'; ComoConseguirla = 'Cómo conseguirla'; Title = 'Título'
        Titulo = 'Título'; Codigo = 'Código'; Despues = 'Después'; Mensaje = 'Mensaje' }
    $cabecera = @(foreach ($clave in $claves) {
        if ($rotulos.ContainsKey($clave)) { $rotulos[$clave] } else { $clave }
    })
    $ui = $Host.UI.RawUI
    $ancho = $ui.WindowSize.Width
    if ($ancho -le 0) { $ancho = 80 }
    $total = ($anchos | Measure-Object -Sum).Sum + 2 * ($anchos.Count - 1)
    while ($total -gt ($ancho - 1)) {
        $mayor = 0
        for ($i = 1; $i -lt $anchos.Count; $i++) {
            if (($anchos[$i] - $cabecera[$i].Length) -gt ($anchos[$mayor] - $cabecera[$mayor].Length)) { $mayor = $i }
        }
        if ($anchos[$mayor] -le $cabecera[$mayor].Length) { break }
        $anchos[$mayor]--
        $total--
    }

    $filas = @(,@($cabecera)) + @(for ($i = 0; $i -lt $Elementos.Count; $i++) {
        $elemento = $Elementos[$i]
        ,@(foreach ($clave in $claves) {
            $valor = $elemento.$clave
            $valor -join ', '
        })
    })
    foreach ($fila in $filas) {
        $celdas = @(for ($i = 0; $i -lt $claves.Count; $i++) {
            $valor = [string]$fila[$i] -replace '[\r
\t]+', ' '
            $largo = $ui.LengthInBufferCells($valor)
            if ($largo -gt $anchos[$i]) {
                do {
                    $quitar = if ($valor.Length -gt 1 -and [char]::IsSurrogatePair($valor, $valor.Length - 2)) { 2 } else { 1 }
                    $valor = $valor.Substring(0, $valor.Length - $quitar)
                } while ($ui.LengthInBufferCells($valor) -ge $anchos[$i])
                $valor += '…'
                $largo = $ui.LengthInBufferCells($valor)
            }
            $valor + (' ' * ($anchos[$i] - $largo))
        })
        Write-Host (($celdas -join '  ').TrimEnd()) -ForegroundColor $Color
    }
}

function Invoke-AldiaActualizacion {
    param($Config, [string[]]$Fuentes, [string]$HistorialRuta, [switch]$Simular, [switch]$Forzar, [switch]$Parcial)
    $mutex = $null
    $adquirido = $false
    try {
        if (!$Simular) {
            $mutex = [Threading.Mutex]::new($false,'Global\Aldia')
            try { $adquirido = $mutex.WaitOne(0) }
            catch [Threading.AbandonedMutexException] { $adquirido = $true }
            if (!$adquirido) { Write-AldiaLog 'Ya hay otra ejecución en marcha.'; return 3 }
            $historial = @(Read-AldiaHistorial $HistorialRuta)
            if ($programado) {
                if ((Get-AldiaCosteInternet) -eq 'medido') {
                    $motivo = 'Conexión de datos limitada.'
                    Write-AldiaLog $motivo
                    $fecha = (Get-Date).ToString('o')
                    Add-AldiaHistorial $HistorialRuta @{
                        Inicio=$fecha; Fin=$fecha; Modo='programado'; Completa=$false; Codigo=3; RequiereReinicio=$false
                        Resultados=@(New-AldiaResultado red internet omitido $null $motivo)
                    }
                    return 3
                }
                $motivo = Get-AldiaMotivoOmision $Config $historial -Forzar:$Forzar
                if ($motivo) { Write-AldiaLog $motivo; return 3 }
            }
        }
        $inicio = (Get-Date).ToString('o')
        $discoBajo = Test-AldiaDiscoBajo
        if ($discoBajo) {
            if ($programado) { Write-AldiaLog $script:AldiaDiscoBajo }
            else { Write-Host $script:AldiaDiscoBajo -ForegroundColor Yellow }
        }
        $paraRestaurar = @($Fuentes | Where-Object { !($programado -and $discoBajo -and $_ -in 'windows','drivers') })
        New-AldiaPuntoRestauracion $Config $paraRestaurar -Simular:$Simular
        $resultados = @(foreach ($fuente in $Fuentes) {
            try {
                switch ($fuente) {
                    'windows' {
                        if ($programado -and $discoBajo) { New-AldiaResultado windows disco omitido $null $script:AldiaDiscoBajo }
                        else { Update-AldiaWindows $Config -Simular:$Simular }
                    }
                    'office' { Update-AldiaOffice $Config -Simular:$Simular }
                    'store' { Update-AldiaStore -Simular:$Simular }
                    'drivers' {
                        if ($programado -and $discoBajo) { New-AldiaResultado drivers disco omitido $null $script:AldiaDiscoBajo }
                        else { Update-AldiaDrivers $Config -Simular:$Simular }
                    }
                    'apps' {
                        if ($null -ne $estadoWinget -and $estadoWinget.Estado -ne 'ok') {
                            New-AldiaResultado apps winget omitido $null $estadoWinget.Mensaje
                        } else { Update-AldiaApps $Config -Simular:$Simular }
                    }
                    'npm' { Update-AldiaNpm $Config -Simular:$Simular }
                }
            } catch { New-AldiaResultado $fuente consulta fallo $null $_.Exception.Message }
        })
        $fallos = @($resultados | Where-Object { $_.Estado -in 'fallo','timeout','persistente' })
        if ($Simular) {
            foreach ($r in $resultados | Where-Object { $_.Estado -in 'aviso','fallo','omitido','explicito' }) {
                Write-Host "$($r.Fuente) · $($r.Id): $($r.Mensaje)" -ForegroundColor Yellow
            }
            $previstos = @($resultados | Where-Object Estado -eq simulado)
            Write-Host "Se actualizarían $($previstos.Count) elementos"
            return [int]($fallos.Count -gt 0)
        }
        $cambios = @($resultados | Where-Object Estado -eq actualizado)
        $reinicio = @($resultados | Where-Object RequiereReinicio).Count -gt 0
        $codigo = [int]($fallos.Count -gt 0)
        $entradaHistorial = [ordered]@{
            Inicio = $inicio; Fin = (Get-Date).ToString('o')
            Modo = if ($programado) { 'programado' } else { 'interactivo' }
            Completa = !$Parcial; Codigo = $codigo; Resultados = $resultados; RequiereReinicio = $reinicio
        }
        Add-AldiaHistorial $HistorialRuta $entradaHistorial
        $resumen = "$($cambios.Count) actualizadas, $($fallos.Count) fallidas"
        if ($fallos.Count) {
            $nombres = $fallos | ForEach-Object { if ($_.Titulo) { $_.Titulo } else { $_.Id } }
            $resumen += ' (' + ($nombres -join ', ') + ')'
        }
        $resumen += '.'
        if ($reinicio) { $resumen += ' Reinicia para terminar.' }
        foreach ($nombre in Get-AldiaFallosRepetidos $historial $resultados) {
            $resumen += " $nombre lleva 3 ejecuciones sin poder actualizarse: hazlo a mano."
        }
        $seguridad = $null
        if ($programado -and $Config.vulnerabilidades.activado) {
            try {
                $informe = Get-AldiaVulnerabilidades $Config
                foreach ($aviso in $informe.Avisos) { Write-AldiaLog $aviso }
                foreach ($item in $informe.Programas | Where-Object { $_.Nivel -or $_.Edad -or $_.Detalle -like 'No se pudo*' }) {
                    Write-AldiaLog "$($item.Nombre): $($item.Detalle)"
                }
                $seguridad = Get-AldiaResumenSeguridad $informe
                if ($seguridad) { $resumen += " $seguridad" }
            } catch { Write-AldiaLog 'No se pudo completar la comprobación de seguridad.' }
        }
        Write-AldiaLog $resumen
        foreach ($fuente in $Fuentes) {
            $items = @($resultados | Where-Object Fuente -eq $fuente)
            foreach ($item in $items) { Write-AldiaLog ($item | ConvertTo-Json -Compress) }
            if (!$programado) {
                $columnas = [ordered]@{ Id=24; Titulo=32; Antes=12; Despues=12; Estado=13; Codigo=10; Mensaje=38 }
                $grupos = @(
                    @{ Color = 'Green'; Estados = @('actualizado','no-aplicable') }
                    @{ Color = 'Yellow'; Estados = @('aviso','omitido','explicito') }
                    @{ Color = 'Red'; Estados = @('fallo','timeout','persistente') }
                )
                Write-Host "=== $fuente ==="
                if (!$items.Count) { Write-Host 'Sin resultados.' -ForegroundColor Green }
                foreach ($grupo in $grupos) {
                    $filas = @($items | Where-Object { $_.Estado -in $grupo.Estados })
                    if ($filas.Count) {
                        Show-AldiaTabla -Elementos $filas -Columnas $columnas -Color $grupo.Color
                    }
                }
            }
        }
        if (!$programado) { Write-Host "Al Día: $resumen" }
        if ($Config.notificar -eq 'siempre' -or ($Config.notificar -eq 'solo-cambios' -and ($cambios.Count -or $seguridad)) -or
            ($Config.notificar -eq 'solo-errores' -and ($fallos.Count -or $seguridad))) { Send-AldiaToast $resumen }
        try { Clear-AldiaLogs $directorioLog $Config.diasLogs } catch { Write-AldiaLog "No se pudieron rotar los logs: $_" }
        return $codigo
    } finally {
        if ($adquirido) { $mutex.ReleaseMutex() }
        if ($mutex) { $mutex.Dispose() }
    }
}

function Show-AldiaDrivers {
    param($Config)
    try { Show-AldiaTabla 'Dispositivos con incidencias' @(Get-AldiaProblemasPnP) $script:AldiaColumnasPnP }
    catch { Write-Host 'Windows no dejó consultar los dispositivos de este PC.' -ForegroundColor Yellow }
    if ($internetCli -ne $false) {
        try {
            $sesion = New-AldiaSesionWU
            $columnas = [ordered]@{ Title=36; DriverClass=12; DriverManufacturer=18; DriverVerDate=19; DriverModel=20; DriverHardwareID=28 }
            Show-AldiaTabla 'Drivers de Windows Update' @(Get-AldiaDriversWU $sesion $Config) $columnas
        } catch { Write-Host 'No se pudieron consultar los drivers de Windows Update.' -ForegroundColor Yellow }
    }
    $gpu = @()
    try { $gpu = @(Get-AldiaGpu) }
    catch { Write-Host 'Windows no dejó consultar los gráficos de este PC.' -ForegroundColor Yellow }
    try {
        Show-AldiaTabla 'Herramientas del fabricante' @(Get-AldiaRecomendaciones $gpu) ([ordered]@{ Herramienta=33; Instalado=9; Version=10; ComoConseguirla=120 })
        Show-AldiaTabla 'Antigüedad de drivers de GPU' @(Get-AldiaGpuAntiguas $gpu) ([ordered]@{ Nombre=40; Fecha=19; Aviso=39 })
    } catch { Write-Host 'Windows no dejó consultar el fabricante de este PC.' -ForegroundColor Yellow }
}

$script:AldiaColumnasPnP = [ordered]@{ Nombre=40; Clase=12; Codigo=6; Mensaje=32; HardwareID=28 }

function Invoke-AldiaRevision {
    param($Config, $Fuentes)
    $fallo = $false
    $totales = [ordered]@{}
    foreach ($fuente in $Fuentes) {
        try {
            switch ($fuente) {
                'apps' {
                    $items = @(if (!$estadoWinget -or $estadoWinget.Estado -eq 'ok') { Get-AldiaApps $Config })
                    Show-AldiaTabla apps $items ([ordered]@{ Nombre=40; Id=31; Version=12; Disponible=12; Origen=8 })
                }
                'windows' {
                    $items = @(Find-AldiaActualizacionesWU (New-AldiaSesionWU) Software)
                    $items = @($items | Select-Object Title, KBArticleIDs, @{Name='Seguridad';Expression={ Get-AldiaSeveridadWU $_ }})
                    Show-AldiaTabla windows $items ([ordered]@{ Title=48; KBArticleIDs=14; Seguridad=24 })
                }
                'drivers' {
                    $items = @(Get-AldiaDriversWU (New-AldiaSesionWU) $Config)
                    Show-AldiaTabla drivers $items ([ordered]@{ Title=40; DriverClass=14; DriverModel=20 })
                    $pnp = @(Get-AldiaProblemasPnP)
                    Show-AldiaTabla 'Incidencias de dispositivos' $pnp $script:AldiaColumnasPnP
                }
                { $_ -in 'office','store' } {
                    $items = @(if ($fuente -eq 'office') { Get-AldiaOffice } else { Get-AldiaStore })
                    # Sin Office instalado no se muestra nada: no es algo que falte.
                    $titulo = if ($fuente -eq 'office') { 'Office' } else { 'Microsoft Store' }
                    if ($items.Count) { Show-AldiaTabla $titulo $items ([ordered]@{ Nombre=35; Version=16; Detalle=42 }) }
                }
                'npm' {
                    $items = @(Get-AldiaNpm)
                    Show-AldiaTabla npm $items ([ordered]@{ Id=40; Version=14; Disponible=14 })
                }
            }
            $totales[$fuente] = $items.Count
        } catch {
            $fallo = $true
            $totales[$fuente] = 'error'
            Write-Host "$fuente - $($_.Exception.Message)" -ForegroundColor Red
        }
    }
    $resumen = foreach ($fuente in $totales.Keys) { "$fuente=$($totales[$fuente])" }
    Write-Host "Totales por fuente: $($resumen -join ' · ')"
    if ($fallo) { return 2 }
    return 0
}

function Invoke-AldiaCli {
    param([string[]]$Argumentos, [string]$Entrada)
    $ErrorActionPreference = 'Stop'
    $programado = $Argumentos -contains '--programado'
    $simular = $false
    $pausar = $Argumentos -contains '--pausar' -and !$programado
    try {
        $orden = $Argumentos[0]
        if ($orden -notin 'revisar','actualizar','drivers','inventario','instalar','desinstalar','historial','config','gui','vulnerabilidades','salud','adoptar','deshacer','fijados','informe','diagnostico') {
            throw 'Órdenes disponibles: revisar, actualizar, drivers, inventario, instalar, desinstalar, historial, config, gui, vulnerabilidades, salud, adoptar, deshacer, fijados, informe y diagnostico.'
        }
        if ($orden -eq 'gui') { return (Start-AldiaGui $Entrada @($Argumentos | Select-Object -Skip 1)) }
        $solo = @(); $n = 10; $forzar = $false; $todo = $false; $id = $null
        $fuentesValidas = @('windows','drivers','apps','npm','office','store')
        for ($i = 1; $i -lt $Argumentos.Count; $i++) {
            $opcion = $Argumentos[$i]
            if ($opcion -eq '--pausar') { continue }
            switch ("$orden/$opcion") {
                'actualizar/--programado' {}
                'actualizar/--simular' { $simular = $true }
                'actualizar/--forzar' { $forzar = $true }
                'actualizar/--solo' {
                    $i++
                    $solo = @($Argumentos[$i] -split ',')
                    if (!$solo.Count -or @($solo | Where-Object { $_ -notin $fuentesValidas }).Count) {
                        throw 'Indica fuentes válidas para --solo: apps,windows,drivers,npm,office,store.'
                    }
                }
                { $_ -in 'adoptar/--id','deshacer/--id' } {
                    $i++
                    $id = $Argumentos[$i]
                    if ($id -notmatch '^(?:@[A-Za-z0-9._-]+/)?[A-Za-z0-9][A-Za-z0-9._+-]*$' -or
                        ($orden -eq 'adoptar' -and $id -match '[@/]')) { throw 'Indica un identificador válido.' }
                }
                'diagnostico/--guardar' { $guardarHardware = $true }
                'diagnostico/--velocidad' { $velocidadHardware = $true }
                'diagnostico/--unidad' {
                    $i++
                    $unidadHardware = $Argumentos[$i]
                    if ($unidadHardware -notmatch '^[A-Z]:?$') { throw 'Indica una letra de unidad, por ejemplo C.' }
                    $unidadHardware = $unidadHardware.TrimEnd(':').ToUpperInvariant()
                }
                'informe/--ruta' {
                    $i++
                    $rutaInforme = $Argumentos[$i]
                    if (!$rutaInforme) { throw 'Indica dónde guardar el informe.' }
                }
                'instalar/--desde-lanzador' { $desdeLanzador = $true }
                'desinstalar/--todo' { $todo = $true }
                'historial/-n' {
                    $i++
                    if (![int]::TryParse($Argumentos[$i], [ref]$n) -or $n -lt 1) { throw 'Indica un número positivo para -n.' }
                }
                default { throw "Opción desconocida para $orden : $opcion" }
            }
        }
        $datos = Join-Path $env:ProgramData 'Aldia'
        $historialRuta = Join-Path $datos 'historial.jsonl'
        $programa = Get-AldiaProgramFiles
        $rutaConfig = Join-Path $programa 'config.json'
        if ($orden -eq 'deshacer' -and !$id) { throw 'Indica el identificador con --id.' }
        $requiereAdmin = ($orden -in 'actualizar','instalar','desinstalar','config','deshacer' -or ($orden -eq 'adoptar' -and $id)) -and !$simular
        if ($requiereAdmin -and !(Test-AldiaAdmin)) {
            if ($orden -eq 'instalar' -and !$desdeLanzador -and !(Test-AldiaCuentaAdmin)) {
                Write-Host 'Abre Al Día desde una cuenta de administrador para instalarlo.' -ForegroundColor Yellow
                return 3
            }
            if ($programado) { throw 'La tarea debe ejecutarse con privilegios elevados.' }
            $ps = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
            $argumentosElevados = @('-NoProfile','-ExecutionPolicy','Bypass','-File',$Entrada) + $Argumentos
            if (!$desdeLanzador) { $argumentosElevados += '--pausar' }
            try { $r = Invoke-AldiaComando $ps $argumentosElevados -Elevar -Timeout 10800 }
            catch {
                if (!$desdeLanzador) { throw }
                Write-Host 'Windows no dio permiso para instalar Al Día.' -ForegroundColor Yellow
                return 3
            }
            if ($r.Timeout) { return 2 }
            return $r.Codigo
        }
        if ($orden -eq 'actualizar' -and !$simular) {
            Assert-AldiaRutaNormal $datos
            $directorioLog = Join-Path $datos 'logs'
            Assert-AldiaRutaNormal $directorioLog
            Assert-AldiaRutaNormal $historialRuta
        }
        if ($orden -eq 'instalar') { Install-Aldia (Split-Path $Entrada); return 0 }
        if ($orden -eq 'desinstalar') { Uninstall-Aldia -Todo:$todo; return 0 }
        if ($orden -eq 'config') {
            if (!(Test-Path -LiteralPath $rutaConfig)) { throw 'Instala Al Día antes de editar la configuración.' }
            $null = Invoke-AldiaComando (Join-Path $env:SystemRoot 'System32\notepad.exe') @($rutaConfig) -Visible
            return 0
        }
        $config = Get-AldiaConfig $rutaConfig
        if ($orden -eq 'diagnostico') {
            if ($unidadHardware -and !$velocidadHardware) { throw 'Usa --unidad junto con --velocidad.' }
            if ($guardarHardware) {
                if ($velocidadHardware) { throw 'Usa --guardar por separado.' }
                Save-AldiaHardware
                return 0
            }
            $hardware = Get-AldiaHardware
            Show-AldiaHardwareCli $hardware
            if ($velocidadHardware -and !$hardware.Virtual) {
                if (!$unidadHardware) { $unidadHardware = $env:SystemDrive.TrimEnd(':') }
                $mutexHardware = [Threading.Mutex]::new($false,'Global\Aldia')
                $turno = $false
                try {
                    try { $turno = $mutexHardware.WaitOne(0) }
                    catch [Threading.AbandonedMutexException] { $turno = $true }
                    if (!$turno) { throw 'Espera a que termine la actualización en curso.' }
                    $velocidad = Test-AldiaVelocidadDisco $unidadHardware -Config $config -Hardware $hardware
                    Write-Host $velocidad.Detalle
                } finally {
                    if ($turno) { $mutexHardware.ReleaseMutex() }
                    $mutexHardware.Dispose()
                }
            }
            return 0
        }
        if ($orden -eq 'actualizar' -and $programado -and !$simular) {
            try { Save-AldiaHardware } catch { Write-AldiaLog 'No se pudieron guardar los detalles del disco.' }
        }
        $fuentes = @($fuentesValidas | Where-Object { $config.fuentes.$_ -and (!$solo.Count -or $_ -in $solo) })
        if ($orden -in 'revisar','actualizar','drivers','informe') { $internetCli = Test-AldiaInternet }
        if ($internetCli -eq $false) {
            if ($programado) { Write-AldiaLog $script:AldiaSinInternet }
            else { Write-Host $script:AldiaSinInternet -ForegroundColor Yellow }
            if ($orden -notin 'informe','drivers') { return 3 }
        }
        if (($orden -in 'revisar','actualizar' -and 'apps' -in $fuentes) -or $orden -in 'adoptar','inventario','deshacer') {
            $estadoWinget = Get-AldiaEstadoWinget
            if ($estadoWinget.Estado -ne 'ok' -and !$programado) { Write-Host $estadoWinget.Mensaje -ForegroundColor Yellow }
        }
        switch ($orden) {
            'actualizar' {
                $codigo = Invoke-AldiaActualizacion $config $fuentes $historialRuta -Simular:$simular -Forzar:$forzar -Parcial:($solo.Count -gt 0)
                if ($programado -and !$simular) { Update-AldiaInstalado (Split-Path $Entrada) }
                return $codigo
            }
            'revisar' { return (Invoke-AldiaRevision $config $fuentes) }
            'drivers' { Show-AldiaDrivers $config }
            'vulnerabilidades' { Show-AldiaVulnerabilidadesCli $config }
            'salud' { Show-AldiaSaludCli }
            'informe' {
                $rutaEscrita = Save-AldiaInforme $config $rutaInforme $historialRuta
                Write-Host "Informe guardado en $rutaEscrita"
            }
            'adoptar' {
                if ($estadoWinget.Estado -ne 'ok') { return 3 }
                if ($id) {
                    Write-Host $script:AldiaAvisoAdopcion
                    if ((Read-Host '¿Continuar? [s/N]') -ne 's') { return 3 }
                    return (Invoke-AldiaCambioCli adoptar $id $rutaConfig $historialRuta)
                }
                Show-AldiaTabla 'Programas que puedes adoptar' @(Get-AldiaAdopciones $config) ([ordered]@{ Nombre=36; Version=14; Id=40; Confianza=10 })
            }
            'deshacer' { return (Invoke-AldiaCambioCli deshacer $id $rutaConfig $historialRuta) }
            'fijados' {
                Show-AldiaTabla 'Programas fijados' $config.fijados ([ordered]@{ fuente=8; id=38; version=16; fecha=25; motivo=24 })
            }
            'inventario' {
                if ($estadoWinget.Estado -ne 'ok') { return 3 }
                $items = @(Get-AldiaApps $config -Inventario)
                Show-AldiaTabla 'Programas de instaladores clásicos' $items ([ordered]@{ Nombre=40; Version=12; Id=55 })
            }
            'historial' {
                foreach ($h in Read-AldiaHistorial $historialRuta | Select-Object -Last $n) {
                    Write-Host "$($h.Inicio) → $($h.Fin) | $($h.Modo) | código $($h.Codigo) | reinicio: $($h.RequiereReinicio)"
                    $h.Resultados | Group-Object Fuente,Estado | Select-Object Count,Name | Format-Table | Out-Host
                }
            }
        }
        return 0
    } catch {
        if ($directorioLog) { try { Write-AldiaLog $_.Exception.Message } catch {} }
        if (!$programado) { Write-Host $_.Exception.Message -ForegroundColor Red }
        return 2
    } finally {
        if ($pausar) { $null = Read-Host 'Pulsa Enter para cerrar' }
    }
}

function New-AldiaPuntoRestauracion {
    param($Config, [string[]]$Fuentes, [switch]$Simular)
    if ($Config.puntoRestauracion -and ('windows' -in $Fuentes -or 'drivers' -in $Fuentes)) {
        try {
            if ($Simular) {
                Write-Host 'Checkpoint-Computer -Description "Al Día" -RestorePointType MODIFY_SETTINGS'
            } elseif ($PSVersionTable.PSEdition -eq 'Core') {
                Invoke-AldiaWindowsPowerShell 'Checkpoint-Computer -Description "Al Día" -RestorePointType MODIFY_SETTINGS -ErrorAction Stop -WarningAction Stop'
            } else {
                Checkpoint-Computer -Description 'Al Día' -RestorePointType MODIFY_SETTINGS -ErrorAction Stop -WarningAction Stop | Out-Null
            }
        } catch { Write-AldiaLog "No se pudo crear el punto de restauración: $_" }
    }
}

function Invoke-AldiaCambioCli {
    param($Orden, $Id, $RutaConfig, $HistorialRuta)
    $mutex = [Threading.Mutex]::new($false,'Global\Aldia')
    $adquirido = $false
    try {
        try { $adquirido = $mutex.WaitOne(0) }
        catch [Threading.AbandonedMutexException] { $adquirido = $true }
        if (!$adquirido) { Write-Host 'Hay una actualización en curso.'; return 3 }
        $config = Get-AldiaConfig $RutaConfig
        if ($Orden -eq 'adoptar') {
            Write-Host (Invoke-AldiaAdopcion $config $Id)
            return 0
        }
        Assert-AldiaRutaNormal (Split-Path $HistorialRuta)
        Assert-AldiaRutaNormal $HistorialRuta
        if (Test-Path -LiteralPath $HistorialRuta) {
            Assert-AldiaHistorialDeshacer $HistorialRuta
        }
        $resultado = Read-AldiaHistorial $HistorialRuta | Sort-Object Inicio -Descending |
            ForEach-Object { $_.Resultados } | Where-Object { $_.Estado -eq 'actualizado' -and ($_.Id -eq $Id -or $_.KB -eq $Id) } |
            Select-Object -First 1
        if (!$resultado) { throw "No hay una actualización completada para $Id." }
        $plan = Get-AldiaPlanDeshacer $resultado
        if ($plan.Omitido) { Write-Host $plan.Motivo -ForegroundColor Yellow; return 3 }
        if (!$plan.Disponible) { throw $plan.Motivo }
        if ($plan.AvisoSeguridad) { Write-Host $plan.AvisoSeguridad -ForegroundColor Red }
        if ((Read-Host "¿Volver a $($plan.Version) y fijar $Id? [s/N]") -ne 's') { return 3 }
        $entrada = Invoke-AldiaDeshacer $config $plan $RutaConfig $HistorialRuta
        Write-Host $entrada.Resultados[0].Mensaje
        0
    } finally {
        if ($adquirido) { $mutex.ReleaseMutex() }
        $mutex.Dispose()
    }
}