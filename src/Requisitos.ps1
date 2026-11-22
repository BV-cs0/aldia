$script:AldiaSinWinget = 'Falta el Instalador de aplicaciones de Microsoft. Sin él, Al Día no puede actualizar los programas (Windows Update y los drivers sí funcionan).'
$script:AldiaSinInternet = 'No hay internet. Conéctate y pulsa Revisar.'
$script:AldiaDiscoBajo = 'Quedan menos de 5 GB libres en la unidad de Windows.'

function Get-AldiaRutaWinget {
    $comando = Get-Command winget.exe -CommandType Application -ErrorAction SilentlyContinue
    if ($comando) { return $comando.Source }
    if ($env:LOCALAPPDATA) {
        $ruta = Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\winget.exe'
        if (Test-Path -LiteralPath $ruta -PathType Leaf) { $ruta }
    }
}

function Get-AldiaEstadoWinget {
    $estado = [pscustomobject]@{ Estado='ausente'; Version=$null; Mensaje=$script:AldiaSinWinget }
    if (Get-AldiaRutaWinget) {
        try {
            # La ayuda incluye la versión y no abre ningún catálogo.
            $r = Invoke-AldiaWinget @('list','--help') -Timeout 10
            if (!$r.Timeout -and $r.Codigo -eq 0 -and $r.Salida -match '(?im)^\s*(?:[^\r\n]*\s)?v(\d+\.\d+(?:\.\d+){0,2})\b') {
                $estado.Version = [version]$Matches[1]
                if ($estado.Version -lt [version]'1.6') {
                    $estado.Estado = 'antiguo'; $estado.Mensaje = 'El Instalador de aplicaciones de Microsoft necesita una actualización.'
                } else { $estado.Estado = 'ok'; $estado.Mensaje = '' }
            }
        } catch {}
    }
    $estado
}

function Test-AldiaCuentaAdmin {
    if (Test-AldiaAdmin) { return $true }
    $identidad = [Security.Principal.WindowsIdentity]::GetCurrent()
    if ($identidad.Groups.Value -contains 'S-1-5-32-544') { return $true }
    try {
        # El token sin elevar puede mostrar este grupo solo como de denegación.
        $r = Invoke-AldiaComando (Join-Path $env:SystemRoot 'System32\whoami.exe') @('/groups','/fo','csv','/nh') -Timeout 5
        !$r.Timeout -and $r.Codigo -eq 0 -and $r.Salida -match '"S-1-5-32-544"'
    } catch { $false }
}

function Test-AldiaInternet {
    # Misma prueba que usa Windows (NCSI). Va por HTTP a propósito: su HTTPS no tiene un certificado
    # válido para ese nombre. Si una red la bloquea, se prueba una web HTTPS de Microsoft.
    try {
        $r = Invoke-WebRequest 'http://www.msftconnecttest.com/connecttest.txt' -UseBasicParsing -TimeoutSec 5 -MaximumRedirection 0 -ErrorAction Stop
        if ($r.Content -match 'Microsoft Connect Test') { return $true }
    } catch {}
    try {
        $null = Invoke-WebRequest 'https://www.microsoft.com/' -Method Head -UseBasicParsing -TimeoutSec 8 -ErrorAction Stop
        $true
    } catch { $false }
}

function Get-AldiaCosteInternet {
    try {
        $perfil = [Windows.Networking.Connectivity.NetworkInformation,Windows.Networking.Connectivity,ContentType=WindowsRuntime]::GetInternetConnectionProfile()
        if ($perfil) {
            $coste = $perfil.GetConnectionCost()
            if ($coste.NetworkCostType -in 'Fixed','Variable' -or $coste.Roaming -or $coste.OverDataLimit) { return 'medido' }
            if ($coste.NetworkCostType -eq 'Unrestricted') { return 'normal' }
        }
    } catch {}
    'desconocido'
}

function Test-AldiaDiscoBajo {
    try {
        $disco = Get-AldiaDiscoSalud
        $null -ne $disco.FreeSpace -and $disco.FreeSpace -lt 5GB
    } catch { $false }
}

function Test-AldiaMaquinaVirtual {
    param($Equipo = (Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue))
    "$($Equipo.Manufacturer) $($Equipo.Model)" -match 'VMware|VirtualBox|Virtual Machine|Hyper-V|QEMU|Parallels|Xen'
}

function Invoke-AldiaWinget {
    param([string[]]$Argumentos, [int]$Timeout=120, [switch]$Simular)
    foreach ($opcion in '--accept-source-agreements','--disable-interactivity') {
        if ($opcion -notin $Argumentos) { $Argumentos += $opcion }
    }
    $r = Invoke-AldiaComando winget.exe $Argumentos -Timeout $Timeout -Simular:$Simular
    $origen = [array]::IndexOf($Argumentos,'--source')
    $codigo = '0x{0:X8}' -f ([long]$r.Codigo -band 4294967295L)
    if (!$Simular -and !$r.Timeout -and $codigo -in '0x8A15000F','0x8A150044' -and
        ($origen -lt 0 -or $Argumentos[$origen + 1] -eq 'msstore')) {
        Write-AldiaLog 'No se pudo consultar Microsoft Store. Se vuelve a intentar con el catálogo de programas.'
        if ($origen -lt 0) { $Argumentos += @('--source','winget') }
        else {
            $Argumentos = $Argumentos.Clone()
            $Argumentos[$origen + 1] = 'winget'
        }
        $r = Invoke-AldiaComando winget.exe $Argumentos -Timeout $Timeout
    }
    $r
}