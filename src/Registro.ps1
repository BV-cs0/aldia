function Write-AldiaLog {
    param([string]$Mensaje)
    if ($directorioLog) {
        [IO.Directory]::CreateDirectory($directorioLog) > $null
        $ruta = Join-Path $directorioLog ('aldia-{0:yyyy-MM-dd}.log' -f (Get-Date))
        [IO.File]::AppendAllText($ruta, ('{0:o} {1}{2}' -f (Get-Date), $Mensaje, [Environment]::NewLine), [Text.Encoding]::UTF8)
    } elseif (!$programado) { Write-Warning $Mensaje }
}

function Read-AldiaHistorial {
    param([string]$Ruta)
    if (Test-Path -LiteralPath $Ruta) {
        Get-Content -LiteralPath $Ruta -Encoding UTF8 | ForEach-Object {
            try { if ($_.Trim()) { ConvertFrom-Json -InputObject $_ -ErrorAction Stop } }
            catch { Write-AldiaLog 'Se omitió una línea ilegible del historial.' }
        }
    }
}

function Add-AldiaHistorial {
    param([string]$Ruta, $Entrada)
    [IO.Directory]::CreateDirectory((Split-Path $Ruta)) > $null
    [IO.File]::AppendAllText($Ruta, (($Entrada | ConvertTo-Json -Depth 10 -Compress) + [Environment]::NewLine), [Text.UTF8Encoding]::new($false))
}

function Clear-AldiaLogs {
    param([string]$Ruta, [int]$Dias)
    if (Test-Path -LiteralPath $Ruta) {
        Get-ChildItem -LiteralPath $Ruta -Filter '*.log' -File |
            Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-$Dias) } |
            Remove-Item -ErrorAction Stop
    }
}

function New-AldiaResultado {
    param($Fuente, $Id, $Estado, $Codigo, $Mensaje, $Antes, $Despues, [bool]$Reinicio, $Titulo)
    [pscustomobject]@{
        Fuente = $Fuente; Id = $Id; Titulo = $Titulo; Antes = $Antes; Despues = $Despues
        Estado = $Estado; Codigo = $Codigo; Mensaje = $Mensaje; RequiereReinicio = $Reinicio
    }
}
