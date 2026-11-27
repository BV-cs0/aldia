# Al Día

[![PowerShell Gallery](https://img.shields.io/powershellgallery/v/Aldia)](https://www.powershellgallery.com/packages/Aldia)
[![Licencia: MIT](https://img.shields.io/badge/licencia-MIT-green)](LICENSE)
[![Pruebas](https://github.com/BV-cs0/aldia/actions/workflows/pruebas.yml/badge.svg)](https://github.com/BV-cs0/aldia/actions/workflows/pruebas.yml)

Al Día mantiene Windows al día desde una sola ventana en español:

- Actualiza las aplicaciones de winget y Microsoft Store, Windows Update, los drivers que ofrece Windows Update y los paquetes globales de npm. Si Dell Command Update está instalado, también aplica sus actualizaciones.
- Avisa de programas instalados con fallos de seguridad conocidos, ordenados por riesgo.
- Revisa la salud del PC: discos, batería, memoria y la causa de los pantallazos azules.
- Detecta dispositivos con problemas, recomienda las herramientas oficiales del fabricante y avisa cuando hay que reiniciar.

## Requisitos e instalación

Windows 10 22H2 u 11 con Windows PowerShell 5.1, que ya viene incluido. PowerShell 7 también puede ejecutar las órdenes. Las aplicaciones necesitan winget (Instalador de aplicaciones) y la fuente npm necesita npm. Las fuentes que descargan actualizaciones necesitan conexión.

### Desde la PowerShell Gallery (lo más fácil)

Abre Windows PowerShell y escribe:

```powershell
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
Install-Module Aldia -Scope CurrentUser
aldia
```

La primera línea solo hace falta una vez: permite que Windows ejecute módulos de PowerShell. `aldia` abre la ventana. `aldia diagnostico`, `aldia revisar` y el resto de órdenes funcionan igual que `.\aldia.ps1`. Para dejar la tarea automática, ejecuta `aldia instalar` en un PowerShell abierto como administrador.

### Desde GitHub

Desde Windows PowerShell como administrador:

```powershell
git clone https://github.com/BV-cs0/aldia.git
cd aldia
.\aldia.ps1 instalar
```

Sin Git, descarga el ZIP de la última [Release](https://github.com/BV-cs0/aldia/releases/latest), descomprímelo y haz doble clic en **Abrir Al Día.cmd** o **Instalar Al Día.cmd**.

La instalación copia el programa y la configuración a Program Files, para que la tarea elevada solo ejecute archivos que únicamente pueden cambiar los administradores. La tarea se ejecuta con el usuario que la instaló, durante su sesión. Se dispara a la hora configurada, se repite cada hora durante doce horas y vuelve a intentarlo quince minutos después de iniciar sesión.

### En el PC de otra persona

Copia la carpeta completa y abre **Abrir Al Día.cmd** para revisar el PC desde la carpeta o desde un USB. Para tener el acceso directo y las revisiones automáticas, ejecuta **Instalar Al Día.cmd** y acepta la solicitud de permisos de Windows. Si la cuenta es estándar, Windows pedirá la contraseña de un administrador.

Si falta el Instalador de aplicaciones de Microsoft, pulsa **Conseguirlo** en la ventana o descárgalo desde [Microsoft](https://aka.ms/getwinget). Mientras tanto puedes revisar Windows y los drivers. Office y Microsoft Store se activan en **Herramientas** o en las claves `office` y `store` de `fuentes` en la configuración.

## La ventana

Abre **Al Día** desde el menú Inicio, el escritorio o con `aldia` (o `.\aldia.ps1 gui`).

- **Escáner** agrupa lo pendiente, te deja elegir qué instalar y muestra los fallos de seguridad conocidos.
- **Salud** muestra los diagnósticos y pide confirmación antes de cualquier acción que cambie el sistema.
- **Diagnóstico** revisa los discos, la batería, la memoria y los avisos de estabilidad de los últimos 30 días.
- **Historial** muestra el resultado de cada ejecución.
- **Herramientas** reúne las recomendaciones del fabricante, el inventario, la configuración de la actualización automática y **Guardar informe**.

Para explorar la ventana y simular una instalación sin consultar el equipo ni pedir permisos de administrador, usa `.\aldia.ps1 gui --demo`.

### Diagnóstico del equipo

Abre **Diagnóstico** o ejecuta `.\aldia.ps1 diagnostico`. Windows puede pedir permiso de administrador en **Ver detalles** para mostrar la temperatura y el desgaste de los discos.

Para medir la velocidad de un disco, pulsa **Probar velocidad** junto a la unidad o ejecuta `.\aldia.ps1 diagnostico --velocidad --unidad C`. La prueba necesita 3 GB libres y borra su archivo temporal al terminar. En un portátil con poca batería, conecta antes el cargador.

### Informe

Pulsa **Guardar informe** en Herramientas o ejecuta `.\aldia.ps1 informe --ruta "C:\ruta\Informe Al Día.html"`. Si no eliges una ruta, Al Día sugiere el Escritorio. El informe se abre sin internet y se puede imprimir desde el navegador.

## Órdenes

Ejecuta estas órdenes con el script de la copia instalada, desde el repositorio o con `aldia` si lo instalaste desde la Gallery.

| Orden | Acción |
| --- | --- |
| `.\aldia.ps1 revisar` | Consulta las actualizaciones y las incidencias de dispositivos. |
| `.\aldia.ps1 actualizar` | Actualiza todas las fuentes habilitadas. |
| `.\aldia.ps1 actualizar --simular` | Consulta las fuentes y muestra las operaciones previstas y el total, sin instalar. |
| `.\aldia.ps1 actualizar --solo apps,drivers` | Limita la ejecución a esas fuentes habilitadas. |
| `.\aldia.ps1 actualizar --programado` | Escribe en el log, comprueba la batería y espera 20 horas desde la última ejecución completada (código 0 o 1). |
| `.\aldia.ps1 actualizar --programado --forzar` | Omite el límite de 20 horas. |
| `.\aldia.ps1 drivers` | Muestra incidencias, ofertas de Windows Update y recomendaciones del fabricante. |
| `.\aldia.ps1 inventario` | Muestra los programas de instaladores clásicos (ARP), salvo los juegos gestionados por Steam. |
| `.\aldia.ps1 vulnerabilidades` | Consulta fallos conocidos en las versiones instaladas y los ordena por riesgo. |
| `.\aldia.ps1 salud` | Muestra doce comprobaciones de solo lectura, sin pedir elevación. |
| `.\aldia.ps1 diagnostico` | Revisa discos, batería, memoria y pantallazos azules. |
| `.\aldia.ps1 informe` | Guarda el informe del equipo en HTML. |
| `.\aldia.ps1 adoptar` | Busca paquetes de winget para programas sin actualizador conocido. |
| `.\aldia.ps1 adoptar --id OpenJS.NodeJS.24` | Instala el paquete indicado tras pedir confirmación. Requiere administración. |
| `.\aldia.ps1 deshacer --id Git.Git` | Vuelve a la versión anterior de la última actualización completada, si sigue disponible. Requiere administración. |
| `.\aldia.ps1 fijados` | Muestra los elementos que el actualizador omite tras deshacer. Desde Herramientas puedes dejar de fijarlos. |
| `.\aldia.ps1 historial -n 10` | Resume las diez últimas ejecuciones. |
| `.\aldia.ps1 config` | Abre la configuración instalada en el Bloc de notas elevado. |
| `.\aldia.ps1 desinstalar` | Quita la tarea y el programa. Añade `--todo` para borrar también los registros. |

Los códigos de salida son 0 si todo fue bien, 1 si falló alguna actualización, 2 si falló la herramienta y 3 si se omitió la ejecución.

## Configuración y registros

Edita `config.json` con la orden `config`. `config.default.json` incluye todos los valores predeterminados:

- `fuentes` habilita o deshabilita cada fuente, y `excluir` deja fuera Id de winget y nombres de npm.
- También puedes activar las versiones desconocidas y ajustar el tiempo límite por paquete.
- Las opciones de drivers permiten excluir clases y repetir la detección de dispositivos.
- Puedes elegir si se crean puntos de restauración, la batería mínima, los días que se guardan los registros y cuándo se muestran notificaciones (`siempre`, `solo-cambios`, `solo-errores` o `nunca`).
- Después de cambiar `horaDiaria`, ejecuta `instalar` de nuevo para aplicar la hora a la tarea.

La tarea comprueba las vulnerabilidades después de actualizar y añade los casos graves a la notificación. Esta comprobación se configura con `vulnerabilidades.activado`. La clave de NVD es opcional y va en `vulnerabilidades.nvdApiKey`. La relación con los productos de NVD se lee de `datos\cpe.json`, y la caché se guarda en `%ProgramData%\Aldia\cache`. La orden `vulnerabilidades` consulta a mano aunque la comprobación automática esté desactivada.

Los logs están en `%ProgramData%\Aldia\logs` y el historial en `%ProgramData%\Aldia\historial.jsonl`. Cada actualización de winget tiene además su propio log.

## Actualizaciones de Al Día

Al Día se mantiene al día a sí mismo, sin ventanas ni preguntas. Lo que hace depende de cómo lo tengas:

| Cómo lo tienes | Qué hace |
| --- | --- |
| Instalado (`instalar`, en Program Files) | Después de cada ejecución programada mira la última [Release](https://github.com/BV-cs0/aldia/releases), descarga el paquete, comprueba su SHA-256 y lo aplica. La versión nueva se usa en la siguiente ejecución. Queda anotado en el log. |
| Carpeta suelta o USB (**Abrir Al Día.cmd**) | Mientras la ventana está abierta, descarga y verifica la versión nueva en segundo plano, y al cerrarla la aplica en la misma carpeta. Tu `config.json` no se toca. |
| PowerShell Gallery (`Install-Module`) | No se reinstala solo: avisa una vez, en una línea, de que hay versión nueva y de que se actualiza con `Update-Module Aldia`. Para no ver el aviso, define la variable de entorno `ALDIA_SIN_AVISO_VERSION=1`. |
| Clon con Git | Nada: se actualiza con `git pull`. |

Solo descarga de `github.com/BV-cs0/aldia` por HTTPS, y descarta cualquier paquete cuyo SHA-256 no coincida con el publicado. Si no hay conexión o GitHub no responde, Al Día funciona igual. La versión que tienes aparece en el título de la ventana, y los cambios de cada versión están en las [Releases](https://github.com/BV-cs0/aldia/releases) y en `ReleaseNotes` de `Aldia.psd1`.

## Privacidad

Para revisar fallos de seguridad, Al Día consulta NVD y OSV con los nombres o identificadores de los programas y sus versiones. Envía a EPSS los identificadores de los fallos (CVE) y descarga de CISA la lista de fallos que se están aprovechando. La clave opcional de NVD solo se envía a NVD. Al Día no pide cuentas ni envía telemetría. Para sus propias actualizaciones solo consulta las Releases de GitHub o, si lo instalaste desde allí, la PowerShell Gallery. Windows Update, winget, npm y Microsoft Store consultan sus propios catálogos cuando están habilitados.

El informe se guarda en el archivo que elijas. Incluye el modelo y las características del PC, lo pendiente, los drivers con problemas, el estado de seguridad y las diez últimas ejecuciones. Omite nombres de usuario y de equipo, números de serie, direcciones IP y MAC, claves de producto y la clave de NVD.

## Desarrollo

Pruebas: en Windows PowerShell 5.1 con Pester 3.4, ejecuta `Invoke-Pester .\tests` desde la carpeta del proyecto.

Publicar una versión: sube `ModuleVersion` y `ReleaseNotes` en `Aldia.psd1` y crea la etiqueta `vX.Y.Z`. El flujo de GitHub crea la Release con `Aldia-X.Y.Z.zip` y su `.sha256`. Los genera `publicar\Crear-Paquete.ps1`, solo con los archivos de `FileList`. `publicar\Publicar-Gallery.ps1` sube la misma versión a la PowerShell Gallery.

## Licencia

Al Día tiene licencia [MIT](LICENSE): puedes usarlo, copiarlo, cambiarlo y compartirlo libremente, también en otros proyectos, siempre que conserves el aviso de copyright y la licencia.
