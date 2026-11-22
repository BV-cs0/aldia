function Get-AldiaNpmEjecutable {
    $comando = Get-Command npm.cmd,npm.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($comando) { $comando.Source }
}

function Get-AldiaNpm {
    param([string]$Ejecutable = (Get-AldiaNpmEjecutable))
    if (!$Ejecutable) { return }
    $r = Invoke-AldiaComando $Ejecutable @('outdated','-g','--json')
    if ($r.Timeout -or $r.Codigo -notin 0,1 -or (!$r.Salida.Trim() -and $r.Codigo -ne 0)) {
        throw "No se pudo consultar npm (código $($r.Codigo)). $($r.Error)"
    }
    if (!$r.Salida.Trim()) { return }
    $datos = $r.Salida | ConvertFrom-Json -ErrorAction Stop
    if ($datos.PSObject.Properties['error']) { throw "npm devolvió un error: $($datos.error.summary)" }
    foreach ($p in $datos.PSObject.Properties) {
        if ($p.Name -cnotmatch '^(?:@[A-Za-z0-9._-]+/)?[A-Za-z0-9][A-Za-z0-9._-]*$') {
            Write-AldiaLog "Se descartó un nombre npm inválido: $($p.Name)"
            continue
        }
        [pscustomobject]@{ Id = $p.Name; Version = $p.Value.current; Disponible = $p.Value.latest }
    }
}

function Update-AldiaNpm {
    param($Config, [switch]$Simular)
    $ejecutable = Get-AldiaNpmEjecutable
    if (!$ejecutable) { return }
    foreach ($p in Get-AldiaNpm $ejecutable) {
        if ($p.Id -in $Config.excluir) { continue }
        Update-AldiaNpmItem $Config $p $ejecutable -Simular:$Simular
    }
}

function Update-AldiaNpmItem {
    param($Config, $p, [string]$Ejecutable = (Get-AldiaNpmEjecutable), [switch]$Simular)
    if (!$Ejecutable) { return (New-AldiaResultado npm $p.Id fallo $null "npm no está disponible.") }
    try {
        $r = Invoke-AldiaComando $ejecutable @('install','-g',"$($p.Id)@latest") -Timeout ($Config.timeoutMinutosPorPaquete * 60) -Simular:$Simular
        if ($Simular) {
            New-AldiaResultado npm $p.Id simulado $null '' $p.Version $p.Disponible
            return
        }
        $estado = if ($r.Timeout) { 'timeout' } elseif ($r.Codigo -eq 0) { 'actualizado' } else { 'fallo' }
        New-AldiaResultado npm $p.Id $estado $r.Codigo $r.Error $p.Version $p.Disponible
    } catch { New-AldiaResultado npm $p.Id fallo $null $_.Exception.Message $p.Version $p.Disponible }
}
