function Show-AldiaVulnerabilidadesCli {
    param($Config)
    $informe = Get-AldiaVulnerabilidades $Config -Progreso {
        param($actual,$total)
        Write-Progress -Activity 'Vulnerabilidades' -Status "Comprobando $actual/$total…" -PercentComplete (100*$actual/$total)
    }
    Write-Progress -Activity 'Vulnerabilidades' -Completed
    foreach ($aviso in $informe.Avisos) { Write-Host $aviso -ForegroundColor Yellow }
    Write-Host (Format-AldiaRevisionSeguridad $informe)
    $hallazgos = @($informe.Programas | Where-Object Nivel -gt 0)
    Show-AldiaTabla 'Vulnerabilidades conocidas' $hallazgos ([ordered]@{ Nombre=40; Version=14; Riesgo=9; CVE=3; Peor=19 })
    foreach ($p in $hallazgos) {
        Write-Host "$($p.Nombre) · $($p.Detalle)"
        if ($p.Accion) { Write-Host "  $($p.Accion)" }
        foreach ($c in $p.Fallos) { Write-Host "  $($c.Url)" }
    }
}

function Show-AldiaSaludCli {
    $salud = @(Get-AldiaSalud)
    $bien = @($salud | Where-Object Estado -eq bien).Count
    Write-Host "$bien de $($salud.Count) bien"
    Show-AldiaTabla 'Salud del PC' $salud ([ordered]@{ Nombre=32; Estado=11; Detalle=70 })
    $red = $salud | Where-Object Id -eq red
    foreach ($c in $red.Datos) { Write-Host "  $($c.Direccion) · puerto $($c.Puerto) · $($c.Programa) $($c.Ruta) $($c.Explicacion)" }
}

function Get-AldiaSeveridadWU {
    param($Actualizacion)
    $nivel = switch ($Actualizacion.MsrcSeverity) {
        Critical { 'Crítica' }
        Important { 'Importante' }
        Moderate { 'Moderada' }
        Low { 'Baja' }
        default { $Actualizacion.MsrcSeverity }
    }
    if ($nivel) { "Seguridad · $nivel" }
}
