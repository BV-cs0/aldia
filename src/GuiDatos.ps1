function ConvertTo-AldiaFilaGui {
    param($Fuente, $Elemento, $Config)
    $id = $Elemento.Id
    $nombre = $Elemento.Nombre
    $motivo = ''
    $hardware = ''
    $bytes = 0
    switch ($Fuente) {
        'pnp' {
            if (!$Elemento.Problema) { return }
            $id = $hardware = $Elemento.HardwareID
            $detalle = $Elemento.Clase
            $motivo = "Código $($Elemento.Codigo): $($Elemento.Mensaje). Consulta al fabricante."
        }
        { $_ -in 'drivers','windows' } {
            $id = [string]$Elemento.Identity.UpdateID
            $nombre = $Elemento.Title
            $bytes = [long]$Elemento.MaxDownloadSize
            if ($Fuente -eq 'drivers') {
                $fecha = $Elemento.DriverVerDate
                if ($fecha -is [datetime]) { $fecha = $fecha.ToString('dd/MM/yyyy',[cultureinfo]::InvariantCulture) }
                $detalle = (@($Elemento.DriverManufacturer, $Elemento.DriverClass, $fecha) | Where-Object { $_ }) -join ' · '
            } else {
                $detalle = ($Elemento.KBArticleIDs | ForEach-Object { "KB$_" }) -join ', '
            }
            if (!$id) { $motivo = 'Windows Update no proporcionó un identificador.' }
            if ($Elemento.InstallationBehavior.CanRequestUserInput) { $motivo = 'Requiere interacción.' }
        }
        { $_ -in 'apps','npm' } {
            if (!$nombre) { $nombre = $id }
            $antes = if ($Elemento.Version -and !$Elemento.VersionDesconocida) { $Elemento.Version } else { 'Versión desconocida' }
            $detalle = "$antes → $($Elemento.Disponible)"
            if ($id -in $Config.excluir) { $motivo = 'Excluido en la configuración.' }
            if ($Fuente -eq 'apps') {
                if ($Elemento.Origen -notin 'winget','msstore') { $motivo = 'Origen sin confirmar.' }
                if ($Elemento.Explicito) { $motivo = 'Paquete fijado. Actualízalo manualmente.' }
            }
        }
    }
    $categorias = @{ pnp='Dispositivos sin driver'; drivers='Drivers'; windows='Actualizaciones de Windows'; apps='Programas'; npm='npm' }
    $iconos = @{ pnp=0xE7BA; drivers=0xE950; windows=0xE777; apps=0xE71D; npm=0xE8B7 }
    $disponible = !$motivo
    [pscustomobject]@{
        Clave=[guid]::NewGuid().ToString(); Fuente=$Fuente; Categoria=$categorias[$Fuente]
        Icono=[string][char]$iconos[$Fuente]; Id=$id; Nombre=$nombre; Detalle=$detalle
        Hardware=$hardware; Bytes=$bytes; Motivo=$motivo; Habilitada=$disponible; Seleccionada=$disponible
        Estado=if ($disponible) { 'Pendiente' } else { 'No disponible' }
        Paquete=if ($Fuente -in 'apps','npm') { $Elemento }
    }
}

function Get-AldiaTrabajosGui {
    param($Filas)
    $orden = @{ windows=0; drivers=1; apps=2; npm=4 }
    $Filas | Where-Object { $_.Habilitada -and $_.Seleccionada -and $orden.ContainsKey($_.Fuente) } |
        Sort-Object @{Expression = { if ($_.Fuente -eq 'apps' -and $_.Id -eq 'Microsoft.AppInstaller') { 3 } else { $orden[$_.Fuente] } }} |
        Select-Object Clave,Fuente,Id,Nombre,Paquete
}

function Format-AldiaCantidadGui {
    param([int]$Cantidad, [string]$Singular, [string]$Plural, [string]$Formato = "{0} {1}")
    $texto = if ($Cantidad -eq 1) { $Singular } else { $Plural }
    $Formato -f $Cantidad, $texto
}

function Get-AldiaResumenGui {
    param($Resultados)
    [pscustomobject]@{
        Actualizadas=@($Resultados | Where-Object Estado -eq actualizado).Count
        Fallidas=@($Resultados | Where-Object { $_.Estado -in 'fallo','timeout','persistente' }).Count
        Reinicio=@($Resultados | Where-Object RequiereReinicio).Count -gt 0
    }
}

function Get-AldiaUrlDriverGui {
    param([string]$Hardware)
    if ($Hardware.Trim()) { 'https://www.bing.com/search?q=' + [uri]::EscapeDataString($Hardware) }
}

function Set-AldiaConfigGui {
    param($Config, $Cambios)
    $hora = ([string]$Cambios.Hora).Trim()
    if (!(Test-AldiaHora $hora)) { throw 'Introduce una hora válida en formato HH:mm (por ejemplo, 08:30).' }
    foreach ($fuente in 'apps','windows','drivers','npm') {
        if ($Cambios.Fuentes[$fuente] -isnot [bool]) { throw "Valor inválido para la fuente $fuente." }
    }
    if ($Cambios.Activa -isnot [bool]) { throw 'Indica si la actualización automática está activada.' }
    $Config.horaDiaria = $hora
    foreach ($fuente in 'apps','windows','drivers','npm') { $Config.fuentes.$fuente = $Cambios.Fuentes[$fuente] }
    $Config
}

function Get-AldiaDemoGui {
    param($Config)
    ConvertTo-AldiaFilaGui pnp ([pscustomobject]@{
        Problema=$true; Nombre='Controladora de red'; Clase='Red'; Codigo=28
        Mensaje='no tiene driver instalado'; HardwareID='PCI\VEN_1234&DEV_5678'
    }) $Config
    ConvertTo-AldiaFilaGui drivers ([pscustomobject]@{
        Title='Intel® Wi-Fi'; DriverManufacturer='Intel'; DriverClass='Red'
        DriverVerDate=[datetime]'2025-09-15'; Identity=@{ UpdateID='demo-driver' }; MaxDownloadSize=18MB
    }) $Config
    ConvertTo-AldiaFilaGui windows ([pscustomobject]@{
        Title='Actualización acumulativa de Windows'; KBArticleIDs=@('5000000')
        Identity=@{UpdateID='demo-windows'}; MaxDownloadSize=420MB
    }) $Config
    foreach ($p in @(
        @{ Nombre='Visual Studio Code'; Id='Microsoft.VisualStudioCode'; Version='1.99'; Disponible='1.100'; Origen='winget' }
        @{ Nombre='Aplicación fijada'; Id='Ejemplo.Aplicacion'; Version='2.0'; Disponible='3.0'; Origen='winget'; Explicito=$true }
    )) { ConvertTo-AldiaFilaGui apps ([pscustomobject]$p) $Config }
    ConvertTo-AldiaFilaGui npm ([pscustomobject]@{ Id='typescript'; Version='5.8'; Disponible='5.9' }) $Config
}
