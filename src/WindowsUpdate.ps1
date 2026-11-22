function New-AldiaSesionWU { New-Object -ComObject Microsoft.Update.Session }

function Find-AldiaActualizacionesWU {
    param($Sesion, [ValidateSet('Software','Driver')]$Tipo)
    $buscador = $Sesion.CreateUpdateSearcher()
    try {
        if (!(Test-AldiaEquipoGestionado) -and (Test-AldiaMicrosoftUpdate)) {
            $buscador.ServiceID = $script:AldiaMicrosoftUpdateId
            $buscador.ServerSelection = 3
        }
    } catch {}
    $resultado = $buscador.Search("IsInstalled=0 and IsHidden=0 and Type='$Tipo'")
    foreach ($actualizacion in $resultado.Updates) { $actualizacion }
}

function New-AldiaColeccionWU { ,(New-Object -ComObject Microsoft.Update.UpdateColl) }

function Invoke-AldiaDescargaWU {
    param($Sesion, $Coleccion)
    $descarga = $Sesion.CreateUpdateDownloader()
    $descarga.Updates = $Coleccion
    $descarga.Download()
}

function Invoke-AldiaInstalacionWU {
    param($Sesion, $Coleccion)
    $instalador = $Sesion.CreateUpdateInstaller()
    $instalador.Updates = $Coleccion
    $instalador.AllowSourcePrompts = $false
    $instalador.Install()
}

function Update-AldiaWU {
    param($Sesion, $Actualizaciones, [string]$Fuente, [switch]$Simular)
    foreach ($u in $Actualizaciones) { Update-AldiaWUItem $Sesion $u $Fuente -Simular:$Simular }
}

function Update-AldiaWUItem {
    param($Sesion, $u, [string]$Fuente, [switch]$Simular)
    $kb = (@($u.KBArticleIDs | ForEach-Object { "KB$_" }) -join ', ')
    $id = $u.Identity.UpdateID
    if (!$id) { $id = $u.Title }
    if ($u.InstallationBehavior.CanRequestUserInput) {
        New-AldiaResultado $Fuente $id omitido $null 'Requiere interacción.' -Titulo $u.Title
        return
    }
    if ($Simular) {
        Write-Host "Windows Update: $($u.Title) [UpdateID: $id]"
        if (!$u.EulaAccepted) { Write-Host '  IUpdate.AcceptEula()' }
        Write-Host '  IUpdateDownloader.Download()'
        Write-Host '  IUpdateInstaller.Install()'
        New-AldiaResultado $Fuente $id simulado $null $kb -Titulo $u.Title
        return
    }
    try {
        if (!$u.EulaAccepted) { $u.AcceptEula() }
        $coleccion = New-AldiaColeccionWU
        $null = $coleccion.Add($u)
        $descarga = Invoke-AldiaDescargaWU $Sesion $coleccion
        if (!$u.IsDownloaded) { throw "Error de descarga de Windows Update (código $($descarga.ResultCode))." }
        $instalacion = Invoke-AldiaInstalacionWU $Sesion $coleccion
        $detalle = $instalacion.GetUpdateResult(0)
        $estado = if ($detalle.ResultCode -eq 2) { 'actualizado' } else { 'fallo' }
        $r = New-AldiaResultado $Fuente $id $estado $detalle.ResultCode $kb -Reinicio ($instalacion.RebootRequired -or $detalle.RebootRequired) -Titulo $u.Title
        $r | Add-Member -NotePropertyName KB -NotePropertyValue $kb
        $r | Add-Member -NotePropertyName Definiciones -NotePropertyValue ($u.Categories.CategoryID -contains 'e0789628-ce08-4437-be74-2495b842f43b') -PassThru
    } catch { New-AldiaResultado $Fuente $id fallo $null $_.Exception.Message -Titulo $u.Title }
}

function Update-AldiaWindows {
    param($Config, [switch]$Simular)
    $sesion = New-AldiaSesionWU
    $pendientes = @(Find-AldiaActualizacionesWU $sesion Software | Where-Object { !(Test-AldiaWUFijada $Config $_) })
    Update-AldiaWU $sesion $pendientes windows -Simular:$Simular
}

function Test-AldiaWUFijada {
    param($Config, $Actualizacion)
    $kb = @($Actualizacion.KBArticleIDs | ForEach-Object { if ($_){ "KB$_" } })
    Test-AldiaFijado $Config windows $Actualizacion.Identity.UpdateID $kb
}
