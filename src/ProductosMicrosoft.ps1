$script:AldiaMicrosoftUpdateId = '7971f918-a847-4430-9279-4a52d1efe18d'

function Get-AldiaOffice {
    $registro = Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration' -ErrorAction SilentlyContinue
    if (!$registro.VersionToReport) {
        $registro = Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Office\ClickToRun\Configuration' -ErrorAction SilentlyContinue
    }
    if ($registro.VersionToReport) {
        [pscustomobject]@{ Id='Office'; Nombre='Microsoft 365 / Office'; Version=$registro.VersionToReport
            Canal=$registro.CDNBaseUrl; Detalle='Buscar e instalar actualizaciones de Office' }
    }
}

function Get-AldiaStore {
    [pscustomobject]@{ Id='Store'; Nombre='Apps de Microsoft Store'; Detalle='Buscar actualizaciones en Microsoft Store' }
}

function Update-AldiaOffice {
    param($Config, [switch]$Simular)
    $office = Get-AldiaOffice
    if (!$office) { return }
    $cliente = foreach ($carpeta in @($env:CommonProgramW6432,$env:CommonProgramFiles,[Environment]::GetEnvironmentVariable('CommonProgramFiles(x86)')) | Where-Object { $_ } | Select-Object -Unique) {
        $ruta = Join-Path $carpeta 'microsoft shared\ClickToRun\OfficeC2RClient.exe'
        if (Test-Path -LiteralPath $ruta -PathType Leaf) { $ruta; break }
    }
    if (!$cliente) { return (New-AldiaResultado office Office omitido $null 'No se encontró el programa que actualiza Office.' -Titulo $office.Nombre) }
    $reloj = [Diagnostics.Stopwatch]::StartNew()
    $limite = $Config.timeoutMinutosPorPaquete * 60
    $r = Invoke-AldiaComando $cliente @('/update','user','displaylevel=false','forceappshutdown=false') -Timeout $limite -Simular:$Simular
    if ($Simular) { return (New-AldiaResultado office Office simulado $null '' -Titulo $office.Nombre) }
    if ($r.Timeout -or $r.Codigo -ne 0) {
        return (New-AldiaResultado office Office fallo $r.Codigo 'No se pudo iniciar la actualización de Office.' -Titulo $office.Nombre)
    }
    do {
        $version = (Get-AldiaOffice).Version
        if ($version -and $version -ne $office.Version) {
            return (New-AldiaResultado office Office actualizado 0 '' $office.Version $version -Titulo $office.Nombre)
        }
        $restante = $limite - $reloj.Elapsed.TotalSeconds
        if ($restante -gt 0) { Start-Sleep -Milliseconds ([int]([math]::Min(5,$restante)*1000)) }
    } while ($restante -gt 0)
    New-AldiaResultado office Office aviso $null 'Office ya estaba al día o se actualizará al cerrar sus programas.' $office.Version $office.Version -Titulo $office.Nombre
}

function Update-AldiaStore {
    param([switch]$Simular)
    $titulo = (Get-AldiaStore).Nombre
    if ($Simular) {
        Write-Host 'Get-CimInstance -Namespace root\cimv2\mdm\dmmap -ClassName MDM_EnterpriseModernAppManagement_AppManagement01 | Invoke-CimMethod -MethodName UpdateScanMethod'
        return (New-AldiaResultado store Store simulado $null '' -Titulo $titulo)
    }
    try {
        if (!(Test-AldiaAdmin)) { throw 'Windows necesita permiso de administrador.' }
        $app = Get-CimInstance -Namespace 'root\cimv2\mdm\dmmap' -ClassName MDM_EnterpriseModernAppManagement_AppManagement01 -ErrorAction Stop
        if (!$app) { throw 'Microsoft Store no está disponible.' }
        $r = $app | Invoke-CimMethod -MethodName UpdateScanMethod -ErrorAction Stop
        if ($r.ReturnValue -ne 0) { throw "Microsoft Store devolvió el código $($r.ReturnValue)." }
        New-AldiaResultado store Store aviso 0 'Microsoft Store buscará actualizaciones.' -Titulo $titulo
    } catch { New-AldiaResultado store Store omitido $null "No se pudo pedir a Microsoft Store que revise las apps. $($_.Exception.Message)" -Titulo $titulo }
}

function New-AldiaServiciosWU { New-Object -ComObject Microsoft.Update.ServiceManager }

function Test-AldiaMicrosoftUpdate {
    $servicios = New-AldiaServiciosWU
    foreach ($servicio in $servicios.Services) {
        if ($servicio.ServiceID -eq $script:AldiaMicrosoftUpdateId) { return $true }
    }
    $false
}

function Test-AldiaEquipoGestionado {
    $politica = Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate' -ErrorAction SilentlyContinue
    if ($politica.WUServer) { return $true }
    try {
        $r = Invoke-AldiaComando (Join-Path $env:SystemRoot 'System32\dsregcmd.exe') @('/status') -Timeout 10
        !$r.Timeout -and $r.Codigo -eq 0 -and $r.Salida -match '(?m)^\s*(AzureAdJoined|DomainJoined)\s*:\s*YES\s*$'
    } catch { $false }
}

function Get-AldiaSaludMicrosoft {
    $gestionado = Test-AldiaEquipoGestionado
    if ($gestionado) {
        [pscustomobject]@{ Id='gestion'; Nombre='Equipo de empresa'; Estado='aviso'
            Detalle='Este PC lo gestiona una empresa: algunas actualizaciones las controla su departamento de informática.' }
    }
    try {
        if (!(Test-AldiaMicrosoftUpdate) -and !$gestionado) {
            [pscustomobject]@{ Id='microsoftUpdate'; Nombre='Recibir también actualizaciones de otros programas de Microsoft'
                Estado='aviso'; Detalle='Puedes buscarlas junto con las actualizaciones de Windows.'; Accion='Activar' }
        }
    } catch {}
}