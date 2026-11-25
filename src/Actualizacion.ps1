$script:AldiaUrlRelease = 'https://api.github.com/repos/BV-cs0/aldia/releases/latest'
$script:AldiaUrlDescargas = 'https://github.com/BV-cs0/aldia/releases/download/'
$script:AldiaUrlGaleria = "https://www.powershellgallery.com/api/v2/FindPackagesById()?id='Aldia'"
$script:AldiaTamanoMaximo = 20MB

function ConvertTo-AldiaVersion {
    param($Texto)
    $t = "$Texto".Trim() -replace '^[vV]', ''
    if ($t -notmatch '^\d+(\.\d+){1,3}$') { return $null }
    $v = [version]$t
    [version]::new($v.Major, $v.Minor, [math]::Max($v.Build, 0), [math]::Max($v.Revision, 0))
}

function Test-AldiaVersionNueva {
    param($Actual, $Ultima)
    $a = ConvertTo-AldiaVersion $Actual
    $u = ConvertTo-AldiaVersion $Ultima
    [bool]($a -and $u -and $u -gt $a)
}

function Get-AldiaVersionLocal {
    param([string]$Carpeta = (Split-Path $PSScriptRoot))
    try { [string](Import-PowerShellDataFile (Join-Path $Carpeta 'Aldia.psd1') -ErrorAction Stop).ModuleVersion }
    catch { $null }
}

function Get-AldiaCanal {
    # instalado: Program Files (tarea elevada) · galeria: Install-Module · desarrollo: git clone · portatil: carpeta suelta o USB
    param([string]$Carpeta)
    $c = $Carpeta.TrimEnd('\')
    if ($c -ieq (Get-AldiaProgramFiles).TrimEnd('\')) { return 'instalado' }
    if (Test-Path -LiteralPath ([IO.Path]::Combine($c, '.git'))) { return 'desarrollo' }   # Join-Path falla si la unidad (USB) no existe
    foreach ($m in @("$env:PSModulePath" -split ';' | Where-Object { $_ })) {
        if ($c.StartsWith($m.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) { return 'galeria' }
    }
    'portatil'
}

function Get-AldiaUltimaRelease {
    param([int]$Timeout = 8)
    try { $r = Invoke-AldiaHttp $script:AldiaUrlRelease -Headers @{ Accept = 'application/vnd.github+json' } -Timeout $Timeout }
    catch {
        if ([int]$_.Exception.Response.StatusCode -eq 404) { return $null }   # aún no hay ninguna release publicada
        throw
    }
    $version = ConvertTo-AldiaVersion $r.tag_name
    if (!$version -or $r.draft -or $r.prerelease) { return $null }
    $texto = "$($r.tag_name)" -replace '^[vV]', ''
    $nombre = "Aldia-$texto.zip"
    $urls = @{}
    foreach ($archivo in $nombre, "$nombre.sha256") {
        $activo = @($r.assets | Where-Object { $_.name -ceq $archivo })[0]
        # Solo el canal oficial: la URL tiene que ser exactamente la de esa release en BV-cs0/aldia.
        if (!$activo -or "$($activo.browser_download_url)" -cne "$script:AldiaUrlDescargas$($r.tag_name)/$archivo") { return $null }
        $urls[$archivo] = $activo.browser_download_url
    }
    [pscustomobject]@{ Version = $texto; Zip = $urls[$nombre]; Sha = $urls["$nombre.sha256"]; Nombre = $nombre }
}

function Get-AldiaHashSha256 {
    param([string]$Ruta)
    (Get-FileHash -LiteralPath $Ruta -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
}

function Save-AldiaDescarga {
    param([string]$Uri, [string]$Destino, [int]$Timeout)
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    if (!$Uri.StartsWith($script:AldiaUrlDescargas, [StringComparison]::Ordinal)) { throw 'Origen de descarga no permitido.' }
    Invoke-WebRequest -Uri $Uri -OutFile $Destino -TimeoutSec $Timeout -MaximumRedirection 5 -UseBasicParsing -ErrorAction Stop
    if ((Get-Item -LiteralPath $Destino).Length -gt $script:AldiaTamanoMaximo) { throw 'La descarga es demasiado grande.' }
}

function Save-AldiaActualizacion {
    # Descarga la última release si es más nueva, comprueba su SHA-256 y la deja preparada en $Pendientes.
    param([string]$Carpeta, [string]$Pendientes, [switch]$Protegida, [int]$Timeout = 60)
    $release = Get-AldiaUltimaRelease
    if (!$release -or !(Test-AldiaVersionNueva (Get-AldiaVersionLocal $Carpeta) $release.Version)) { return $null }
    if ($Protegida) { New-AldiaDirectorioProtegido $Pendientes } else { $null = [IO.Directory]::CreateDirectory($Pendientes) }
    $zip = Join-Path $Pendientes $release.Nombre
    $sha = "$zip.sha256"
    $marcaPrevia = Join-Path $Pendientes 'pendiente.json'
    try {
        if ((Test-Path -LiteralPath $zip) -and ([IO.File]::ReadAllText($marcaPrevia) | ConvertFrom-Json).Version -eq $release.Version) { return $release.Version }
    } catch {}
    try {
        Save-AldiaDescarga $release.Sha $sha 15
        $esperado = ([IO.File]::ReadAllText($sha) -split '\s+')[0].ToLowerInvariant()
        if ($esperado -notmatch '^[0-9a-f]{64}$') { throw 'El hash publicado no es válido.' }
        Save-AldiaDescarga $release.Zip $zip $Timeout
        if ((Get-AldiaHashSha256 $zip) -ne $esperado) { throw 'El SHA-256 de la descarga no coincide con el publicado.' }
        $marca = @{ Version = $release.Version; Archivo = $release.Nombre; Sha256 = $esperado } | ConvertTo-Json -Compress
        [IO.File]::WriteAllText($marcaPrevia, $marca, [Text.UTF8Encoding]::new($false))
        if ($Protegida) { foreach ($f in $zip, $marcaPrevia) { Set-AldiaPropietarioAdmin $f } }
        $release.Version
    } catch {
        foreach ($f in $zip, $sha) { try { [IO.File]::Delete($f) } catch {} }
        throw
    } finally { try { [IO.File]::Delete($sha) } catch {} }
}

function Expand-AldiaPaquete {
    # Descomprime sin dejar que ninguna entrada salga de $Destino (rutas absolutas, '..', unidades).
    param([string]$Zip, [string]$Destino)
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $raiz = [IO.Path]::GetFullPath($Destino).TrimEnd('\') + '\'
    $archivo = [IO.Compression.ZipFile]::OpenRead($Zip)
    try {
        if ($archivo.Entries.Count -gt 300) { throw 'El paquete tiene demasiados archivos.' }
        foreach ($e in $archivo.Entries) {
            $relativa = $e.FullName -replace '/', '\'
            if (!$relativa -or $relativa.EndsWith('\')) { continue }
            if ($relativa -match '(^|\\)\.\.(\\|$)|:' -or $relativa.StartsWith('\')) { throw "Ruta no permitida en el paquete: $relativa" }
            $final = [IO.Path]::GetFullPath($raiz + $relativa)
            if (!$final.StartsWith($raiz, [StringComparison]::OrdinalIgnoreCase)) { throw "Ruta no permitida en el paquete: $relativa" }
            $null = [IO.Directory]::CreateDirectory((Split-Path $final))
            [IO.Compression.ZipFileExtensions]::ExtractToFile($e, $final, $true)
        }
    } finally { $archivo.Dispose() }
}

function Get-AldiaArchivosPaquete {
    # Comprueba que el paquete es exactamente lo que dice su manifiesto (ni más ni menos) y de la versión esperada.
    param([string]$Carpeta, [string]$Version)
    $manifiesto = Import-PowerShellDataFile (Join-Path $Carpeta 'Aldia.psd1') -ErrorAction Stop
    if ((ConvertTo-AldiaVersion $manifiesto.ModuleVersion) -ne (ConvertTo-AldiaVersion $Version)) { throw 'La versión del paquete no coincide con la publicada.' }
    $lista = @($manifiesto.FileList | ForEach-Object { $_ -replace '/', '\' })
    $base = [IO.Path]::GetFullPath($Carpeta).TrimEnd('\') + '\'
    $presentes = @(Get-ChildItem -LiteralPath $Carpeta -Recurse -File -Force | ForEach-Object { $_.FullName.Substring($base.Length) })
    $sobran = @($presentes | Where-Object { $_ -notin $lista })
    $faltan = @($lista | Where-Object { $_ -notin $presentes })
    if ($sobran.Count -or $faltan.Count) { throw 'El contenido del paquete no coincide con su manifiesto.' }
    foreach ($imprescindible in 'aldia.ps1', 'Aldia.psm1', 'Aldia.psd1') {
        if ($imprescindible -notin $lista) { throw "Al paquete le falta $imprescindible." }
    }
    $lista
}

function Copy-AldiaPaquete {
    param([string]$Origen, [string]$Destino, [string[]]$Archivos, [switch]$Protegida)
    foreach ($archivo in $Archivos) {
        $objetivo = Join-Path $Destino $archivo
        $carpeta = Split-Path $objetivo
        if ($Protegida) {
            New-AldiaDirectorioProtegido $carpeta
            if (Test-Path -LiteralPath $objetivo) { Assert-AldiaPermisos $objetivo }
        } else { $null = [IO.Directory]::CreateDirectory($carpeta) }
        Copy-Item -LiteralPath (Join-Path $Origen $archivo) -Destination $objetivo -Force -ErrorAction Stop
        Unblock-File -LiteralPath $objetivo -ErrorAction SilentlyContinue
        if ($Protegida) { Set-AldiaPropietarioAdmin $objetivo }
    }
    # Aldia.psm1 carga todos los .ps1 de src: uno que ya no existe en la versión nueva no puede quedarse.
    foreach ($viejo in @(Get-ChildItem -LiteralPath (Join-Path $Destino 'src') -Filter '*.ps1' -File -ErrorAction SilentlyContinue)) {
        if ("src\$($viejo.Name)" -notin $Archivos) { Remove-Item -LiteralPath $viejo.FullName -Force -ErrorAction Stop }
    }
}

function Install-AldiaActualizacionPendiente {
    # Aplica la versión ya descargada y verificada. Se llama al terminar, para que la nueva se use al volver a abrir.
    param([string]$Carpeta, [string]$Pendientes, [switch]$Protegida)
    $marca = Join-Path $Pendientes 'pendiente.json'
    if (!(Test-Path -LiteralPath $marca)) { return $null }
    if ($Protegida) { Assert-AldiaPermisos $Pendientes; Assert-AldiaPermisos $marca }
    $datos = [IO.File]::ReadAllText($marca) | ConvertFrom-Json
    $zip = Join-Path $Pendientes ([IO.Path]::GetFileName([string]$datos.Archivo))
    $temporal = Join-Path $Pendientes ('paquete-' + [guid]::NewGuid().ToString('N'))
    try {
        if (!(Test-AldiaVersionNueva (Get-AldiaVersionLocal $Carpeta) $datos.Version)) { return $null }
        if ($Protegida) { Assert-AldiaPermisos $zip }
        if ((Get-AldiaHashSha256 $zip) -ne [string]$datos.Sha256) { throw 'El paquete descargado cambió después de verificarlo.' }
        Expand-AldiaPaquete $zip $temporal
        $archivos = Get-AldiaArchivosPaquete $temporal $datos.Version
        Copy-AldiaPaquete $temporal $Carpeta $archivos -Protegida:$Protegida
        [string]$datos.Version
    } finally {
        try { Remove-Item -LiteralPath $temporal -Recurse -Force -ErrorAction Stop } catch {}
        foreach ($f in $zip, $marca) { try { [IO.File]::Delete($f) } catch {} }
    }
}

function Update-AldiaInstalado {
    # Tarea programada (elevada): descarga, verifica y aplica al terminar. Nunca hace fallar la ejecución.
    param([string]$Carpeta)
    if ((Get-AldiaCanal $Carpeta) -ne 'instalado') { return }
    $pendientes = Join-Path $env:ProgramData 'Aldia\actualizacion'
    try {
        $null = Save-AldiaActualizacion $Carpeta $pendientes -Protegida
        $version = Install-AldiaActualizacionPendiente $Carpeta $pendientes -Protegida
        if ($version) { Write-AldiaLog "Al Día se actualizó a la versión $version. Se usará en la próxima ejecución." }
    } catch {
        try { Write-AldiaLog "No se pudo actualizar Al Día: $($_.Exception.Message)" } catch {}
    }
}

function Start-AldiaActualizacionPortatil {
    # Carpeta portátil: descarga y verifica en segundo plano, sin tocar nada de la ventana.
    param([string]$Carpeta)
    if ((Get-AldiaCanal $Carpeta) -ne 'portatil') { return $null }
    try {
        $ps = [powershell]::Create()
        $null = $ps.AddScript({
            param($Modulo, $Carpeta)
            try {
                Import-Module $Modulo -ErrorAction Stop
                & (Get-Module Aldia) { param($c) $null = Save-AldiaActualizacion $c (Join-Path $c '.actualizacion') -Timeout 45 } $Carpeta
            } catch {}
        }).AddArgument((Join-Path $Carpeta 'Aldia.psd1')).AddArgument($Carpeta)
        $null = $ps.BeginInvoke()
        $ps
    } catch { $null }
}

function Complete-AldiaActualizacionPortatil {
    # Al cerrar la ventana: aplica lo que se descargó y verificó durante la sesión.
    param([string]$Carpeta)
    if ((Get-AldiaCanal $Carpeta) -ne 'portatil') { return }
    try { $null = Install-AldiaActualizacionPendiente $Carpeta (Join-Path $Carpeta '.actualizacion') } catch {}
}

function Get-AldiaVersionGaleria {
    param([int]$Timeout = 5)
    $versiones = foreach ($p in @(Invoke-AldiaHttp $script:AldiaUrlGaleria -Timeout $Timeout)) {
        $texto = $p.properties.Version
        if ($texto -is [Xml.XmlElement]) { $texto = $texto.InnerText }
        if (ConvertTo-AldiaVersion $texto) { [string]$texto }
    }
    @($versiones | Sort-Object { ConvertTo-AldiaVersion $_ } -Descending)[0]
}

function Show-AldiaAvisoVersion {
    # Galería (Install-Module): solo un aviso de una línea, una vez por versión. Nunca se reinstala solo.
    param([string]$Carpeta, [string]$Estado = (Join-Path $env:LOCALAPPDATA 'Aldia\version.json'))
    try {
        if ($env:ALDIA_SIN_AVISO_VERSION -or (Get-AldiaCanal $Carpeta) -ne 'galeria' -or ![Environment]::UserInteractive) { return }
        $datos = @{}
        if (Test-Path -LiteralPath $Estado) {
            $leido = [IO.File]::ReadAllText($Estado) | ConvertFrom-Json
            foreach ($p in $leido.PSObject.Properties) { $datos[$p.Name] = $p.Value }
        }
        $actual = Get-AldiaVersionLocal $Carpeta
        if ((Test-AldiaVersionNueva $actual $datos.ultima) -and $datos.avisado -ne $datos.ultima) {
            Write-Host "Hay una versión nueva de Al Día: $($datos.ultima) (tienes $actual). Para actualizar: Update-Module Aldia" -ForegroundColor Cyan
            $datos.avisado = $datos.ultima
            Save-AldiaEstadoVersion $Estado $datos
        }
        $comprobado = 0.0
        if ([double]::TryParse("$($datos.comprobado)", [ref]$comprobado) -and
            ([DateTimeOffset]::UtcNow.ToUnixTimeSeconds() - $comprobado) -lt 86400) { return }
        $ps = [powershell]::Create()
        $null = $ps.AddScript({
            param($Modulo, $Estado)
            try {
                Import-Module $Modulo -ErrorAction Stop
                & (Get-Module Aldia) { param($e) Update-AldiaEstadoGaleria $e } $Estado
            } catch {}
        }).AddArgument((Join-Path $Carpeta 'Aldia.psd1')).AddArgument($Estado)
        $null = $ps.BeginInvoke()
    } catch {}
}

function Update-AldiaEstadoGaleria {
    param([string]$Estado)
    $ultima = Get-AldiaVersionGaleria
    if (!$ultima) { return }
    $datos = @{}
    try { foreach ($p in ([IO.File]::ReadAllText($Estado) | ConvertFrom-Json).PSObject.Properties) { $datos[$p.Name] = $p.Value } } catch {}
    $datos.ultima = $ultima
    $datos.comprobado = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    Save-AldiaEstadoVersion $Estado $datos
}

function Save-AldiaEstadoVersion {
    param([string]$Estado, [hashtable]$Datos)
    try {
        $null = [IO.Directory]::CreateDirectory((Split-Path $Estado))
        [IO.File]::WriteAllText($Estado, ($Datos | ConvertTo-Json -Compress), [Text.UTF8Encoding]::new($false))
    } catch {}
}
