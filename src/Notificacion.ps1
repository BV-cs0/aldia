function Send-AldiaToast {
    param([string]$Mensaje, [switch]$PropagarError)
    try {
        if ($PSVersionTable.PSEdition -eq 'Core') {
            $ruta = $PSCommandPath.Replace("'", "''")
            $texto = $Mensaje.Replace("'", "''")
            Invoke-AldiaWindowsPowerShell ". '$ruta'; Send-AldiaToast '$texto' -PropagarError"
            return
        }
        $null = [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType=WindowsRuntime]
        $null = [Windows.UI.Notifications.ToastNotification, Windows.UI.Notifications, ContentType=WindowsRuntime]
        $xml = [Windows.UI.Notifications.ToastNotificationManager]::GetTemplateContent(
            [Windows.UI.Notifications.ToastTemplateType]::ToastText02)
        $nodos = $xml.GetElementsByTagName('text')
        $null = $nodos.Item(0).AppendChild($xml.CreateTextNode('Al Día'))
        $null = $nodos.Item(1).AppendChild($xml.CreateTextNode($Mensaje))
        $toast = [Windows.UI.Notifications.ToastNotification]::new($xml)
        $id = '{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1.0\powershell.exe'
        [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($id).Show($toast)
    } catch {
        if ($PropagarError) { throw }
        Write-AldiaLog "No se pudo mostrar la notificación: $_"
    }
}
