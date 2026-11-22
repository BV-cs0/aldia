function Get-AldiaConfig {
    param([string]$Ruta, [string]$Raiz = (Split-Path $PSScriptRoot))
    $defecto = Get-Content -LiteralPath (Join-Path $Raiz 'config.default.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    if (!$Ruta -or !(Test-Path -LiteralPath $Ruta)) { return $defecto }
    try {
        $datos = Get-Content -LiteralPath $Ruta -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($datos -isnot [pscustomobject]) { throw 'Se esperaba un objeto JSON.' }
        Merge-AldiaConfig $defecto $datos
    } catch { Write-AldiaLog "Configuración inválida: $_" }
    return $defecto
}

function Merge-AldiaConfig {
    param($Defecto, $Datos, [string]$Prefijo)
    foreach ($prop in $Datos.PSObject.Properties) {
        $clave = $prop.Name
        $ruta = "$Prefijo$clave"
        $base = $Defecto.PSObject.Properties[$clave]
        $valor = $prop.Value
        if (!$base) { Write-AldiaLog "Clave desconocida: $ruta"; continue }
        $valido = $false
        if ($base.Value -is [pscustomobject]) {
            if ($valor -is [pscustomobject]) { Merge-AldiaConfig $base.Value $valor "$ruta."; continue }
        } elseif ($base.Value -is [array]) {
            $valido = $valor -is [array] -and @($valor | Where-Object { $_ -isnot [string] }).Count -eq 0
        } elseif ($base.Value -is [bool]) {
            $valido = $valor -is [bool]
        } elseif ($base.Value -is [string]) {
            $valido = $valor -is [string] -and $(switch ($clave) {
                'horaDiaria' { (Test-AldiaHora $valor) }
                'notificar' { $valor -cin @('siempre','solo-cambios','solo-errores','nunca') }
            })
        } else {
            $valido = ($valor -is [int] -or $valor -is [long]) -and $valor -ge 0 -and $valor -le [int]::MaxValue
            if ($clave -eq 'bateriaMinima') { $valido = $valido -and $valor -le 100 }
            if ($clave -eq 'timeoutMinutosPorPaquete') { $valido = $valido -and $valor -ge 1 -and $valor -le 35791 }
        }
        if ($valido) { $base.Value = $valor } else { Write-AldiaLog "Valor inválido: $ruta" }
    }
}


function Test-AldiaHora {
    param($Valor)
    $Valor -is [string] -and $Valor -cmatch '\A(?:[01][0-9]|2[0-3]):[0-5][0-9]\z'
}