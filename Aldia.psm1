foreach ($archivo in Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot 'src') -Filter '*.ps1') {
    . $archivo.FullName
}

function Start-Aldia {
    <#
    .SYNOPSIS
    Abre Al Día. Sin nada más abre la ventana; con una orden la ejecuta en la consola.
    .EXAMPLE
    aldia
    .EXAMPLE
    aldia diagnostico
    .EXAMPLE
    aldia instalar
    #>
    $argumentos = @(foreach ($a in $args) {
        if ($a -is [array]) { $a -join ',' } else { [string]$a }
    })
    if (!$argumentos.Count) { $argumentos = @('gui') }
    Show-AldiaAvisoVersion $PSScriptRoot
    $entrada = Join-Path $PSScriptRoot 'aldia.ps1'
    # Devolver el código como lo haría un programa, sin escribirlo en pantalla ni cerrar la consola.
    $global:LASTEXITCODE = [int](@(Invoke-AldiaCli -Argumentos $argumentos -Entrada $entrada) | Select-Object -Last 1)
}

Set-Alias -Name aldia -Value Start-Aldia
Export-ModuleMember -Function Invoke-AldiaCli,Start-Aldia -Alias aldia
