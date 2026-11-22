function Get-AldiaEditores {
    $editor = @{}
    foreach ($ruta in 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*') {
        foreach ($p in Get-ItemProperty -Path $ruta -ErrorAction SilentlyContinue) {
            if ($p.DisplayName -and $p.Publisher) { $editor["$($p.DisplayName)|$($p.DisplayVersion)"] = $p.Publisher }
        }
    }
    $editor
}

function Get-AldiaInventarioSeguridad {
    param($Config)
    $editor = Get-AldiaEditores
    $inventario = @{ Apps=@(); Npm=@(); Avisos=@() }
    try {
        $inventario.Apps = @(foreach ($p in Get-AldiaApps $Config -ListaCompleta) {
            if ($p.Version -and !$p.VersionDesconocida -and $p.Id -notlike 'MSIX\Microsoft.*') {
                [pscustomobject]@{ Id=$p.Id; Nombre=$p.Nombre; Version=$p.Version; Fuente='apps'
                    Publisher=$editor["$($p.Nombre)|$($p.Version)"]; Origen=$p.Origen }
            }
        })
        $inventario.Apps = @($inventario.Apps | Group-Object {
            $nombre = $_.Nombre -replace '(?i)(?:\(\s*)?\bx(?:64|86)\b(?:\s*\))?', ' '
            "$(($nombre -replace '\s+',' ').Trim(' ','-','·'))|$($_.Version)"
        } | ForEach-Object {
            $primero = $_.Group | Sort-Object @{ Expression={ [bool]$_.Origen }; Descending=$true } | Select-Object -First 1
            if (!$primero.Publisher) {
                $primero.Publisher = $_.Group | Where-Object Publisher | Select-Object -First 1 -ExpandProperty Publisher
            }
            $primero | Add-Member -NotePropertyName Ids -NotePropertyValue @($_.Group.Id)
            $primero
        })
    } catch { $inventario.Avisos += 'No se pudo leer el inventario de winget.' }
    try {
        $exe = Get-AldiaNpmEjecutable
        if ($exe) {
            $r = Invoke-AldiaComando $exe @('ls','-g','--json','--depth','0')
            if ($r.Timeout -or $r.Codigo -notin 0,1) { throw 'No se pudo consultar npm.' }
            $lista = $r.Salida | ConvertFrom-Json -ErrorAction Stop
            $inventario.Npm = @(foreach ($p in $lista.dependencies.PSObject.Properties) {
                if ($p.Value.version -and $p.Name -cmatch '^(?:@[a-z0-9._-]+/)?[a-z0-9][a-z0-9._-]*$') {
                    [pscustomobject]@{ Id=$p.Name; Nombre=$p.Name; Version=$p.Value.version; Fuente='npm' }
                }
            })
        }
    } catch { $inventario.Avisos += 'No se pudo leer el inventario de npm.' }
    $inventario
}

function ConvertTo-AldiaTokensCpe {
    param([string]$Texto)
    $Texto.Normalize([Text.NormalizationForm]::FormKC).ToLowerInvariant() -split '[^\p{L}\p{Nd}]+' |
        Where-Object { $_ }
}

function Get-AldiaCpe {
    param($Programa, $Semillas, [hashtable]$Headers, [string]$Cache)
    foreach ($semilla in $Semillas) {
        if (($semilla.id -and $Programa.Id -like $semilla.id) -or
            ($semilla.nombre -and $Programa.Nombre -match $semilla.nombre)) {
            return @{ Datos=$semilla.cpe; Disponible=$true; Edad=0 }
        }
    }
    $limpio = ($Programa.Nombre -replace '(?i)\(\s*(?:[36][24][ -]?bit|x(?:64|86)|user|usuario)\s*\)|\b(?:x64|x86|amd64|arm64|[36][24][ -]?bit)\b|\bv?\d+(?:[._]\d+)+\b',' ' -replace '\s+',' ').Trim(' ','-','(',')')
    $tokens = @(ConvertTo-AldiaTokensCpe $limpio)
    $segmento = if ($Programa.Id -notmatch '\\') { ($Programa.Id -split '\.')[0] }
    $fabricantes = @(foreach ($nombre in $Programa.Publisher,$segmento) { @(ConvertTo-AldiaTokensCpe $nombre) -join '' })
    if (!$tokens.Count -or !($fabricantes -join '')) { return @{ Disponible=$true; Edad=0 } }
    Get-AldiaCacheSeguridad "cpe|$limpio|$($fabricantes -join '|')" 720 {
        $url = 'https://services.nvd.nist.gov/rest/json/cpes/2.0?keywordSearch=' + [uri]::EscapeDataString($limpio)
        $respuesta = Invoke-AldiaHttp $url -Headers $Headers
        if (!$respuesta.PSObject.Properties['totalResults']) { throw 'Respuesta CPE inválida.' }
        $candidatos = @(foreach ($entrada in $respuesta.products) {
            if ($entrada.cpe.deprecated -or $entrada.cpe.cpeName -notmatch '^cpe:2\.3:a:([\w.-]+):([\w.-]+):') { continue }
            $vendor = $Matches[1]
            $producto = $Matches[2]
            $marca = @(ConvertTo-AldiaTokensCpe $vendor) -join ''
            $partes = @(ConvertTo-AldiaTokensCpe $producto)
            if (!$marca -or !@($fabricantes | Where-Object { $_.Contains($marca) }).Count -or !$partes.Count) { continue }
            if (@($partes | Where-Object { $_ -notin $tokens }).Count) { continue }
            [pscustomobject]@{ Cpe="$($vendor):$producto"; Puntos=$partes.Count }
        })
        $orden = @($candidatos | Sort-Object Puntos -Descending)
        if ($orden.Count) {
            $mejores = @($orden | Where-Object Puntos -eq $orden[0].Puntos | Select-Object -ExpandProperty Cpe -Unique)
            if ($mejores.Count -eq 1) { $mejores[0] }
        }
    } -Directorio $Cache
}

function Compare-AldiaVersionNumerica {
    param([string]$A, [string]$B)
    if ($A -notmatch '^\d+(?:\.\d+)*$' -or $B -notmatch '^\d+(?:\.\d+)*$') { return }
    $izquierda = $A.Split('.')
    $derecha = $B.Split('.')
    for ($i=0; $i -lt [math]::Max($izquierda.Count,$derecha.Count); $i++) {
        $x = ([string]$izquierda[$i]).TrimStart('0')
        $y = ([string]$derecha[$i]).TrimStart('0')
        if ($x.Length -ne $y.Length) { return $x.Length.CompareTo($y.Length) }
        $orden = [string]::CompareOrdinal($x,$y)
        if ($orden) { return $orden }
    }
    0
}

function Get-AldiaCoincidenciasNvd {
    param($Nodo)
    $Nodo.cpeMatch
    foreach ($hijo in @($Nodo.nodes) + @($Nodo.children)) {
        if ($hijo) { Get-AldiaCoincidenciasNvd $hijo }
    }
}

function Test-AldiaVersionNvd {
    param($Coincidencia, [string]$Version, [string]$Exacta)
    if ($Exacta -ne '*' -and $Exacta -ne $Version) {
        $comparacion = Compare-AldiaVersionNumerica $Version $Exacta
        if ($null -ne $comparacion -and $comparacion -ne 0) { return $false }
    }
    foreach ($limite in 'versionStartIncluding','versionStartExcluding','versionEndIncluding','versionEndExcluding') {
        if (!$Coincidencia.$limite) { continue }
        $comparacion = Compare-AldiaVersionNumerica $Version $Coincidencia.$limite
        if ($null -eq $comparacion) { continue }
        if ($limite -like '*Excluding' -and $comparacion -eq 0) { return $false }
        if ($limite -like '*Start*' -and $comparacion -lt 0) { return $false }
        if ($limite -like '*End*' -and $comparacion -gt 0) { return $false }
    }
    $true
}

function ConvertFrom-AldiaNvd {
    param($Respuesta, [string]$Cpe, [string]$Version)
    foreach ($entrada in $Respuesta.vulnerabilities) {
        $cve = $entrada.cve
        if ($cve.vulnStatus -eq 'Rejected' -or $cve.id -notmatch '^CVE-\d{4}-\d{4,}$') { continue }
        $puntuacion = $null
        foreach ($tipo in 'cvssMetricV31','cvssMetricV30','cvssMetricV2') {
            $metricas = @($cve.metrics.$tipo | Where-Object { $null -ne $_.cvssData.baseScore })
            if ($metricas.Count) {
                $puntuacion = ($metricas | ForEach-Object { $_.cvssData.baseScore } | Measure-Object -Maximum).Maximum
                break
            }
        }
        $coincidencias = @(foreach ($nodo in $cve.configurations) {
            foreach ($m in Get-AldiaCoincidenciasNvd $nodo) {
                if ($m.vulnerable -ne $true -or $m.criteria -notmatch '^cpe:2\.3:a:([^:]+:[^:]+):((?:\\.|[^:\\])+):' -or $Matches[1] -ne $Cpe) { continue }
                if (!(Test-AldiaVersionNvd $m $Version $Matches[2])) { continue }
                [pscustomobject]@{
                    criteria=$m.criteria; vulnerable=$true
                    versionStartIncluding=$m.versionStartIncluding; versionStartExcluding=$m.versionStartExcluding
                    versionEndIncluding=$m.versionEndIncluding; versionEndExcluding=$m.versionEndExcluding
                }
            }
        })
        if ($Cpe -and !$coincidencias.Count) { continue }
        $fecha = [datetime]::MinValue
        $antiguo = [datetime]::TryParse([string]$cve.published,[ref]$fecha) -and $fecha -lt (Get-Date).AddYears(-10)
        $impreciso = $coincidencias.Count -gt 0 -and !@($coincidencias | Where-Object {
            $_.criteria -notmatch '^cpe:2\.3:a:[^:]+:[^:]+:\*:' -or
                $_.versionStartIncluding -or $_.versionStartExcluding -or $_.versionEndIncluding -or $_.versionEndExcluding
        }).Count
        [pscustomobject]@{ Published=$cve.published; CpeMatch=$coincidencias; Impreciso=($antiguo -or $impreciso); Id=$cve.id; Cvss=$puntuacion; Url="https://nvd.nist.gov/vuln/detail/$($cve.id)" }
    }
}

function Get-AldiaCvesNvd {
    param([string]$Cpe, [string]$Version, [hashtable]$Headers, [string]$Cache)
    Get-AldiaCacheSeguridad "nvd-v2|$Cpe|$Version" 24 {
        $versionCpe = $Version -replace '([^\w.-])','\$1'
        $cadena = [uri]::EscapeDataString("cpe:2.3:a:$($Cpe):$versionCpe")
        $inicio = 0
        do {
            $url = "https://services.nvd.nist.gov/rest/json/cves/2.0?virtualMatchString=$cadena&startIndex=$inicio"
            $respuesta = Invoke-AldiaHttp $url -Headers $Headers
            if (!$respuesta.PSObject.Properties['totalResults']) { throw 'Respuesta CVE inválida.' }
            ConvertFrom-AldiaNvd $respuesta $Cpe $Version
            $inicio += [int]$respuesta.resultsPerPage
            if ($respuesta.totalResults -gt $inicio -and !$respuesta.resultsPerPage) { throw 'Paginación CVE inválida.' }
        } while ($inicio -lt $respuesta.totalResults)
    } -Directorio $Cache
}

function ConvertFrom-AldiaOsv {
    param($Resultado, [string]$Cache, [switch]$SoloCache)
    foreach ($vuln in $Resultado.vulns) {
        $ids = @(@($vuln.id) + @($vuln.aliases) | Where-Object { $_ -match '^CVE-\d{4}-\d{4,}$' } | Select-Object -Unique)
        if (!$ids.Count -and $Cache -and $vuln.id -cmatch '^(?:GHSA-[a-z0-9-]+|OSV-\d+-\d+)$') {
            $detalle = Get-AldiaCacheSeguridad "osv-aviso|$($vuln.id)" 24 {
                Invoke-AldiaHttp "https://api.osv.dev/v1/vulns/$($vuln.id)"
            } -Directorio $Cache -SoloCache:$SoloCache
            $ids = @($detalle.Datos.aliases | Where-Object { $_ -match '^CVE-\d{4}-\d{4,}$' } | Select-Object -Unique)
        }
        if ($ids.Count) {
            foreach ($id in $ids) { [pscustomobject]@{ Id=$id; Cvss=$null; Url="https://nvd.nist.gov/vuln/detail/$id" } }
        } elseif ($vuln.id -match '^(?:GHSA-[a-z0-9-]+|OSV-\d+-\d+)$') {
            [pscustomobject]@{ Id=$vuln.id; Cvss=$null; Url="https://osv.dev/vulnerability/$($vuln.id)" }
        }
    }
}

function Get-AldiaOsv {
    param($Paquetes, [string]$Cache)
    $resultados = @{}
    for ($i=0; $i -lt $Paquetes.Count; $i+=100) {
        $lote = @($Paquetes[$i..([math]::Min($i+99,$Paquetes.Count-1))])
        $consultas = @(foreach ($p in $lote) { [ordered]@{ package=[ordered]@{ name=$p.Id; ecosystem='npm' }; version=$p.Version } })
        $body = @{ queries=$consultas } | ConvertTo-Json -Depth 5 -Compress
        $resp = Get-AldiaCacheSeguridad "osv|$body" 24 {
            $respuesta = Invoke-AldiaHttp 'https://api.osv.dev/v1/querybatch' -Body $body
            if ($respuesta.results.Count -ne $lote.Count) { throw 'Respuesta OSV incompleta.' }
            $respuesta
        } -Directorio $Cache
        for ($j=0; $j -lt $lote.Count; $j++) {
            $resultados[$lote[$j].Id] = @{
                Disponible=$resp.Disponible; Edad=$resp.Edad
                Datos=if ($resp.Disponible) { @(ConvertFrom-AldiaOsv $resp.Datos.results[$j] $Cache -SoloCache:([bool]$resp.Edad)) }
            }
        }
    }
    $resultados
}

function Get-AldiaContextoCves {
    param([string[]]$Ids, [string]$Cache)
    $contexto = @{ Kev=@{}; Epss=@{}; Edad=0; Incompleto=$false }
    if (!$Ids.Count) { return $contexto }
    $kev = Get-AldiaCacheSeguridad 'kev' 24 {
        $respuesta = Invoke-AldiaHttp 'https://www.cisa.gov/sites/default/files/feeds/known_exploited_vulnerabilities.json'
        if (!$respuesta.PSObject.Properties['vulnerabilities']) { throw 'Respuesta KEV inválida.' }
        $respuesta.vulnerabilities | Select-Object cveID,knownRansomwareCampaignUse,dueDate
    } -Directorio $Cache
    $contexto.Edad = $kev.Edad
    $contexto.Incompleto = !$kev.Disponible
    foreach ($c in $kev.Datos) { if ($c.cveID) { $contexto.Kev[$c.cveID] = $c } }
    for ($i=0; $i -lt $Ids.Count; $i+=100) {
        $lista = $Ids[$i..([math]::Min($i+99,$Ids.Count-1))] -join ','
        $epss = Get-AldiaCacheSeguridad "epss|$lista" 24 {
            $respuesta = Invoke-AldiaHttp "https://api.first.org/data/v1/epss?cve=$lista"
            if ($respuesta.status -ne 'OK') { throw 'Respuesta EPSS inválida.' }
            $respuesta.data
        } -Directorio $Cache
        foreach ($c in $epss.Datos) {
            $valor = 0.0
            if ($c.cve -and [double]::TryParse([string]$c.epss,[Globalization.NumberStyles]::Float,[cultureinfo]::InvariantCulture,[ref]$valor)) {
                $contexto.Epss[$c.cve] = $valor
            }
        }
        $contexto.Edad = [math]::Max($contexto.Edad,$epss.Edad)
        if (!$epss.Disponible) { $contexto.Incompleto = $true }
    }
    $contexto
}
