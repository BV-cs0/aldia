# Al Día

Al Día revisa y actualiza aplicaciones de winget y Microsoft Store, actualizaciones de Windows, drivers ofrecidos por Windows Update y paquetes globales de npm. También detecta incidencias de dispositivos y recomienda herramientas oficiales del fabricante. Si Dell Command Update está instalado, puede aplicarle sus actualizaciones. Al Día avisa cuando hay que reiniciar.

## Requisitos e instalación

Windows 10 u 11 con Windows PowerShell 5.1. PowerShell 7 también puede ejecutar el CLI. Las aplicaciones requieren winget (App Installer) y la fuente npm requiere npm. Las fuentes que descargan actualizaciones necesitan conexión.

Desde Windows PowerShell como administrador, clona el repositorio con Git. Sustituye RUTA_O_URL_DEL_REPOSITORIO por el origen del proyecto.

~~~powershell
git clone RUTA_O_URL_DEL_REPOSITORIO
cd RUTA_DE_LA_COPIA\aldia
.\aldia.ps1 instalar
~~~

La instalación copia el programa y la configuración a Program Files para que la tarea elevada ejecute archivos modificables por administradores. La tarea se ejecuta con el usuario que la instaló, durante su sesión. Se dispara a la hora configurada, repite cada hora durante doce horas y vuelve a intentarlo quince minutos después de iniciar sesión.

## Órdenes

Ejecuta estas órdenes con el script de la copia instalada o desde el repositorio.

| Orden | Acción |
| --- | --- |
| .\aldia.ps1 revisar | Consulta las actualizaciones y las incidencias de dispositivos. |
| .\aldia.ps1 actualizar | Actualiza todas las fuentes habilitadas. |
| .\aldia.ps1 actualizar --simular | Consulta las fuentes y muestra las operaciones previstas y el total, sin instalar. |
| .\aldia.ps1 actualizar --solo apps,drivers | Limita la ejecución a esas fuentes habilitadas. |
| .\aldia.ps1 actualizar --programado | Escribe al log, comprueba la batería y espera 20 horas desde la última ejecución completada (código 0 o 1). |
| .\aldia.ps1 actualizar --programado --forzar | Omite el límite de 20 horas. |
| .\aldia.ps1 drivers | Muestra incidencias, ofertas de Windows Update y recomendaciones del fabricante. |
| .\aldia.ps1 inventario | Muestra los programas de instaladores clásicos (ARP), salvo los juegos gestionados por Steam. |
| .\aldia.ps1 historial -n 10 | Resume las diez últimas ejecuciones. |
| .\aldia.ps1 config | Abre la configuración instalada en el Bloc de notas elevado. |
| .\aldia.ps1 desinstalar | Quita la tarea y el programa. Añade --todo para borrar también los registros. |

Los códigos de salida son 0 si todo fue bien, 1 si falló alguna actualización, 2 si falló la herramienta y 3 si se omitió la ejecución.

## Configuración y registros

Edita config.json desde la orden config. config.default.json incluye todos los valores predeterminados. Puedes habilitar cada fuente en fuentes, excluir Id de winget y nombres npm en excluir, activar versiones desconocidas y ajustar el timeout por paquete. Las opciones de drivers permiten excluir clases y repetir la detección de dispositivos. También puedes elegir si crear puntos de restauración, la batería mínima, los días de retención y cuándo mostrar notificaciones (siempre, solo-cambios, solo-errores o nunca). Después de cambiar horaDiaria, ejecuta instalar de nuevo para aplicar la hora a la tarea.

Los logs están en %ProgramData%\Aldia\logs y el historial en %ProgramData%\Aldia\historial.jsonl. Cada actualización de winget tiene además su propio log.

## Pruebas

En Windows PowerShell 5.1 con Pester 3.4 disponible, ejecuta Invoke-Pester .\tests desde la carpeta del proyecto.


## Interfaz gráfica

Abre **Al Día** desde el menú Inicio, el escritorio o con PowerShell:

    .\aldia.ps1 gui

El escáner agrupa las actualizaciones y permite elegir cuáles instalar. **Historial**
muestra el resultado de cada ejecución. **Herramientas** reúne las recomendaciones
del fabricante, el inventario y la configuración de la actualización automática.

Para explorar la interfaz y simular una instalación sin consultar el equipo ni pedir
permisos de administrador, usa:

    .\aldia.ps1 gui --demo
