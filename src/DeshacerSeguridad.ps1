function Get-AldiaAvisoDeshacer {
    param($Resultado,[string]$Version,[string]$Cache=(Join-Path $env:ProgramData 'Aldia\cache'))
    $soloCacheInforme = $true
    try {
        $consulta = switch ($Resultado.Fuente) {
            apps {
                $programa = @{ Id=$Resultado.Id; Nombre=$Resultado.Titulo; Version=$Version }
                $semillas = Get-Content -LiteralPath (Join-Path (Split-Path $PSScriptRoot) 'datos\cpe.json') -Raw -Encoding UTF8 | ConvertFrom-Json
                $cpe = Get-AldiaCpe $programa $semillas @{} $Cache
                if ($cpe.Datos) { Get-AldiaCvesNvd $cpe.Datos $Version @{} $Cache }
            }
            npm {
                $osv = Get-AldiaOsv @(@{ Id=$Resultado.Id; Version=$Version }) $Cache
                $osv[$Resultado.Id]
            }
        }
        $ids = @($consulta.Datos | Where-Object Id -match '^CVE-\d{4}-\d{4,}$' | ForEach-Object { $_.Id } | Sort-Object -Unique)
        if ($ids.Count) {
            $lista = ($ids | Select-Object -First 5) -join ', '
            if ($ids.Count -gt 5) { $lista += " y $($ids.Count - 5) más" }
            "Ojo: la versión anterior tiene fallos de seguridad conocidos ($lista). Vuelve a ella solo si la nueva te da problemas."
        }
    } catch {}
}