$ErrorActionPreference = 'Stop'
try {
    Import-Module (Join-Path $PSScriptRoot 'Aldia.psd1') -ErrorAction Stop
    $argumentos = @(foreach ($a in $args) {
        if ($a -is [array]) { $a -join ',' } else { [string]$a }
    })
    exit (Invoke-AldiaCli -Argumentos $argumentos -Entrada $PSCommandPath)
} catch {
    if ($args -notcontains '--programado') { Write-Host $_.Exception.Message -ForegroundColor Red }
    exit 2
}
