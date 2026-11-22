$script:AldiaAvisoAdopcion = 'Se instalará la versión más reciente encima de la tuya; normalmente se conservan tus datos y ajustes.'

function ConvertTo-AldiaNombreAdopcion {
    param([string]$Nombre)
    $texto = $Nombre -replace '(?i)\(\s*(?:x64|x86|arm64|[36][24][ -]?bit|user|usuario|LTS)\s*\)|\b(?:x64|x86|arm64|[36][24][ -]?bit|LTS)\b',' '
    ($texto -replace '(?i)\s+v?\d+(?:\.\d+)*(?=\s|$)',' ' -replace '\s+',' ').Trim(' ','-')
}

function Select-AldiaCandidatoAdopcion {
    param($Programa, $Candidatos, [string]$Publisher)
    $tokens = @(ConvertTo-AldiaTokensCpe (ConvertTo-AldiaNombreAdopcion $Programa.Nombre) | Select-Object -Unique)
    $editor = @(ConvertTo-AldiaTokensCpe $Publisher) -join ''
    $mayor = if ($Programa.Version -match '^[vV]?(\d+)') { $Matches[1] }
    $compatibles = foreach ($c in $Candidatos) {
        if ($c.Id -notmatch '^[A-Za-z0-9][A-Za-z0-9._+-]*$') { continue }
        $otros = @(ConvertTo-AldiaTokensCpe (ConvertTo-AldiaNombreAdopcion $c.Nombre) | Select-Object -Unique)
        $union = @($tokens + $otros | Select-Object -Unique).Count
        if (!$union) { continue }
        $jaccard = @($otros | Where-Object { $_ -in $tokens }).Count / $union
        if ($jaccard -lt 0.6) { continue }
        $vendor = @(ConvertTo-AldiaTokensCpe (($c.Id -split '\.')[0])) -join ''
        $puntos = [math]::Min(1, $jaccard + 0.1 * [int]($vendor -and $editor.Contains($vendor)))
        [pscustomobject]@{ Id=$c.Id; Version=$c.Version; Puntos=$puntos
            MismaMayor=([bool]$mayor -and $c.Version -match "^[vV]?$mayor(?:\.|$)")
            Confianza=if ($puntos -ge 0.8) { 'alta' } else { 'media' } }
    }
    $compatibles | Sort-Object @{Expression='MismaMayor';Descending=$true},@{Expression='Puntos';Descending=$true},
        @{Expression={ $_.Id.Length }},Id | Select-Object -First 1
}

function Get-AldiaAdopciones {
    param($Config, $Inventario, [string]$Cache = (Join-Path $env:ProgramData 'Aldia\cache'))
    if (!$PSBoundParameters.ContainsKey('Inventario')) { $Inventario = @(Get-AldiaApps $Config -Inventario) }
    $datos = Get-Content -LiteralPath (Join-Path (Split-Path $PSScriptRoot) 'datos\adopcion.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $patron = ($datos.excluir | ForEach-Object { [regex]::Escape($_) }) -join '|'
    $editores = Get-AldiaEditores
    foreach ($p in $Inventario) {
        if ($p.Id -notlike 'ARP\*' -or "$($p.Nombre) $($p.Id)" -match $patron) { continue }
        $nombreLimpio = ConvertTo-AldiaNombreAdopcion $p.Nombre
        if ($nombreLimpio -notmatch '\p{L}{2}' -or $nombreLimpio -match '^[{(]?[0-9a-f]{8}-[0-9a-f-]{27}[})]?$|[\p{Cc}]') { continue }
        $resultado = Get-AldiaCacheSeguridad "adopcion-v1|$nombreLimpio" 168 {
            $r = Invoke-AldiaWinget @('search','--name',$nombreLimpio,'--source','winget','--accept-source-agreements','--disable-interactivity')
            if ($r.Timeout) { throw 'Se agotó el tiempo de búsqueda.' }
            if (('0x{0:X8}' -f ([long]$r.Codigo -band 4294967295L)) -eq '0x8A150014') { return }
            if ($r.Codigo -ne 0) { throw 'No se pudo buscar en winget.' }
            ConvertFrom-AldiaWinget $r.Salida -Busqueda
        } -Directorio $Cache
        $c = Select-AldiaCandidatoAdopcion $p $resultado.Datos $editores["$($p.Nombre)|$($p.Version)"]
        if ($c) { [pscustomobject]@{ Nombre=$p.Nombre; Version=$p.Version; Id=$c.Id; ArpId=$p.Id; Confianza=$c.Confianza } }
    }
}

function Invoke-AldiaAdopcion {
    param($Config, [string]$Id, [switch]$Demo)
    if ($Id -notmatch '^[A-Za-z0-9][A-Za-z0-9._+-]*$') { throw 'Identificador de paquete inválido.' }
    if ($Demo) { return 'Adopción simulada.' }
    $r = Invoke-AldiaWinget @('install','--id',$Id,'--exact','--source','winget','--silent',
        '--accept-package-agreements','--accept-source-agreements','--disable-interactivity') -Timeout ($Config.timeoutMinutosPorPaquete * 60)
    $estado = ConvertTo-AldiaEstadoWinget $r.Codigo -Timeout:$r.Timeout
    if ($estado.Estado -ne 'actualizado') { throw "No se pudo adoptar $Id ($($estado.Codigo)). $($estado.Mensaje)" }
    $lista = Invoke-AldiaWinget @('list','--id',$Id,'--exact','--disable-interactivity')
    $asociado = !$lista.Timeout -and $lista.Codigo -eq 0 -and @(ConvertFrom-AldiaWinget $lista.Salida -ListaCompleta |
        Where-Object { $_.Id -eq $Id -and $_.Origen -eq 'winget' }).Count
    if (!$asociado) { throw 'Winget completó la instalación, pero no se pudo confirmar que vaya a actualizar el programa.' }
    'Hecho: Al Día lo mantendrá actualizado.'
}