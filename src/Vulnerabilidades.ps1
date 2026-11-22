function New-AldiaInformePrograma {
    param($Programa, $Consulta, $Contexto, $Actualizacion, [switch]$SinCpe, [int]$EdadCpe, [bool]$AlDia = $false, [bool]$Adoptable = $false, [datetime]$Ahora = (Get-Date))
    $cves = @(foreach ($grupo in $Consulta.Datos | Group-Object Id) {
        $c = $grupo.Group[0]
        if (!$c.Id) { continue }
        $kev = $Contexto.Kev[$c.Id]
        $epss = $Contexto.Epss[$c.Id]
        $nivel = if ($kev -or $c.Cvss -ge 9) { 4 } elseif ($c.Cvss -ge 7 -or $epss -ge 0.1) { 3 }
            elseif ($c.Cvss -ge 4) { 2 } else { 1 }
        $anio = if ($c.Id -match '^CVE-(\d{4})-') { [int]$Matches[1] }
        $motivoDudoso = if ($anio -and ($Ahora.Year - $anio) -gt 10) { 'dato antiguo' }
            elseif ($AlDia -and $anio -and ($Ahora.Year - $anio) -gt 3) { 'probablemente no afecta a tu versión' }
            elseif ($c.Impreciso) { 'dato antiguo o impreciso' }
        $dudosoHallazgo = $motivoDudoso -in 'dato antiguo','probablemente no afecta a tu versión'
        if ($motivoDudoso) { $nivel = 1 }
        [pscustomobject]@{ Anio=$anio; Impreciso=[bool]$motivoDudoso; Dudoso=$dudosoHallazgo; MotivoDudoso=$motivoDudoso; Id=$c.Id; Cvss=$c.Cvss; Url=$c.Url; Epss=$epss; Nivel=$nivel; Explotado=[bool]$kev
            Ransomware=$kev.knownRansomwareCampaignUse; FechaLimite=$kev.dueDate }
    })
    $cves = @($cves | Sort-Object @{Expression='Nivel';Descending=$true},@{Expression='Explotado';Descending=$true},
        @{Expression='Cvss';Descending=$true},@{Expression='Epss';Descending=$true},Id)
    $claros = @($cves | Where-Object { !$_.Dudoso })
    $dudoso = $cves.Count -gt 0 -and !$claros.Count
    $peor = if ($dudoso) { $cves | Select-Object -First 1 } else { $claros | Select-Object -First 1 }
    $cantidadCve = @($cves | Where-Object Id -like 'CVE-*').Count
    $edad = [math]::Max($EdadCpe,$Consulta.Edad)
    if ($cantidadCve) { $edad = [math]::Max($edad,$Contexto.Edad) }
    $detalle = if (!$Consulta.Disponible) { 'No se pudo comprobar (sin conexión)' }
        elseif ($SinCpe) { 'Sin datos' }
        elseif (!$peor) { 'Sin fallos conocidos en la fuente consultada' }
        else {
            $cantidad = Format-AldiaCantidadGui $cves.Count 'fallo conocido' 'fallos conocidos'
            $cvss = if ($null -ne $peor.Cvss) { ' ({0})' -f $peor.Cvss }
            $anio = if ($peor.Anio) { " · $($peor.Anio)" }
            "$cantidad · el peor: $($peor.Id)$cvss$anio"
        }
    $explotado = @($cves | Where-Object Explotado).Count -gt 0
    $ransomware = @($cves | Where-Object Ransomware -eq 'Known').Count -gt 0
    if ($explotado) { $detalle += ' · explotado activamente' }
    if ($ransomware) { $detalle += ' · usado en ransomware' }
    foreach ($motivo in @($cves | Where-Object Impreciso | Select-Object -ExpandProperty MotivoDudoso -Unique)) {
        $detalle += " · $motivo"
    }
    if ($edad) { $detalle += " · resultados de hace $edad h" }
    if ($cantidadCve -and $Contexto.Incompleto) { $detalle += ' · datos de explotación incompletos' }
    $accion = if ($peor -and $Actualizacion) { 'Se actualiza con Al Día.' }
        elseif ($peor -and $Adoptable) { 'Adóptalo en Herramientas para que se actualice solo.' }
        elseif ($peor -and $AlDia) { 'No hay versión más nueva. Si ya no lo usas, desinstálalo.' }
        elseif ($peor -and $Programa.Fuente -eq 'apps') { 'Actualízalo desde la web del fabricante.' }
        elseif ($peor) { 'Consulta el aviso y actualiza el paquete npm.' }
    [pscustomobject]@{
        Nombre=$Programa.Nombre; Id=$Programa.Id; Version=$Programa.Version; Fuente=$Programa.Fuente
        Nivel=[int]$peor.Nivel; Riesgo=@('—','Bajo','Medio','Alto','Crítico')[[int]$peor.Nivel]
        Ids=$Programa.Ids; Anio=$peor.Anio; Comprobado=($Consulta.Disponible -and !$SinCpe); CVE=$cantidadCve; Fallos=$cves; Peor=$peor.Id; Detalle=$detalle; Accion=$accion
        Dudoso=$dudoso; Explotado=$explotado; Ransomware=$ransomware; Actualizacion=$Actualizacion; Edad=$edad
    }
}

function Get-AldiaVulnerabilidades {
    param($Config, [scriptblock]$Progreso, $Pendientes,
        [string]$Cache = (Join-Path $env:ProgramData 'Aldia\cache'))
    $inventario = Get-AldiaInventarioSeguridad $Config
    if (!$PSBoundParameters.ContainsKey('Pendientes')) {
        try { $Pendientes = @(Get-AldiaApps $Config) }
        catch { $inventario.Avisos += 'No se pudo comprobar si winget ofrece actualizaciones.' }
    }
    $consultaWinget = $true
    if ($inventario.Avisos -contains 'No se pudo comprobar si winget ofrece actualizaciones.') { $consultaWinget = $false }
    $adoptables = @{}
    if ($inventario.Apps) {
        try {
            $inventarioAdopcion = @($inventario.Apps | Where-Object { $_.Id -like 'ARP\*' })
            foreach ($adopcion in Get-AldiaAdopciones $Config -Inventario $inventarioAdopcion -Cache $Cache) {
                $adoptables[$adopcion.ArpId] = $true
            }
        } catch {}
    }
    $versiones = @{}
    foreach ($p in $Pendientes) { if ($p.Id) { $versiones[$p.Id] = $p.Disponible } }
    $semillas = Get-Content -LiteralPath (Join-Path (Split-Path $PSScriptRoot) 'datos\cpe.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $headers = @{}
    if ($Config.vulnerabilidades.nvdApiKey) { $headers.apiKey = $Config.vulnerabilidades.nvdApiKey }
    $total = $inventario.Apps.Count + $inventario.Npm.Count
    $actual = 0
    $consultas = @(foreach ($p in $inventario.Apps) {
        $actual++
        if ($Progreso) { $null = & $Progreso $actual $total }
        $cpe = Get-AldiaCpe $p $semillas $headers $Cache
        $consulta = if ($cpe.Datos) { Get-AldiaCvesNvd $cpe.Datos $p.Version $headers $Cache } else { $cpe }
        @{ Programa=$p; Consulta=$consulta; SinCpe=(!$cpe.Datos); EdadCpe=$cpe.Edad }
    })
    if ($inventario.Npm.Count) {
        $osv = Get-AldiaOsv @($inventario.Npm | Sort-Object { $_.Id }) $Cache
        $consultas += @(foreach ($p in $inventario.Npm) {
            $actual++
            if ($Progreso) { $null = & $Progreso $actual $total }
            @{ Programa=$p; Consulta=$osv[$p.Id]; SinCpe=$false; EdadCpe=0 }
        })
    }
    $ids = @($consultas | ForEach-Object { $_.Consulta.Datos } | Where-Object { $_.Id -like 'CVE-*' } |
        Select-Object -ExpandProperty Id | Sort-Object -Unique)
    $contexto = Get-AldiaContextoCves $ids $Cache
    $programas = @(foreach ($item in $consultas) {
        $version = if ($item.Programa.Fuente -eq 'apps') {
            foreach ($id in @($item.Programa.Id) + @($item.Programa.Ids)) {
                if ($versiones[$id]) { $versiones[$id]; break }
            }
        }
        $alDia = $consultaWinget -and !$version -and $item.Programa.Origen -eq 'winget'
        $adoptable = $item.Programa.Id -and $adoptables.ContainsKey($item.Programa.Id)
        New-AldiaInformePrograma $item.Programa $item.Consulta $contexto $version -SinCpe:$item.SinCpe -EdadCpe $item.EdadCpe -AlDia:$alDia -Adoptable:$adoptable
    })
    @{ Programas=@($programas | Sort-Object @{Expression='Nivel';Descending=$true},Nombre)
        Avisos=$inventario.Avisos }
}

function Get-AldiaResumenSeguridad {
    param($Informe)
    $graves = @($Informe.Programas | Where-Object { $_.Nivel -ge 3 -and !$_.Dudoso })
    if (!$graves.Count) { return }
    $nombres = @($graves | Select-Object -First 3 | ForEach-Object {
        if ($_.Explotado) { "$($_.Nombre) (explotado activamente)" } else { $_.Nombre }
    })
    $lista = $nombres -join ', '
    if ($graves.Count -gt 3) { $lista += '…' }
    if ($graves.Count -eq 1) { "Queda 1 programa con fallos graves: $lista." }
    else { "Quedan $($graves.Count) programas con fallos graves: $lista." }
}

function Format-AldiaRevisionSeguridad {
    param($Informe)
    $hallazgos = @($Informe.Programas | Where-Object { $_.Nivel -gt 0 -and !$_.Dudoso }).Count
    $limpios = @($Informe.Programas | Where-Object { $_.Comprobado -and !$_.Nivel }).Count
    $dudosos = @($Informe.Programas | Where-Object Dudoso).Count
    $sinDatos = $Informe.Programas.Count - $hallazgos - $limpios - $dudosos
    $total = Format-AldiaCantidadGui $Informe.Programas.Count 'programa revisado' 'programas revisados'
    $texto = "$($total): $hallazgos con fallos, $limpios sin fallos conocidos, $sinDatos sin datos"
    if ($dudosos) { $texto += ", $dudosos con datos dudosos" }
    "$texto."
}