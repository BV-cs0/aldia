function Get-AldiaRutasVelocidad {
    param($Unidad)
    # Primero la carpeta temporal del usuario si está en esa unidad: si el proceso se corta, el
    # archivo de prueba no queda suelto en la raíz del disco.
    $raiz = '{0}:\' -f $Unidad
    $temp = [IO.Path]::GetTempPath()
    if ([IO.Path]::GetPathRoot($temp) -eq $raiz -and $temp -ne $raiz) { $temp }
    $raiz
}

function Open-AldiaArchivoVelocidad {
    param([string]$Ruta)
    # El valor adicional pide entrada y salida sin caché de Windows.
    $opciones = [IO.FileOptions]([IO.FileOptions]0x20000000 -bor [IO.FileOptions]::WriteThrough -bor [IO.FileOptions]::DeleteOnClose)
    [IO.FileStream]::new($Ruta,[IO.FileMode]::CreateNew,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None,1,$opciones)
}

function Measure-AldiaVelocidadUnidad {
    param($Unidad, [long]$Tamano, $Control, [scriptblock]$Progreso)
    $bloque = 1MB
    $buffer = [byte[]]::new($bloque + 4095)
    $azar = [Security.Cryptography.RandomNumberGenerator]::Create()
    try { $azar.GetBytes($buffer) } finally { $azar.Dispose() }
    $pin = [Runtime.InteropServices.GCHandle]::Alloc($buffer,[Runtime.InteropServices.GCHandleType]::Pinned)
    $archivo = $null
    try {
        $offset = [int]((4096 - ($pin.AddrOfPinnedObject().ToInt64() % 4096)) % 4096)
        foreach ($carpeta in Get-AldiaRutasVelocidad $Unidad) {
            $limite = [datetime]::UtcNow.AddDays(-1)
            Get-ChildItem -LiteralPath $carpeta -Filter 'aldia-velocidad-*.tmp' -File -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -match '^aldia-velocidad-[0-9a-f-]{36}\.tmp$' -and $_.LastWriteTimeUtc -lt $limite -and !($_.Attributes -band [IO.FileAttributes]::ReparsePoint) } |
                Remove-Item -ErrorAction SilentlyContinue
            $candidato = Join-Path $carpeta ('aldia-velocidad-{0}.tmp' -f [guid]::NewGuid())
            try {
                $archivo = Open-AldiaArchivoVelocidad $candidato
                break
            } catch {}
        }
        if (!$archivo) { throw 'No se pudo crear el archivo de prueba en esa unidad.' }
        foreach ($escribir in $true,$false) {
            if (!$escribir) { $archivo.Position = 0 }
            $reloj = [Diagnostics.Stopwatch]::StartNew()
            $anterior = -1
            for ($i = 0L; $i -lt $Tamano; $i += $bloque) {
                if ($Control -and $Control.Cancelar) { throw [OperationCanceledException]::new('Prueba cancelada.') }
                $cantidad = [int][math]::Min($bloque,$Tamano - $i)
                if ($escribir) { $archivo.Write($buffer,$offset,$cantidad) }
                elseif ($archivo.Read($buffer,$offset,$cantidad) -ne $cantidad) { throw 'No se pudo leer todo el archivo de prueba.' }
                $porcentaje = [int][math]::Floor(50 * ($i + $cantidad) / $Tamano) + 50 * [int](!$escribir)
                if ($Progreso -and $porcentaje -gt $anterior) {
                    & $Progreso $porcentaje
                    $anterior = $porcentaje
                }
            }
            [math]::Round($Tamano / 1000000 / [math]::Max(0.000001,$reloj.Elapsed.TotalSeconds))
        }
    } finally {
        try { if ($archivo) { $archivo.Dispose() } }
        finally { $pin.Free() }
    }
}

function Test-AldiaVelocidadDisco {
    param([ValidatePattern('^[A-Z]$')][string]$Unidad = ($env:SystemDrive -replace ':$'),
        [ValidateRange(4096,1073741824)][long]$Tamano = 1GB, $Config, $Hardware, $Control, [scriptblock]$Progreso)
    if ($Tamano % 4096) { throw 'Usa un tamaño múltiplo de 4096 bytes.' }
    $v = try { Get-AldiaVolumenDisco $Unidad } catch {}
    $libre = $v.SizeRemaining
    if ($null -eq $libre) {
        try {
            $unidadWindows = [IO.DriveInfo]::new($Unidad)
            if ($unidadWindows.IsReady -and $unidadWindows.DriveType -in 'Fixed','Removable') { $libre = $unidadWindows.AvailableFreeSpace }
        } catch {}
    }
    if ($null -eq $libre) { throw 'Windows no pudo comprobar el espacio libre de esa unidad.' }
    if ($libre -lt 3GB) { throw 'Hacen falta al menos 3 GB libres para hacer la prueba.' }
    if (!$Config) { $Config = Get-AldiaConfig }
    $bateria = Get-AldiaBateria
    if ($bateria.EnBateria -and $bateria.Carga -lt $Config.bateriaMinima) {
        throw 'Conecta el PC a la corriente para hacer la prueba.'
    }
    $escritura,$lectura = Measure-AldiaVelocidadUnidad $Unidad $Tamano $Control $Progreso
    $disco = @($Hardware.Discos | Where-Object { $_.Unidades.Letra -contains $Unidad } | Select-Object -First 1)
    $tipo = $disco.Tipo
    $minimo = @{ 'Disco duro'=100; 'SSD SATA'=450; 'SSD NVMe'=1500; 'Memoria interna (eMMC)'=100 }
    $detalle = '{0}: · Escritura {1} MB/s · Lectura {2} MB/s' -f $Unidad,$escritura,$lectura
    if ($tipo -and $minimo.ContainsKey($tipo)) {
        $detalle += if ($lectura -lt $minimo[$tipo]) { ' · Más lento de lo normal para este tipo de disco.' } else { " · Normal para este tipo de disco ($tipo)." }
    }
    [pscustomobject]@{ Unidad=$Unidad; Escritura=$escritura; Lectura=$lectura; Detalle=$detalle }
}
