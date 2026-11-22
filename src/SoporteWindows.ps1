function Get-AldiaVersionWindows {
    Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction Stop
}

function Get-AldiaSoporteWindows {
    param([datetime]$Ahora = (Get-Date))
    $r = Get-AldiaVersionWindows
    $insider = Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\WindowsSelfHost\Applicability' -ErrorAction SilentlyContinue
    $tabla = Get-Content -LiteralPath (Join-Path (Split-Path $PSScriptRoot) 'datos\windows.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $build = [int]$r.CurrentBuildNumber
    $fila = $tabla | Where-Object build -eq $build | Select-Object -First 1
    $estado = 'desconocido'; $detalle = 'No se pudo comprobar la versión de Windows.'; $accion = $null; $url = $null
    if ($insider.BranchName) { $estado='aviso'; $detalle='Versión de prueba (Insider)' }
    elseif ($build -gt ($tabla.build | Measure-Object -Maximum).Maximum) {
        $estado='bien'; $detalle='Versión reciente'
    } elseif ($fila) {
        $fin = if ($r.EditionID -match '^(Enterprise|Education|IoTEnterprise)') { $fila.finEmpresa } else { $fila.finHomePro }
        $fecha = [datetime]::ParseExact($fin,'yyyy-MM-dd',[cultureinfo]::InvariantCulture)
        if ($Ahora.Date -gt $fecha) { $estado='mal'; $detalle='Esta versión de Windows ya no recibe parches de seguridad' }
        elseif (($fecha - $Ahora.Date).Days -lt 90) { $estado='aviso'; $detalle="Recibe parches hasta el $($fecha.ToString('dd/MM/yyyy'))." }
        else { $estado='bien'; $detalle="$($fila.producto) $($fila.version) recibe parches de seguridad." }
    } elseif ($build -gt 0) {
        $estado='mal'; $detalle='Windows sin soporte'
    }
    if ($estado -eq 'mal') {
        $accion='Cómo actualizar'; $url='ms-settings:windowsupdate'
        if ($build -ge 10240 -and $build -lt 22000) {
            $detalle='Windows 10 ya no tiene soporte. Si el PC es compatible, pasa a Windows 11. Si no, consulta las actualizaciones de seguridad extendidas (ESU) de Microsoft.'
            $url='https://www.microsoft.com/windows/extended-security-updates'
        }
    }
    [pscustomobject]@{ Id='versionWindows'; Nombre='Versión de Windows'; Estado=$estado; Detalle=$detalle
        Explicacion='Una versión con soporte sigue recibiendo correcciones de seguridad.'; Accion=$accion; Datos=$url }
}