function Get-AldiaProgramFiles {
    $raiz = $env:ProgramW6432
    if (!$raiz) { $raiz = $env:ProgramFiles }
    Join-Path $raiz 'Aldia'
}

function Connect-AldiaTareas {
    $servicio = New-Object -ComObject Schedule.Service
    $servicio.Connect()
    $servicio
}

function Register-AldiaTarea {
    param([string]$Programa, $Config, [switch]$Deshabilitada)
    $servicio = Connect-AldiaTareas
    try { $carpeta = $servicio.GetFolder('\Aldia') }
    catch { $carpeta = $servicio.GetFolder('\').CreateFolder('Aldia') }
    $t = $servicio.NewTask(0)
    $usuario = [Security.Principal.WindowsIdentity]::GetCurrent().Name
    $t.Principal.UserId = $usuario
    $t.Principal.LogonType = 3
    $t.Principal.RunLevel = 1
    $t.Settings.Enabled = !$Deshabilitada
    $t.Settings.StartWhenAvailable = $true
    $t.Settings.RunOnlyIfNetworkAvailable = $true
    $t.Settings.DisallowStartIfOnBatteries = $false
    $t.Settings.StopIfGoingOnBatteries = $false
    $t.Settings.MultipleInstances = 2
    $t.Settings.ExecutionTimeLimit = 'PT3H'
    $diario = $t.Triggers.Create(2)
    $diario.StartBoundary = ((Get-Date).Date.Add([timespan]::ParseExact($Config.horaDiaria,'hh\:mm',[cultureinfo]::InvariantCulture))).ToString('yyyy-MM-ddTHH:mm:ss')
    $diario.DaysInterval = 1
    $diario.Repetition.Interval = 'PT1H'
    $diario.Repetition.Duration = 'PT12H'
    $sesion = $t.Triggers.Create(9)
    $sesion.UserId = $usuario
    $sesion.Delay = 'PT15M'
    $accion = $t.Actions.Create(0)
    $accion.Path = Join-Path $env:SystemRoot 'System32\conhost.exe'
    $ps = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $entrada = Join-Path $Programa 'aldia.ps1'
    $accion.WorkingDirectory = $Programa
    $accion.Arguments = "--headless " + (ConvertTo-AldiaArgumento $ps) + ' -NoProfile -ExecutionPolicy Bypass -File "' + $entrada + '" actualizar --programado'
    $null = $carpeta.RegisterTaskDefinition('Al Día',$t,6,$usuario,$null,3,$null)
}

function Assert-AldiaRutaNormal {
    param([string]$Ruta)
    if ((Test-Path -LiteralPath $Ruta) -and ((Get-Item -LiteralPath $Ruta -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw "Se rechazó un punto de reanálisis: $Ruta"
    }
}

function New-AldiaDirectorioProtegido {
    param([string]$Ruta)
    Assert-AldiaRutaNormal $Ruta
    if (Test-Path -LiteralPath $Ruta) {
        Assert-AldiaPermisos $Ruta
        return
    }
    $seguridad = [Security.AccessControl.DirectorySecurity]::new()
    $seguridad.SetAccessRuleProtection($true,$false)
    $seguridad.SetOwner([Security.Principal.SecurityIdentifier]::new('S-1-5-32-544'))
    foreach ($sid in 'S-1-5-18','S-1-5-32-544','S-1-5-32-545') {
        $derechos = if ($sid -eq 'S-1-5-32-545') { 'ReadAndExecute' } else { 'FullControl' }
        $regla = [Security.AccessControl.FileSystemAccessRule]::new(
            [Security.Principal.SecurityIdentifier]::new($sid), $derechos, 'ContainerInherit,ObjectInherit', 'None', 'Allow')
        $seguridad.AddAccessRule($regla)
    }
    $null = [IO.Directory]::CreateDirectory($Ruta)
    Set-Acl -LiteralPath $Ruta -AclObject $seguridad -ErrorAction Stop
}

function Assert-AldiaPermisos {
    param([string]$Ruta)
    Assert-AldiaRutaNormal $Ruta
    $acl = Get-Acl -LiteralPath $Ruta -ErrorAction Stop
    $administradores = @('S-1-5-18','S-1-5-32-544')
    $tipoSid = [Security.Principal.SecurityIdentifier]
    if ($acl.GetOwner($tipoSid).Value -notin $administradores) { throw "Propietario no administrativo: $Ruta" }
    $escritura = [Security.AccessControl.FileSystemRights]'Write,Modify,ChangePermissions,TakeOwnership,Delete,DeleteSubdirectoriesAndFiles'
    # Excluir los bits de lectura y ejecución que también están incluidos en Modify.
    $escritura = $escritura -band (-bnot [int][Security.AccessControl.FileSystemRights]::ReadAndExecute)
    foreach ($regla in $acl.GetAccessRules($true,$true,$tipoSid)) {
        if ($regla.AccessControlType -eq 'Allow' -and $regla.IdentityReference.Value -notin $administradores -and
            ($regla.FileSystemRights -band $escritura)) { throw "Permisos de escritura no administrativos: $Ruta" }
    }
}

function Set-AldiaPropietarioAdmin {
    param([string]$Ruta)
    $acl = Get-Acl -LiteralPath $Ruta -ErrorAction Stop
    $acl.SetOwner([Security.Principal.SecurityIdentifier]::new('S-1-5-32-544'))
    Set-Acl -LiteralPath $Ruta -AclObject $acl -ErrorAction Stop
}

function Install-Aldia {
    param([string]$Origen)
    $destino = Get-AldiaProgramFiles
    New-AldiaDirectorioProtegido $destino
    if ($Origen.TrimEnd('\') -ine $destino.TrimEnd('\')) {
        $fuentes = @('aldia.ps1','Aldia.psd1','Aldia.psm1','config.default.json','README.md','gui\Principal.xaml','datos\cpe.json','datos\adopcion.json')
        $fuentes += @(Get-ChildItem -LiteralPath (Join-Path $Origen 'src') -Filter '*.ps1' -File | ForEach-Object { Join-Path 'src' $_.Name })
        $src = Join-Path $destino 'src'
        New-AldiaDirectorioProtegido $src
        New-AldiaDirectorioProtegido (Join-Path $destino 'gui')
        New-AldiaDirectorioProtegido (Join-Path $destino 'datos')
        foreach ($archivo in $fuentes) {
            $objetivo = Join-Path $destino $archivo
            if (Test-Path -LiteralPath $objetivo) { Assert-AldiaPermisos $objetivo }
            Copy-Item -LiteralPath (Join-Path $Origen $archivo) -Destination $objetivo -Force -ErrorAction Stop
            Set-AldiaPropietarioAdmin $objetivo
        }
    }
    $ruta = Join-Path $destino 'config.json'
    Assert-AldiaRutaNormal $ruta
    if (!(Test-Path -LiteralPath $ruta)) {
        Copy-Item -LiteralPath (Join-Path $destino 'config.default.json') -Destination $ruta -ErrorAction Stop
        Set-AldiaPropietarioAdmin $ruta
    }
    Assert-AldiaPermisos $ruta
    foreach ($entrada in Get-ChildItem -LiteralPath $destino -Force -ErrorAction Stop) {
        Assert-AldiaPermisos $entrada.FullName
        if ($entrada.Name -ieq 'src') {
            foreach ($archivo in Get-ChildItem -LiteralPath $entrada.FullName -Filter '*.ps1' -Force -File) {
                Assert-AldiaPermisos $archivo.FullName
            }
        }
    }
    Assert-AldiaPermisos (Join-Path $destino 'gui\Principal.xaml')
    Assert-AldiaPermisos (Join-Path $destino 'datos\cpe.json')
    Assert-AldiaPermisos (Join-Path $destino 'datos\adopcion.json')
    Register-AldiaTarea $destino (Get-AldiaConfig $ruta $destino)
    Set-AldiaAccesosDirectos $destino
}

function Uninstall-Aldia {
    param([switch]$Todo)
    $servicio = Connect-AldiaTareas
    try { $carpeta = $servicio.GetFolder('\Aldia') }
    catch { if (($_.Exception.HResult -band 65535) -notin 2,3) { throw } }
    if ($carpeta) {
        try { $carpeta.DeleteTask('Al Día',0) }
        catch { if (($_.Exception.HResult -band 65535) -ne 2) { throw } }
        if (!$carpeta.GetTasks(1).Count -and !$carpeta.GetFolders(0).Count) { $servicio.GetFolder('\').DeleteFolder('Aldia',0) }
    }
    Set-AldiaAccesosDirectos (Get-AldiaProgramFiles) -Quitar
    $rutas = @(Get-AldiaProgramFiles)
    if ($Todo) { $rutas += Join-Path $env:ProgramData 'Aldia' }
    foreach ($ruta in $rutas) {
        Assert-AldiaRutaNormal $ruta
        if (Test-Path -LiteralPath $ruta) {
            $enlace = Get-ChildItem -LiteralPath $ruta -Recurse -Force -ErrorAction Stop |
                Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint } | Select-Object -First 1
            if ($enlace) { throw "Se rechazó un punto de reanálisis: $($enlace.FullName)" }
            Remove-Item -LiteralPath $ruta -Recurse -Force -ErrorAction Stop
        }
    }
}


function Set-AldiaAccesosDirectos {
    param([string]$Programa, [switch]$Quitar)
    $shell = New-Object -ComObject WScript.Shell
    $ps = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $argumentos = '-WindowStyle Hidden -NoProfile -STA -ExecutionPolicy Bypass -File "' + (Join-Path $Programa 'aldia.ps1') + '" gui'
    foreach ($especial in 'CommonPrograms','DesktopDirectory') {
        $carpeta = [Environment]::GetFolderPath([Environment+SpecialFolder]$especial)
        if (!$carpeta -or !(Test-Path -LiteralPath $carpeta -PathType Container)) { continue }
        $ruta = Join-Path $carpeta 'Al Día.lnk'
        Assert-AldiaRutaNormal $ruta
        $acceso = $shell.CreateShortcut($ruta)
        if (Test-Path -LiteralPath $ruta) {
            if ($acceso.TargetPath -ine $ps -or $acceso.Arguments -ine $argumentos) {
                if (!$Quitar) { Write-Warning "Ya hay un acceso distinto en $ruta." }
                continue
            }
            if ($Quitar) { Remove-Item -LiteralPath $ruta -ErrorAction Stop }
            continue
        }
        if ($Quitar) { continue }
        $acceso.TargetPath = $ps
        $acceso.Arguments = $argumentos
        $acceso.WorkingDirectory = $Programa
        $acceso.Description = 'Al Día'
        $acceso.IconLocation = (Join-Path $env:SystemRoot 'System32\shell32.dll') + ',46'
        $acceso.Save()
    }
}