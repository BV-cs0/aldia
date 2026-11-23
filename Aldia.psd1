@{
    RootModule = 'Aldia.psm1'
    ModuleVersion = '1.0.1'
    GUID = '59e4183e-dddd-4eaf-a884-131ca352d3f8'
    Author = 'Bryan Valenzuela'
    Copyright = '(c) 2026 Bryan Valenzuela'
    Description = 'Al Día mantiene Windows al día: actualiza programas (winget, Microsoft Store, npm), Windows Update y drivers, avisa de programas con fallos de seguridad conocidos y revisa la salud del PC (discos, batería, memoria y pantallazos azules). Ventana gráfica en español. Escribe «aldia» para abrirla.'
    PowerShellVersion = '5.1'
    CompatiblePSEditions = @('Desktop','Core')
    FileList = @(
        'aldia.ps1',
        'Aldia.psd1',
        'Aldia.psm1',
        'config.default.json',
        'README.md',
        'LICENSE',
        'Abrir Al Día.cmd',
        'Instalar Al Día.cmd',
        'src\Adopcion.ps1',
        'src\AldiaHttp.ps1',
        'src\Comando.ps1',
        'src\Config.ps1',
        'src\Deshacer.ps1',
        'src\DeshacerSeguridad.ps1',
        'src\DiagnosticoCli.ps1',
        'src\Drivers.ps1',
        'src\Ejecucion.ps1',
        'src\Gui.ps1',
        'src\GuiCambios.ps1',
        'src\GuiDatos.ps1',
        'src\GuiDiagnostico.ps1',
        'src\GuiHardware.ps1',
        'src\GuiPortatil.ps1',
        'src\GuiTrabajo.ps1',
        'src\Hardware.ps1',
        'src\HardwareSalida.ps1',
        'src\Informe.ps1',
        'src\Notificacion.ps1',
        'src\Npm.ps1',
        'src\ProductosMicrosoft.ps1',
        'src\Registro.ps1',
        'src\Requisitos.ps1',
        'src\Salud.ps1',
        'src\SoporteWindows.ps1',
        'src\Tarea.ps1',
        'src\VelocidadDisco.ps1',
        'src\Vulnerabilidades.ps1',
        'src\VulnerabilidadesFuentes.ps1',
        'src\WindowsUpdate.ps1',
        'src\Winget.ps1',
        'gui\Principal.xaml',
        'datos\adopcion.json',
        'datos\cpe.json',
        'datos\windows.json'
    )
    FunctionsToExport = @('Invoke-AldiaCli','Start-Aldia')
    CmdletsToExport = @()
    VariablesToExport = @()
    AliasesToExport = @('aldia')
    PrivateData = @{
        PSData = @{
            Tags = @('Windows','Update','Updater','winget','WindowsUpdate','Drivers','Security','CVE','Diagnostics','SMART','BSOD','Spanish','PSEdition_Desktop','PSEdition_Core')
            ProjectUri = 'https://github.com/BV-cs0/aldia'
            LicenseUri = 'https://github.com/BV-cs0/aldia/blob/main/LICENSE'
            ReleaseNotes = '1.0.1: Al Día pasa a tener licencia MIT. 1.0.0: primera versión publicada (actualizaciones, drivers, avisos de seguridad, salud del PC y pestaña Diagnóstico con la causa de los pantallazos azules).'
        }
    }
}
