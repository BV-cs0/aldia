function Test-AldiaFijado {
    param($Config, [string]$Fuente, [string]$Id, [string[]]$KB)
    foreach ($fijado in $Config.fijados) {
        if ($fijado.fuente -eq $Fuente -and ($fijado.id -eq $Id -or ($Fuente -eq 'windows' -and $fijado.version -in $KB))) {
            return $true
        }
    }
    $false
}

function Get-AldiaVersionesWinget {
    param([string]$Texto)
    $enTabla = $false
    foreach ($linea in $Texto -split '\r?\n') {
        $valor = (($linea -split '\r')[-1]).Trim()
        if ($valor -match '^-{5,}$') { $enTabla = $true; continue }
        if ($enTabla -and !$valor) { break }
        if ($enTabla -and $valor -match '^\S+$') { $valor }
    }
}

function Get-AldiaPlanDeshacer {
    param($Resultado, [switch]$Demo)
    $plan = @{ Disponible=$false; Resultado=$Resultado; Motivo='Solo se pueden deshacer actualizaciones completadas.' }
    if ($Resultado.Estado -ne 'actualizado') { return $plan }
    $id = [string]$Resultado.Id
    $antes = [string]$Resultado.Antes
    switch ($Resultado.Fuente) {
        apps {
            $plan.Motivo = 'No se puede volver a esa versión con winget.'
            if ($id -notmatch '^[A-Za-z0-9][A-Za-z0-9._+-]*$' -or $antes -notmatch '^[A-Za-z0-9][A-Za-z0-9._+~-]*$' -or $antes -in 'Unknown','Desconocido','Desconocida') { return $plan }
            if (!$Demo) {
                if ($estadoWinget -and $estadoWinget.Estado -ne 'ok') { $plan.Motivo = $estadoWinget.Mensaje; $plan.Omitido = $true; return $plan }
                $r = Invoke-AldiaWinget @('show','--id',$id,'--exact','--versions','--disable-interactivity')
                if ($r.Timeout -or $r.Codigo -ne 0 -or $antes -cnotin @(Get-AldiaVersionesWinget $r.Salida)) { return $plan }
            }
            $plan.Ejecutable = 'winget.exe'
            $plan.Argumentos = @('install','--id',$id,'--exact','--version',$antes,'--force','--silent',
                '--accept-package-agreements','--accept-source-agreements','--disable-interactivity')
        }
        npm {
            $plan.Motivo = 'La versión anterior de npm no está disponible en el historial.'
            if ($id -cnotmatch '^(?:@[a-z0-9._-]+/)?[a-z0-9][a-z0-9._-]*$' -or
                $antes -cnotmatch '^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?$') { return $plan }
            $plan.Ejecutable = if ($Demo) { 'npm.cmd' } else { Get-AldiaNpmEjecutable }
            if (!$plan.Ejecutable) { $plan.Motivo = 'npm no está disponible.'; return $plan }
            $plan.Argumentos = @('install','-g',"$id@$antes")
        }
        windows {
            $plan.Motivo = 'Las actualizaciones de inteligencia de seguridad no se pueden deshacer.'
            if ($Resultado.Definiciones -or $Resultado.KB -in 'KB2267602','KB915597' -or $Resultado.Mensaje -in 'KB2267602','KB915597') { return $plan }
            $plan.Motivo = 'La actualización no identifica un único KB para desinstalar.'
            $kb = if ($Resultado.KB) { [string]$Resultado.KB } else { [string]$Resultado.Mensaje }
            if ($kb -notmatch '^KB(\d+)$') { return $plan }
            $plan.Ejecutable = Join-Path $env:SystemRoot 'System32\wusa.exe'
            $plan.Argumentos = @('/uninstall',"/kb:$($Matches[1])",'/quiet','/norestart')
            $antes = $kb.ToUpperInvariant()
        }
        drivers {
            $plan.Motivo = 'Puedes volver atrás desde Restaurar sistema o en el Administrador de dispositivos › Propiedades › Revertir controlador.'
            $plan.Controlador = $true
            $plan.Restaurar = $Demo -or (Get-AldiaProteccionGui) -eq 'activada'
            return $plan
        }
        default { return $plan }
    }
    $plan.Disponible = $true
    $plan.Motivo = ''
    $plan.Version = $antes
    if (!$Demo) { $plan.AvisoSeguridad = Get-AldiaAvisoDeshacer $Resultado $antes }
    $plan
}

function Save-AldiaFijados {
    param($Config, [string]$RutaConfig)
    $dir = Split-Path $RutaConfig
    Assert-AldiaPermisos $dir
    if ([IO.File]::Exists($RutaConfig)) { Assert-AldiaPermisos $RutaConfig }
    $temporal = Join-Path $dir ("config-{0}.tmp" -f [guid]::NewGuid())
    try {
        [IO.File]::WriteAllText($temporal, ($Config | ConvertTo-Json -Depth 10), [Text.UTF8Encoding]::new($false))
        Set-AldiaPropietarioAdmin $temporal
        if ([IO.File]::Exists($RutaConfig)) { [IO.File]::Replace($temporal,$RutaConfig,[NullString]::Value) }
        else { [IO.File]::Move($temporal,$RutaConfig) }
    } finally { [IO.File]::Delete($temporal) }
}

function Invoke-AldiaDeshacer {
    param($Config, $Plan, [string]$RutaConfig, [string]$HistorialRuta, [switch]$Demo)
    if (!$Plan.Disponible) { throw $Plan.Motivo }
    $item = $Plan.Resultado
    if (!$Demo) {
        Assert-AldiaPermisos (Split-Path $RutaConfig)
        if (Test-Path -LiteralPath $RutaConfig) { Assert-AldiaPermisos $RutaConfig }
        $limite = $Config.timeoutMinutosPorPaquete * 60
        $r = if ($item.Fuente -eq 'apps') { Invoke-AldiaWinget $Plan.Argumentos -Timeout $limite }
            else { Invoke-AldiaComando $Plan.Ejecutable $Plan.Argumentos -Timeout $limite }
        $winget = if ($item.Fuente -eq 'apps') { ConvertTo-AldiaEstadoWinget $r.Codigo -Timeout:$r.Timeout }
        $reinicio = $winget.RequiereReinicio -or ($item.Fuente -eq 'windows' -and $r.Codigo -in 3010,1641)
        if ($r.Timeout -or ($r.Codigo -ne 0 -and !$reinicio)) { throw "No se pudo deshacer la actualización (código $($r.Codigo)). $($r.Error)" }
    }
    $fecha = [datetime]::Now.ToString('o')
    $Config.fijados = @($Config.fijados | Where-Object { $_.fuente -ne $item.Fuente -or $_.id -ne $item.Id }) +
        @([pscustomobject]@{ fuente=[string]$item.Fuente; id=[string]$item.Id; version=$Plan.Version; fecha=$fecha; motivo='Deshecho por el usuario' })
    if (!$Demo) {
        try { Save-AldiaFijados $Config $RutaConfig }
        catch { throw "Se deshizo la actualización, pero no se pudo fijar el elemento. $($_.Exception.Message)" }
    }
    $mensaje = if ($Demo) { 'Se simuló la reversión y se fijó el elemento de ejemplo.' }
        elseif ($reinicio) { 'Actualización deshecha y elemento fijado. Reinicia el PC para terminar.' }
        else { 'Actualización deshecha y elemento fijado.' }
    $resultado = New-AldiaResultado $item.Fuente $item.Id revertido $r.Codigo $mensaje $item.Despues $Plan.Version -Reinicio $reinicio -Titulo $item.Titulo
    $entrada = @{ Inicio=$fecha; Fin=$fecha; Modo='deshacer'; Completa=$false; Codigo=0; RequiereReinicio=[bool]$reinicio; Resultados=@($resultado) }
    if (!$Demo) {
        try { Add-AldiaHistorial $HistorialRuta $entrada }
        catch { throw "Se deshizo y fijó la actualización, pero no se pudo registrar en el historial. $($_.Exception.Message)" }
    }
    $entrada
}
function Assert-AldiaHistorialDeshacer {
    param([string]$Ruta)
    Assert-AldiaRutaNormal (Split-Path $Ruta)
    Assert-AldiaPermisos $Ruta
}