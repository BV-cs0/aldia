$script:AldiaSalud = [ordered]@{
    antivirus=@('Antivirus','Protege el equipo de archivos y programas dañinos.')
    firewall=@('Firewall','Controla las conexiones que pueden entrar en el equipo.')
    restauracion=@('Puntos de restauración','Permiten recuperar ajustes del sistema si una actualización da problemas.')
    cifrado=@('Cifrado del disco','Protege tus archivos si pierdes el equipo.')
    uac=@('Control de cuentas (UAC)','Pide permiso antes de hacer cambios importantes.')
    smb1=@('SMBv1','Es una versión antigua e insegura del uso compartido de archivos.')
    arranque=@('Arranque seguro','Comprueba que el software de arranque sea de confianza.')
    tpm=@('TPM','Ayuda a proteger las claves y el inicio de sesión.')
    reinicio=@('Reinicio pendiente','Algunos cambios se completan al reiniciar el PC.')
    espacio=@('Espacio libre','Windows necesita espacio libre para instalar actualizaciones.')
    actualizacion=@('Última actualización de Windows','Las actualizaciones corrigen fallos y mejoran la seguridad.')
    red=@('Servicios abiertos a la red','Si no usas este servicio, desactívalo o bloquéalo en el firewall.')
}

function Get-AldiaAntivirusSalud {
    try { $mp = Get-MpComputerStatus -ErrorAction Stop } catch { $mp = $null }
    if ($mp.AntivirusEnabled -and $mp.AMRunningMode -notmatch 'Passive|EDR Block') {
        if ($null -eq $mp.RealTimeProtectionEnabled) { throw 'Estado de protección no disponible.' }
        if (!$mp.RealTimeProtectionEnabled) { return 'mal','La protección en tiempo real está desactivada.' }
        if ($null -eq $mp.AntivirusSignatureAge) { throw 'Antigüedad de firmas no disponible.' }
        if ($mp.AntivirusSignatureAge -gt 3) { return 'aviso',"Las firmas tienen $($mp.AntivirusSignatureAge) días." }
        return 'bien','Microsoft Defender está activo y al día.'
    }
    $productos = @(Get-CimInstance -Namespace 'root\SecurityCenter2' -ClassName AntiVirusProduct -ErrorAction Stop)
    $activos = @($productos | Where-Object { (([int]$_.productState -shr 12) -band 1) -eq 1 })
    if (!$activos.Count) { return 'mal','Windows no informa de un antivirus activo.' }
    $alDia = @($activos | Where-Object { ([int]$_.productState -band 16) -eq 0 })
    if ($alDia.Count) { return 'bien',($alDia.displayName -join ', ') }
    'aviso',("Firmas desactualizadas: " + ($activos.displayName -join ', '))
}

function Get-AldiaReinicioSalud {
    $base = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion'
    $sesion = Get-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -ErrorAction Stop
    if ($sesion.PendingFileRenameOperations -or
        (Test-Path -LiteralPath "$base\Component Based Servicing\RebootPending" -ErrorAction Stop) -or
        (Test-Path -LiteralPath "$base\WindowsUpdate\Auto Update\RebootRequired" -ErrorAction Stop)) {
        return 'aviso','Windows tiene cambios pendientes de aplicar.'
    }
    'bien','No hay cambios pendientes de reinicio.'
}

function Get-AldiaFechaActualizacionSalud {
    $buscador = (New-AldiaSesionWU).CreateUpdateSearcher()
    $total = $buscador.GetTotalHistoryCount()
    for ($inicio=0; $inicio -lt $total; $inicio+=100) {
        foreach ($entrada in $buscador.QueryHistory($inicio,[math]::Min($total-$inicio,100))) {
            if ($entrada.Operation -eq 1 -and $entrada.ResultCode -eq 2) { return [datetime]$entrada.Date }
        }
    }
}

function Get-AldiaEscuchasSalud {
    $errores = @()
    $conexiones = @(Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue -ErrorVariable +errores)
    if (@($errores | Where-Object FullyQualifiedErrorId -notlike 'CmdletizationQuery_NotFound*').Count) {
        throw 'No se pudo consultar la lista de conexiones.'
    }
    $procesos = @{}
    $servicios = foreach ($c in $conexiones | Where-Object LocalAddress -notin '127.0.0.1','::1' |
        Sort-Object { $_.LocalPort },{ $_.LocalAddress },{ $_.OwningProcess } -Unique) {
        $pidConexion = [int]$c.OwningProcess
        if (!$procesos.ContainsKey($pidConexion)) {
            $procesos[$pidConexion] = Get-Process -Id $pidConexion -ErrorAction SilentlyContinue
        }
        $proceso = $procesos[$pidConexion]
        [pscustomobject]@{ Puerto=$c.LocalPort; Direccion=$c.LocalAddress
            Programa=if ($proceso) { $proceso.ProcessName } else { "PID $pidConexion" }
            Ruta=$proceso.Path
            Riesgo=($c.LocalAddress -in '0.0.0.0','::' -and $c.LocalPort -in 21,23,445,3389,5900,22350,22351,22352) }
    }
    foreach ($grupo in $servicios | Group-Object Puerto,Programa) {
        $item = $grupo.Group | Sort-Object Riesgo -Descending | Select-Object -First 1
        $item.Direccion = if (@($grupo.Group | Where-Object Direccion -in '0.0.0.0','::').Count) { 'Todas las interfaces' }
            else { ($grupo.Group.Direccion | Sort-Object -Unique) -join ', ' }
        $explicacion = if ($item.Riesgo) {
            switch ($item.Puerto) {
                445 { 'Compartir archivos de Windows: normal en casa; el firewall lo bloquea en redes públicas.' }
                3389 { 'Escritorio remoto: desactívalo si no lo usas.' }
                { $_ -in 21,23 } { 'Servicio antiguo sin cifrar.' }
                5900 { 'Control remoto VNC.' }
                { $_ -in 22350,22351,22352 } { 'CodeMeter: su panel web no debería estar abierto a la red.' }
            }
        }
        $item | Add-Member -NotePropertyName Explicacion -NotePropertyValue $explicacion -PassThru
    }
}

function Get-AldiaDiscoSalud {
    $disco = [IO.DriveInfo]::new($env:SystemDrive)
    @{ FreeSpace=$disco.AvailableFreeSpace; Size=$disco.TotalSize }
}

function Get-AldiaComprobacionSalud {
    param([string]$Id)
    $meta = $script:AldiaSalud[$Id]
    $accion = $null
    $datos = $null
    try {
        $estado,$detalle = switch ($Id) {
            antivirus {
                $accion = 'Abrir Seguridad de Windows'
                Get-AldiaAntivirusSalud
            }
            firewall {
                $perfiles = @(Get-NetFirewallProfile -ErrorAction Stop)
                if (!$perfiles.Count -or @($perfiles | Where-Object { "$($_.Enabled)" -notin 'True','False' }).Count) {
                    throw 'Perfiles no disponibles.'
                }
                $datos = @($perfiles | Where-Object { "$($_.Enabled)" -eq 'False' } | ForEach-Object { $_.Name })
                if ($datos.Count) {
                    $accion = 'Activar'
                    'mal',('Perfiles desactivados: ' + ($datos -join ', '))
                } else { 'bien','Todos los perfiles están activados.' }
            }
            restauracion {
                switch (Get-AldiaProteccionGui) {
                    activada { 'bien','Activados en la unidad del sistema.' }
                    desactivada { $accion = 'Activar'; 'aviso','Desactivados en la unidad del sistema.' }
                    bloqueada { 'aviso','Desactivados por la organización.' }
                    default { throw 'Estado de protección no disponible.' }
                }
            }
            cifrado {
                $accion = 'Abrir configuración de cifrado'
                $v = Get-BitLockerVolume -MountPoint $env:SystemDrive -ErrorAction Stop
                switch ([string]$v.ProtectionStatus) {
                    { $_ -in '1','On' } { 'bien','La protección está activada.' }
                    { $_ -in '0','Off' } { 'aviso','La protección está desactivada.' }
                    default { throw 'Estado de cifrado no disponible.' }
                }
            }
            uac {
                $accion = 'Abrir configuración de UAC'
                $v = Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' -ErrorAction Stop
                if ($null -eq $v.EnableLUA -or $null -eq $v.ConsentPromptBehaviorAdmin) { throw 'Configuración UAC incompleta.' }
                if ($v.EnableLUA -ne 1 -or $v.ConsentPromptBehaviorAdmin -eq 0) { 'mal','Los cambios de administrador no piden confirmación.' }
                else { 'bien','Los cambios de administrador requieren confirmación.' }
            }
            smb1 {
                $v = Get-WindowsOptionalFeature -Online -FeatureName SMB1Protocol -ErrorAction Stop
                switch ([string]$v.State) {
                    Enabled { $accion = 'Desactivar'; 'mal','SMBv1 está habilitado. Desactivarlo puede requerir reiniciar.' }
                    { $_ -in 'Disabled','DisabledWithPayloadRemoved','Removed' } { 'bien','SMBv1 está desactivado.' }
                    { $_ -in 'EnablePending','DisablePending' } { 'aviso','Hay un cambio de SMBv1 pendiente de reinicio.' }
                    default { throw 'Estado de SMBv1 no disponible.' }
                }
            }
            arranque {
                $v = Confirm-SecureBootUEFI -ErrorAction Stop
                if ($v -eq $true) { 'bien','Arranque seguro activado.' }
                elseif ($v -eq $false) { 'aviso','Arranque seguro desactivado.' }
                else { throw 'Estado de arranque no disponible.' }
            }
            tpm {
                $v = Get-Tpm -ErrorAction Stop
                if ($null -eq $v.TpmPresent -or ($v.TpmPresent -and $null -eq $v.TpmReady)) { throw 'Estado del TPM no disponible.' }
                if (!$v.TpmPresent) { 'aviso','No se detectó un TPM.' }
                elseif (!$v.TpmReady) { 'aviso','El TPM está presente y requiere configuración.' }
                else { 'bien','El TPM está listo para usarse.' }
            }
            reinicio {
                $e,$d = Get-AldiaReinicioSalud
                if ($e -eq 'aviso') { $accion = 'Reiniciar' }
                $e,$d
            }
            espacio {
                $accion = 'Abrir configuración de almacenamiento'
                $v = Get-AldiaDiscoSalud
                if (!$v.Size -or $null -eq $v.FreeSpace) { throw 'Espacio libre no disponible.' }
                $gb = $v.FreeSpace / 1GB
                $porcentaje = 100 * ($v.FreeSpace / $v.Size)
                $e = if ($gb -lt 5 -or $porcentaje -lt 5) { 'mal' }
                    elseif ($gb -lt 20 -or $porcentaje -lt 15) { 'aviso' } else { 'bien' }
                $e, ('{0:N1} GB libres ({1:N1} %).' -f $gb,$porcentaje)
            }
            actualizacion {
                $fecha = Get-AldiaFechaActualizacionSalud
                if (!$fecha) { throw 'El historial no contiene instalaciones correctas.' }
                $dias = ([datetime]::UtcNow - $fecha.ToUniversalTime()).TotalDays
                $e = if ($dias -gt 30) { 'mal' } elseif ($dias -gt 14) { 'aviso' } else { 'bien' }
                $e, ('Última instalación correcta: {0:dd/MM/yyyy}.' -f $fecha)
            }
            red {
                $todos = @(Get-AldiaEscuchasSalud)
                $datos = @($todos | Where-Object {
                    $_.Puerto -lt 49152 -or $_.Programa -notin 'lsass','wininit','services','svchost','spoolsv','System'
                })
                $riesgo = @($datos | Where-Object Riesgo).Count
                $estadoRed = if ($riesgo) { 'aviso' } else { 'bien' }
                $detalleRed = if ($riesgo) {
                    Format-AldiaCantidadGui $riesgo 'servicio sensible abierto a la red' 'servicios sensibles abiertos a la red'
                } else {
                    Format-AldiaCantidadGui $datos.Count 'servicio abierto a la red' 'servicios abiertos a la red'
                }
                $internos = $todos.Count - $datos.Count
                if ($internos) {
                    $resumenInternos = Format-AldiaCantidadGui $internos 'servicio interno de Windows' 'servicios internos de Windows'
                    $detalleRed += " y $resumenInternos"
                }
                $estadoRed, "$detalleRed."
            }
        }
    } catch {
        $estado = 'desconocido'
        $detalle = 'No se pudo comprobar en este equipo.'
    }
    [pscustomobject]@{ Id=$Id; Nombre=$meta[0]; Estado=$estado; Detalle=$detalle; Explicacion=$meta[1]
        Accion=$accion; Datos=$datos }
}

function Get-AldiaSalud {
    foreach ($id in $script:AldiaSalud.Keys) { Get-AldiaComprobacionSalud $id }
}

function Invoke-AldiaAccionSalud {
    param([string]$Id)
    $actual = Get-AldiaComprobacionSalud $Id
    if (!$actual.Accion) { return $actual }
    switch ($Id) {
        antivirus { $null = Invoke-AldiaComando 'windowsdefender:' -Visible }
        cifrado { $null = Invoke-AldiaComando 'ms-settings:deviceencryption' -Visible }
        uac { $null = Invoke-AldiaComando (Join-Path $env:SystemRoot 'System32\UserAccountControlSettings.exe') -Visible }
        espacio { $null = Invoke-AldiaComando 'ms-settings:storagesense' -Visible }
        firewall {
            $perfiles = @($actual.Datos | Where-Object { $_ -in 'Domain','Private','Public' })
            if ($perfiles.Count) { Set-NetFirewallProfile -Name $perfiles -Enabled True -ErrorAction Stop }
        }
        restauracion { Enable-ComputerRestore -Drive "$env:SystemDrive\" -ErrorAction Stop }
        smb1 { $null = Disable-WindowsOptionalFeature -Online -FeatureName SMB1Protocol -NoRestart -ErrorAction Stop }
        reinicio {
            $r = Invoke-AldiaComando (Join-Path $env:SystemRoot 'System32\shutdown.exe') @('/r','/t','0')
            if ($r.Timeout -or $r.Codigo -ne 0) { throw 'No se pudo solicitar el reinicio.' }
        }
    }
    Get-AldiaComprobacionSalud $Id
}

function Get-AldiaSaludDemo {
    param($Cambios)
    foreach ($id in $script:AldiaSalud.Keys) {
        $meta = $script:AldiaSalud[$id]
        $accion = @{ firewall='Activar'; restauracion='Activar'; smb1='Desactivar'; reinicio='Reiniciar'
            antivirus='Abrir Seguridad de Windows'; cifrado='Abrir configuración de cifrado'
            uac='Abrir configuración de UAC'; espacio='Abrir configuración de almacenamiento' }[$id]
        $estado = if ($Cambios[$id]) { 'bien' } elseif ($id -in 'firewall','smb1') { 'mal' }
            elseif ($id -in 'restauracion','reinicio','red') { 'aviso' }
            elseif ($id -eq 'arranque') { 'desconocido' } else { 'bien' }
        if ($Cambios[$id]) { $accion = $null }
        [pscustomobject]@{ Id=$id; Nombre=$meta[0]; Estado=$estado; Detalle="Ejemplo · $estado"
            Explicacion=$meta[1]; Accion=$accion
            Datos=if ($id -eq 'red') { @([pscustomobject]@{ Puerto=445; Direccion='0.0.0.0'; Programa='System'; Ruta='' }) } }
    }
}
