function Invoke-AldiaHttp {
    param([string]$Uri, [hashtable]$Headers = @{}, [string]$Body, [string]$Metodo = 'Get', [int]$Timeout = 60)
    # Windows 10 antiguos con .NET 4.x pueden no ofrecer TLS 1.2 por defecto y NVD lo exige.
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    $nvd = ([uri]$Uri).Host -eq 'services.nvd.nist.gov'
    $opciones = @{ Uri=$Uri; Headers=$Headers; TimeoutSec=$Timeout; Method=$Metodo; ErrorAction='Stop'; MaximumRedirection=0 }
    if ($PSBoundParameters.ContainsKey('Body')) {
        $opciones.Method = 'Post'
        $opciones.ContentType = 'application/json'
        $opciones.Body = [Text.Encoding]::UTF8.GetBytes($Body)
    }
    for ($intento=0; $intento -lt 2; $intento++) {
        if ($nvd) {
            $intervalo = if ($Headers.apiKey) { 700 } else { 6500 }
            if ($script:AldiaUltimaNvd) {
                $espera = $intervalo - ([datetime]::UtcNow - $script:AldiaUltimaNvd).TotalMilliseconds
                if ($espera -gt 0) { Start-Sleep -Milliseconds ([int][math]::Ceiling($espera)) }
            }
            $script:AldiaUltimaNvd = [datetime]::UtcNow
        }
        try { return (Invoke-RestMethod @opciones -UseBasicParsing) }
        catch {
            if (!$nvd -or $intento -ne 0 -or [int]$_.Exception.Response.StatusCode -notin 403,429) { throw }
            Start-Sleep -Seconds 30
        }
    }
}

function Get-AldiaCacheSeguridad {
    param([string]$Clave, [int]$Horas, [scriptblock]$Consultar, [string]$Directorio, [switch]$SoloCache)
    $previo = $null
    $ruta = $null
    try {
        Assert-AldiaRutaNormal (Split-Path $Directorio)
        Assert-AldiaRutaNormal $Directorio
        $hash = [Security.Cryptography.SHA256]::Create()
        try { $nombreCache = [BitConverter]::ToString($hash.ComputeHash([Text.Encoding]::UTF8.GetBytes($Clave))).Replace('-','') }
        finally { $hash.Dispose() }
        $ruta = Join-Path $Directorio "$nombreCache.json"
        Assert-AldiaRutaNormal $ruta
        if ([IO.File]::Exists($ruta)) {
            try {
                $registro = [IO.File]::ReadAllText($ruta) | ConvertFrom-Json -ErrorAction Stop
                $edad = ([datetime]::UtcNow - ([datetimeoffset]$registro.Fecha).UtcDateTime).TotalHours
                if ($registro.PSObject.Properties['Datos'] -and $edad -ge 0) { $previo = $registro }
            } catch { }
        }
    } catch { $ruta = $null }
    if ($previo -and $edad -lt $Horas) { return @{ Datos=$previo.Datos; Disponible=$true; Edad=0 } }
    if ($SoloCache -or $soloCacheInforme) {
        if ($previo) { return @{ Datos=$previo.Datos; Disponible=$true; Edad=[int][math]::Ceiling($edad) } }
        return @{ Disponible=$false; Edad=0 }
    }
    try { $datos = & $Consultar }
    catch {
        if ($previo) { return @{ Datos=$previo.Datos; Disponible=$true; Edad=[int][math]::Ceiling($edad) } }
        return @{ Disponible=$false; Edad=0 }
    }
    if ($ruta) {
        $temporal = Join-Path $Directorio ("{0}.tmp" -f [guid]::NewGuid())
        try {
            $null = [IO.Directory]::CreateDirectory($Directorio)
            $json = @{ Fecha=[datetime]::UtcNow.ToString('o'); Datos=$datos } | ConvertTo-Json -Depth 60 -Compress
            [IO.File]::WriteAllText($temporal, $json, [Text.UTF8Encoding]::new($false))
            if ([IO.File]::Exists($ruta)) { [IO.File]::Replace($temporal,$ruta,[NullString]::Value) }
            else { [IO.File]::Move($temporal,$ruta) }
        } catch {}
        finally { try { [IO.File]::Delete($temporal) } catch {} }
    }
    @{ Datos=$datos; Disponible=$true; Edad=0 }
}
