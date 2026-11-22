foreach ($archivo in Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot 'src') -Filter '*.ps1') {
    . $archivo.FullName
}
Export-ModuleMember -Function Invoke-AldiaCli
