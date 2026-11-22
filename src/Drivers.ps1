# Patrón del equipo, herramienta, DisplayName, Id de winget y URL oficial.
$script:AldiaFabricantes = @(
    ,@('Dell','Dell Command Update','^Dell Command \| Update','Dell.CommandUpdate','https://www.dell.com/support/kbdoc/en-us/000177325/dell-command-update')
    ,@('Lenovo','Lenovo System Update','^Lenovo System Update','Lenovo.SystemUpdate','https://support.lenovo.com/solutions/ht003029')
    ,@('\bHP\b|Hewlett','HP Support Assistant','^HP Support Assistant','HP.SupportAssistant','https://support.hp.com/help/hp-support-assistant')
    ,@('ASUS','MyASUS','^MyASUS','9N7R5S6B0ZZH','https://www.asus.com/support/myasus-deeplink/')
    ,@('MSI|Micro-Star','MSI Center','^MSI Center','MSI.MSICenter','https://www.msi.com/Landing/MSI-Center')
    ,@('GIGABYTE','GIGABYTE Control Center','^GIGABYTE Control Center',$null,'https://www.gigabyte.com/Consumer/Software/GIGABYTE-Control-Center/global')
    ,@('NVIDIA','NVIDIA App','^NVIDIA App \d','XP8CLZL93F5Z4P','https://www.nvidia.com/software/nvidia-app/')
    ,@('AMD|Radeon','AMD Software Adrenalin','^AMD Software',$null,'https://www.amd.com/en/products/software/adrenalin.html')
    ,@('Intel','Intel Driver & Support Assistant','^Intel.*Driver (&|and) Support Assistant','Intel.IntelDriverAndSupportAssistant','https://www.intel.com/content/www/us/en/support/detect.html')
)

function Get-AldiaProblemasPnP {
    $mensajes = @{
        1='no configurado'; 3='driver dañado o recursos insuficientes'; 10='no puede iniciarse'
        18='hay que reinstalar el driver'; 22='desactivado'; 24='ausente o no funciona'
        28='no tiene driver instalado'; 31='Windows no puede cargar el driver'
        39='driver dañado o ausente'; 43='el dispositivo informó de un error'; 45='no conectado'
    }
    foreach ($d in Get-CimInstance Win32_PnPEntity -Filter 'ConfigManagerErrorCode <> 0' -ErrorAction Stop) {
        $codigo = [int]$d.ConfigManagerErrorCode
        if (!$codigo) { continue }
        $mensaje = if ($mensajes.ContainsKey($codigo)) { $mensajes[$codigo] } else { 'error de configuración del dispositivo' }
        [pscustomobject]@{ Nombre = $d.Name; Clase = $d.PNPClass; Codigo = $codigo
            Mensaje = $mensaje; Problema = $codigo -notin 22,45; HardwareID = @($d.HardwareID)[0] }
    }
}

function Get-AldiaDriversWU {
    param($Sesion, $Config)
    Find-AldiaActualizacionesWU $Sesion Driver | Where-Object { $_.DriverClass -notin $Config.drivers.excluirClases }
}

function Get-AldiaGpu {
    Get-CimInstance Win32_VideoController -ErrorAction Stop |
        Where-Object { $_.Name -notmatch 'Microsoft Basic|Virtual|Remote' }
}

function Get-AldiaGpuAntiguas {
    param($Gpu, [datetime]$Ahora = (Get-Date))
    foreach ($g in $Gpu) {
        if ($g.Name -match 'Microsoft Basic|Virtual|Remote' -or !$g.DriverDate) { continue }
        try {
            $fecha = if ($g.DriverDate -is [datetime]) { $g.DriverDate }
            else { [Management.ManagementDateTimeConverter]::ToDateTime($g.DriverDate) }
            if ($fecha -lt $Ahora.AddMonths(-12)) {
                [pscustomobject]@{ Nombre = $g.Name; Fecha = $fecha; Aviso = 'Driver de GPU con más de 12 meses.' }
            }
        } catch { Write-AldiaLog "No se pudo interpretar la fecha del driver de $($g.Name)." }
    }
}

function Get-AldiaDell {
    foreach ($raiz in @($env:ProgramFiles, [Environment]::GetEnvironmentVariable('ProgramFiles(x86)')) | Select-Object -Unique) {
        if (!$raiz) { continue }
        $ruta = Join-Path $raiz 'Dell\CommandUpdate\dcu-cli.exe'
        if (Test-Path -LiteralPath $ruta -PathType Leaf) { return $ruta }
    }
}

function Get-AldiaRecomendaciones {
    param($Gpu = @(Get-AldiaGpu))
    $marca = (Get-CimInstance Win32_ComputerSystem -ErrorAction Stop).Manufacturer
    $modelos = @($Gpu.Name) + @($Gpu.AdapterCompatibility)
    $rutas = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    $instaladas = @(Get-ItemProperty -Path $rutas -ErrorAction SilentlyContinue)
    foreach ($fabricante in $script:AldiaFabricantes) {
        $patron, $nombre, $displayName, $id, $url = $fabricante
        $equipo = if ($marca -match $patron) { "equipo $marca" }
            else {
                $modelo = $modelos -match $patron | Select-Object -First 1
                if ($modelo) { "GPU $modelo" }
            }
        if (!$equipo) { continue }
        $instalada = $instaladas | Where-Object { $_.DisplayName -match $displayName } | Select-Object -First 1
        $estado = if ($instalada) { 'sí' } else { 'no' }
        $como = if ($id) { "winget install --id $id --exact" } else { $url }
        [pscustomobject]@{ Herramienta = $nombre; Instalado = $estado; Version = $instalada.DisplayVersion; ComoConseguirla = $como; Id = $id; Url = $url; Equipo = $equipo }
    }
}

function Update-AldiaDrivers {
    param($Config, [switch]$Simular)
    try {
        $sesion = New-AldiaSesionWU
        Update-AldiaWU $sesion @(Get-AldiaDriversWU $sesion $Config) drivers -Simular:$Simular
    } catch { New-AldiaResultado drivers 'Windows Update' fallo $null $_.Exception.Message }
    $dell = Get-AldiaDell
    if ($dell) {
        try {
            $r = Invoke-AldiaComando $dell @('/applyUpdates','-silent','-reboot=disable') -Timeout ($Config.timeoutMinutosPorPaquete * 60) -Simular:$Simular
            if ($Simular) {
                New-AldiaResultado drivers 'Dell Command Update' simulado $null ''
            } else {
                $estado = if ($r.Timeout) { 'timeout' } elseif ($r.Codigo -in 0,1) { 'actualizado' } elseif ($r.Codigo -eq 500) { 'no-aplicable' } else { 'fallo' }
                New-AldiaResultado drivers 'Dell Command Update' $estado $r.Codigo $r.Error -Reinicio ($r.Codigo -eq 1)
            }
        } catch { New-AldiaResultado drivers 'Dell Command Update' fallo $null $_.Exception.Message }
    }
    if ($Config.drivers.rescanearDispositivos) {
        try {
            $r = Invoke-AldiaComando (Join-Path $env:SystemRoot 'System32\pnputil.exe') @('/scan-devices') -Simular:$Simular
            if ($r.Timeout -or $r.Codigo -ne 0) { New-AldiaResultado drivers 'pnputil' aviso $r.Codigo 'No se pudo volver a detectar los dispositivos.' }
        } catch { New-AldiaResultado drivers 'pnputil' aviso $null $_.Exception.Message }
    }
    foreach ($d in Get-AldiaProblemasPnP | Where-Object Codigo -eq 28) {
        New-AldiaResultado drivers $d.HardwareID aviso 28 "Windows no tiene driver para «$($d.Nombre)». Búscalo en la web del fabricante con este ID: $($d.HardwareID)" -Titulo $d.Nombre
    }
}
