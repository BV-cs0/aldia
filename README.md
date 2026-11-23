# Al Día

Al Día revisa y actualiza aplicaciones de winget y Microsoft Store, actualizaciones de Windows, drivers ofrecidos por Windows Update y paquetes globales de npm. También detecta incidencias de dispositivos y recomienda herramientas oficiales del fabricante. Si Dell Command Update está instalado, puede aplicarle sus actualizaciones. Al Día avisa cuando hay que reiniciar.

## Requisitos e instalación

Windows 10 u 11 con Windows PowerShell 5.1. PowerShell 7 también puede ejecutar el CLI. Las aplicaciones requieren winget (App Installer) y la fuente npm requiere npm. Las fuentes que descargan actualizaciones necesitan conexión.

### Desde la PowerShell Gallery (lo más fácil)

Abre Windows PowerShell y escribe:

~~~powershell
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
Install-Module Aldia -Scope CurrentUser
aldia
~~~

La primera línea solo hace falta una vez: permite que Windows ejecute módulos de PowerShell. `aldia` abre la ventana; `aldia diagnostico`, `aldia revisar` y el resto de órdenes funcionan igual que `.\aldia.ps1`. Para dejar la tarea automática, ejecuta `aldia instalar` en un PowerShell abierto como administrador.

### Desde GitHub

Desde Windows PowerShell como administrador:

~~~powershell
git clone https://github.com/BV-cs0/aldia.git
cd aldia
.\aldia.ps1 instalar
~~~

Sin Git, descarga el ZIP desde GitHub, descomprímelo y haz doble clic en «Abrir Al Día.cmd» o «Instalar Al Día.cmd».

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
| .\aldia.ps1 vulnerabilidades | Consulta fallos conocidos en las versiones instaladas y los ordena por riesgo. |
| .\aldia.ps1 salud | Muestra doce comprobaciones de solo lectura, sin pedir elevación. |
| .\aldia.ps1 adoptar | Busca paquetes de winget para programas sin actualizador conocido. |
| .\aldia.ps1 adoptar --id OpenJS.NodeJS.24 | Instala el paquete indicado tras pedir confirmación. Requiere administración. |
| .\aldia.ps1 deshacer --id Git.Git | Vuelve a la versión anterior de la última actualización completada si sigue disponible. Requiere administración. |
| .\aldia.ps1 fijados | Muestra los elementos omitidos por el actualizador tras deshacer. Desde Herramientas puedes dejar de fijarlos. |
| .\aldia.ps1 historial -n 10 | Resume las diez últimas ejecuciones. |
| .\aldia.ps1 config | Abre la configuración instalada en el Bloc de notas elevado. |
| .\aldia.ps1 desinstalar | Quita la tarea y el programa. Añade --todo para borrar también los registros. |

Los códigos de salida son 0 si todo fue bien, 1 si falló alguna actualización, 2 si falló la herramienta y 3 si se omitió la ejecución.

## Configuración y registros

Edita config.json desde la orden config. config.default.json incluye todos los valores predeterminados. Puedes habilitar cada fuente en fuentes, excluir Id de winget y nombres npm en excluir, activar versiones desconocidas y ajustar el timeout por paquete. Las opciones de drivers permiten excluir clases y repetir la detección de dispositivos. También puedes elegir si crear puntos de restauración, la batería mínima, los días de retención y cuándo mostrar notificaciones (siempre, solo-cambios, solo-errores o nunca). Después de cambiar horaDiaria, ejecuta instalar de nuevo para aplicar la hora a la tarea.

La tarea comprueba las vulnerabilidades después de actualizar y añade los casos graves a la notificación. Configura esta comprobación con vulnerabilidades.activado. La clave NVD es opcional y se configura con vulnerabilidades.nvdApiKey. El mapeo a productos de NVD se lee de datos\cpe.json y la caché se guarda en %ProgramData%\Aldia\cache. La orden vulnerabilidades permite consultar manualmente aunque la comprobación automática esté desactivada.

Los logs están en %ProgramData%\Aldia\logs y el historial en %ProgramData%\Aldia\historial.jsonl. Cada actualización de winget tiene además su propio log.

## Pruebas

En Windows PowerShell 5.1 con Pester 3.4 disponible, ejecuta Invoke-Pester .\tests desde la carpeta del proyecto.


## Interfaz gráfica

Abre **Al Día** desde el menú Inicio, el escritorio o con PowerShell:

    .\aldia.ps1 gui

El escáner agrupa las actualizaciones, permite elegir cuáles instalar y muestra los
fallos de seguridad conocidos. **Salud** muestra los diagnósticos y pide confirmación
antes de ejecutar una acción que cambie el sistema. **Historial**
muestra el resultado de cada ejecución. **Herramientas** reúne las recomendaciones
del fabricante, el inventario y la configuración de la actualización automática.

Para explorar la interfaz y simular una instalación sin consultar el equipo ni pedir
permisos de administrador, usa:

    .\aldia.ps1 gui --demo


## Usarlo en el PC de otra persona

Necesitas Windows 10 22H2 o Windows 11 y Windows PowerShell 5.1, que ya viene incluido.
Copia la carpeta completa y abre **Abrir Al Día.cmd** para revisar el PC desde la carpeta o desde
un USB. Para tener el acceso directo y las revisiones automáticas, ejecuta **Instalar Al Día.cmd**
y acepta la solicitud de permisos de Windows. Si tu cuenta es estándar, Windows pedirá la contraseña de un administrador.

Si falta el Instalador de aplicaciones de Microsoft, pulsa **Conseguirlo** en la ventana. También
puedes descargarlo desde [Microsoft](https://aka.ms/getwinget). Mientras tanto puedes revisar Windows y
los drivers. Puedes activar Office y Microsoft Store en Herramientas o en las claves
office y store de config.fuentes.

Pulsa **Guardar informe** en Herramientas o ejecuta
**.\aldia.ps1 informe --ruta "C:\ruta\Informe Al Día.html"**. Si no eliges una ruta, Al Día sugiere
el Escritorio. El informe se puede abrir sin internet e imprimir desde el navegador.

## Diagnóstico del equipo

Abre **Diagnóstico** o ejecuta **.\aldia.ps1 diagnostico** para revisar los discos, la batería, la
memoria y los avisos de estabilidad de los últimos 30 días. Windows puede pedir permiso de
administrador en **Ver detalles** para mostrar la temperatura y el desgaste de los discos.

Para medir la velocidad, pulsa **Probar velocidad** junto a una unidad o ejecuta
**.\aldia.ps1 diagnostico --velocidad --unidad C**. La prueba necesita 3 GB libres y borra su
archivo temporal al terminar. En un portátil con poca batería, conecta primero el cargador.

## Privacidad

Para revisar fallos de seguridad, Al Día consulta NVD y OSV con nombres o identificadores de
programas y sus versiones. Envía a EPSS los identificadores de fallos (CVE) y descarga la lista de
fallos aprovechados activamente de CISA. La clave opcional de NVD solo se envía a NVD. Al Día no
pide cuentas ni envía telemetría. Windows Update, winget, npm y Microsoft Store consultan sus propios
catálogos cuando están habilitados.

El informe se guarda en el archivo que elijas. Incluye modelo y características del PC, pendientes,
drivers con problemas, estado de seguridad y últimas diez ejecuciones. Omite nombres de usuario y
equipo, números de serie, direcciones IP y MAC, claves de producto y clave de NVD.

## Licencia

Al Día tiene licencia [MIT](LICENSE): puedes usarlo, copiarlo, cambiarlo y compartirlo libremente,
también en otros proyectos, siempre que conserves el aviso de copyright y la licencia.