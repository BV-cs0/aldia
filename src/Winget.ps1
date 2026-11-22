function ConvertFrom-AldiaWinget {
    param([string]$Texto, [switch]$Inventario)
    $lineas = @($Texto -split '\r?\n' | ForEach-Object { ($_ -split '\r')[-1] })
    $tabla = 0
    for ($i = 1; $i -lt $lineas.Count; $i++) {
        if ($lineas[$i] -notmatch '^-{10,}\s*$') { continue }
        $pos = @([regex]::Matches($lineas[$i-1], '\S+') | ForEach-Object { $_.Index })
        if ($pos.Count -lt 3 -or (!$Inventario -and $pos.Count -lt 4)) { continue }
        $tabla++
        for ($i++; $i -lt $lineas.Count; $i++) {
            $fila = $lineas[$i]
            if (!$fila.Trim() -or $fila -match '^\s*\d+\s+\p{L}') { break }
            $campos = @(for ($j = 0; $j -lt $pos.Count; $j++) {
                $inicio = [Math]::Min($pos[$j], $fila.Length)
                $fin = $fila.Length
                if ($j + 1 -lt $pos.Count) { $fin = [Math]::Min($pos[$j+1], $fin) }
                $fila.Substring($inicio, $fin - $inicio).Trim()
            })
            $nombre = $campos[0]; $id = $campos[1]; $version = $campos[2]
            $disponible = $campos[3]; $origen = $campos[4]
            if ($Inventario) {
                if ($pos.Count -eq 4) { $origen = $campos[3] }
                $disponible = $null
                if ($id -notmatch '^ARP\\' -or $id -match '\\Steam App \d+$') { continue }
            } else {
                $camposDerecha = '(?<id>\S+)\s+(?<version>(?:[<>]=?\s+)?\S+)\s+(?<disponible>\S+)'
                $m = [regex]::Match($fila, '^(?<nombre>.+?)\s{2,}(?<id>\S+)\s{2,}(?<version>(?:[<>]=?\s+)?\S+)\s{2,}(?<disponible>\S+)(?:\s+(?<origen>\S+))?\s*$')
                if ($fila -match '\s(?:winget|msstore)\s*$' -and (!$m.Success -or !$m.Groups['origen'].Success)) {
                    $m = [regex]::Match($fila, "^(?<nombre>.+?)\s+$camposDerecha\s+(?<origen>\S+)\s*$")
                }
                if (!$m.Success -and (!$id -or $id -match '\s' -or $disponible -match '\s' -or $origen -match '\s')) {
                    $m = [regex]::Match($fila, "^(?<nombre>.+?)\s+$camposDerecha\s*$")
                }
                if ($m.Success) {
                    $nombre = $m.Groups['nombre'].Value; $id = $m.Groups['id'].Value
                    $version = $m.Groups['version'].Value; $disponible = $m.Groups['disponible'].Value
                    $origen = $m.Groups['origen'].Value
                }
            }
            if (!$Inventario -and $id -notmatch '^[A-Za-z0-9][A-Za-z0-9.\-_+]*$') {
                Write-AldiaLog "Se descartó un Id de winget inválido: $id"
                continue
            }
            [pscustomobject]@{
                Nombre = $nombre; Id = $id; Version = $version; Disponible = $disponible; Origen = $origen
                VersionDesconocida = $version -match '^(?:<|Unknown$|Desconocida$|Desconocido$)'
                Explicito = $tabla -gt 1
            }
        }
    }
}

function Get-AldiaApps {
    param($Config, [switch]$Inventario)
    if (!(Get-Command winget.exe -CommandType Application -ErrorAction SilentlyContinue)) {
        Write-AldiaLog 'winget no está disponible.'
        return
    }
    [Console]::OutputEncoding = [Text.Encoding]::UTF8
    $opciones = @('upgrade','--accept-source-agreements','--disable-interactivity')
    if ($Inventario) { $opciones[0] = 'list' }
    elseif ($Config.incluirVersionDesconocida) { $opciones += '--include-unknown' }
    $r = Invoke-AldiaComando winget.exe $opciones
    $hex = '0x{0:X8}' -f ([long]$r.Codigo -band 4294967295L)
    if ($hex -eq '0x8A150014' -or (!$r.Timeout -and $r.Salida -match 'No installed package found matching input criteria|No se encontr.+paquete instalado')) { return }
    if ($r.Timeout -or $r.Codigo -ne 0) { throw "No se pudo consultar winget ($hex). $($r.Error)" }
    ConvertFrom-AldiaWinget $r.Salida -Inventario:$Inventario
}

function ConvertTo-AldiaEstadoWinget {
    param($Codigo, [switch]$Timeout)
    $estado = 'fallo'; $mensaje = ''; $reinicio = $false; $hex = $null
    if ($Timeout) { $estado = 'timeout'; $mensaje = 'Se agotó el tiempo de espera.' }
    else {
        $hex = '0x{0:X8}' -f ([long]$Codigo -band 4294967295L)
        switch ($hex) {
            '0x00000000' { $estado = 'actualizado' }
            '0x8A15002B' { $estado = 'no-aplicable' }
            { $_ -in '0x8A150109','0x8A15010A' } { $estado = 'actualizado'; $reinicio = $true }
            { $_ -in '0x8A150101','0x8A150103' } { $mensaje = 'La aplicación está abierta; ciérrala.' }
            '0x8A150107' { $mensaje = 'Sin red.' }
        }
    }
    New-AldiaResultado apps '' $estado $hex $mensaje -Reinicio $reinicio
}

function Get-AldiaOrdenApps {
    param($Paquetes, $Config)
    $Paquetes | Where-Object {
        !$_.Explicito -and $_.Id -notin $Config.excluir -and ($Config.incluirVersionDesconocida -or !$_.VersionDesconocida)
    } | Sort-Object @{Expression = { [int]($_.Id -ieq 'Microsoft.AppInstaller') }}
}

function Update-AldiaApps {
    param($Config, [switch]$Simular)
    $paquetes = @(Get-AldiaApps $Config)
    $paquetes | Where-Object Explicito | ForEach-Object {
        New-AldiaResultado apps $_.Id explicito $null 'Requiere selección explícita.' $_.Version $_.Disponible -Titulo $_.Nombre
    }
    $resultados = @(foreach ($p in Get-AldiaOrdenApps $paquetes $Config) {
        if ($p.Id -notmatch '^[A-Za-z0-9][A-Za-z0-9.\-_+]*$') { Write-AldiaLog "Se descartó un Id inválido: $($p.Id)"; continue }
        $argumentos = @('upgrade','--id',$p.Id,'--exact')
        if ($p.Origen -match '^[A-Za-z0-9][A-Za-z0-9.\-_+]*$') { $argumentos += @('--source',$p.Origen) }
        $argumentos += @('--silent','--accept-package-agreements','--accept-source-agreements','--disable-interactivity')
        if ($p.VersionDesconocida) { $argumentos += '--include-unknown' }
        try {
            $r = Invoke-AldiaComando winget.exe $argumentos -Timeout ($Config.timeoutMinutosPorPaquete * 60) -Simular:$Simular
            if ($Simular) {
                New-AldiaResultado apps $p.Id simulado $null '' $p.Version $p.Disponible -Titulo $p.Nombre
                continue
            }
            $resultado = ConvertTo-AldiaEstadoWinget $r.Codigo -Timeout:$r.Timeout
            if ($directorioLog) {
                [IO.Directory]::CreateDirectory($directorioLog) > $null
                $nombreLog = 'winget-{0}-{1}.log' -f ([guid]::NewGuid()), $p.Id
                [IO.File]::WriteAllLines((Join-Path $directorioLog $nombreLog), [string[]]@($resultado.Codigo,$r.Salida,$r.Error), [Text.Encoding]::UTF8)
            }
        } catch { $resultado = New-AldiaResultado apps $p.Id fallo $null $_.Exception.Message }
        $resultado.Id = $p.Id; $resultado.Titulo = $p.Nombre
        $resultado.Antes = $p.Version; $resultado.Despues = $p.Disponible
        $resultado
    })
    if (!$Simular -and $resultados.Count) {
        try {
            $pendientes = @(Get-AldiaApps $Config)
            foreach ($r in $resultados) {
                if (@($pendientes | Where-Object { $_.Id -eq $r.Id -and $_.Disponible -eq $r.Despues }).Count) {
                    $r | Add-Member -NotePropertyName Persistente -NotePropertyValue $true
                    if ($r.Estado -eq 'actualizado') { $r.Estado = 'persistente' }
                    $r.Mensaje = ("$($r.Mensaje) Sigue pendiente la misma versión.").Trim()
                }
            }
        } catch {
            New-AldiaResultado apps 'consulta-final' fallo $null $_.Exception.Message
        }
    }
    $resultados
}
