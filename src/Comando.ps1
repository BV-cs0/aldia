function ConvertTo-AldiaArgumento {
    param([AllowEmptyString()][string]$Valor)
    if ($Valor -and $Valor -notmatch '[\s"]') { return $Valor }
    '"' + (($Valor -replace '(\\*)"', '$1$1\"') -replace '(\\+)$', '$1$1') + '"'
}

function Invoke-AldiaComando {
    param(
        [Parameter(Mandatory)][string]$Ejecutable,
        [string[]]$Argumentos,
        [ValidateRange(1,2147483)][int]$Timeout = 120,
        [switch]$Simular, [switch]$Elevar, [switch]$Visible
    )
    $linea = ($Argumentos | ForEach-Object { ConvertTo-AldiaArgumento $_ }) -join ' '
    if ($Simular) {
        Write-Host "$(ConvertTo-AldiaArgumento $Ejecutable) $linea"
        return [pscustomobject]@{ Codigo = 0; Salida = ''; Error = ''; Timeout = $false }
    }
    $info = New-Object Diagnostics.ProcessStartInfo
    $info.FileName = $Ejecutable
    $info.Arguments = $linea
    $info.UseShellExecute = [bool]($Elevar -or $Visible)
    if ($Elevar) { $info.Verb = 'RunAs' }
    if (!$info.UseShellExecute) {
        if ([IO.Path]::GetExtension($Ejecutable) -ieq '.cmd') {
            # Solo se admiten argumentos literales en el intérprete de npm.
            if ($Ejecutable -match '[%"!\r\n]' -or @($Argumentos | Where-Object { $_ -notmatch '^[A-Za-z0-9@/_.+-]+$' }).Count) {
                throw 'Argumentos no seguros para un archivo CMD.'
            }
            $info.FileName = $env:ComSpec
            $info.Arguments = '/d /v:off /s /c ""' + $Ejecutable + '" ' + $linea + '"'
        }
        $info.CreateNoWindow = $true
        $info.RedirectStandardOutput = $true
        $info.RedirectStandardError = $true
        $info.StandardOutputEncoding = [Text.Encoding]::UTF8
        $info.StandardErrorEncoding = [Text.Encoding]::UTF8
    }
    $proceso = if ($Elevar) {
        Start-Process -FilePath $Ejecutable -ArgumentList $linea -Verb RunAs -PassThru -ErrorAction Stop
    } else { [Diagnostics.Process]::Start($info) }
    try {
        if ($Elevar) { $null = $proceso.Handle }
        if ($Visible) { return [pscustomobject]@{ Codigo = 0; Salida = ''; Error = ''; Timeout = $false } }
        if (!$info.UseShellExecute) {
            $salida = $proceso.StandardOutput.ReadToEndAsync()
            $errores = $proceso.StandardError.ReadToEndAsync()
        }
        $limite = !$proceso.WaitForExit($Timeout * 1000)
        if ($limite) { try { $proceso.Kill() } catch { if (!$proceso.HasExited) { throw } } }
        [pscustomobject]@{
            Codigo = $(if (!$limite) { $proceso.ExitCode })
            Salida = if ($salida -and $salida.Wait(1000)) { $salida.Result } else { '' }
            Error = if ($errores -and $errores.Wait(1000)) { $errores.Result } else { '' }
            Timeout = $limite
        }
    } finally { $proceso.Dispose() }
}

function Test-AldiaAdmin {
    $identidad = [Security.Principal.WindowsIdentity]::GetCurrent()
    (New-Object Security.Principal.WindowsPrincipal $identidad).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Invoke-AldiaWindowsPowerShell {
    param([string]$CodigoPowerShell)
    $ps = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $base64 = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($CodigoPowerShell))
    $r = Invoke-AldiaComando $ps @('-NoProfile','-NonInteractive','-EncodedCommand',$base64)
    if ($r.Timeout -or $r.Codigo -ne 0) {
        throw "Windows PowerShell no completó la operación (código $($r.Codigo))."
    }
}
