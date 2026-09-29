# windows2008r2-winhttp-fix

Instalador (Inno Setup) que habilita **TLS 1.1/1.2 en WinHTTP** en Windows Server 2008 R2 y
Windows 7 SP1, para que instaladores modernos puedan conectarse a servidores con HTTPS actual.

## El problema

Al instalar el agente de TacticalRMM (o cualquier instalador que use `WinHttp.WinHttpRequest`)
en Windows Server 2008 R2 sale:

```
Usuario o contraseña incorrectos.
No se pudo contactar el servidor. WinHttp.WinHttpRequest: Error de compatibilidad del canal seguro
```

El "usuario o contraseña incorrectos" es solo el mensaje genérico del instalador. La causa real es
que 2008 R2 / Windows 7 solo negocian **TLS 1.0** por defecto en WinHTTP, y el servidor exige
TLS 1.2.

## Qué hace

1. Instala **KB3140245** (TLS 1.1/1.2 en WinHTTP) y **KB3080079** (TLS 1.1/1.2 para RDS), en la
   variante x86 o x64 que corresponda.
2. Pone `DefaultSecureProtocols = 0x00000A00` (TLS 1.1 + 1.2) en
   `HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Internet Settings\WinHttp` y en su
   equivalente `Wow6432Node`. Es lo que hace el "Easy Fix 51044" de Microsoft.
3. Habilita TLS 1.2 de cliente en SCHANNEL (`Enabled=1`, `DisabledByDefault=0`).
4. Opcional (marcado por defecto): importa la raíz **ISRG Root X1** de Let's Encrypt, que 2008 R2
   no trae. Sin ella, aun con TLS 1.2 fallan los certificados de Let's Encrypt.
5. Pide reinicio. Después de reiniciar, se vuelve a correr el instalador que fallaba.

Solo corre en Windows 7 SP1 / 2008 R2 (versión 6.1). En Windows más nuevo no arranca porque no
hace falta.

## Uso

Ejecutar `winhttp-fix-win2008r2.exe` como administrador y reiniciar al terminar.

Silencioso (para scripts o el propio RMM):

```
winhttp-fix-win2008r2.exe /VERYSILENT /NORESTART
winhttp-fix-win2008r2.exe /VERYSILENT /NORESTART /TASKS="!isrg"   # sin importar la raíz ISRG
```

El log queda en `%TEMP%\Setup Log <fecha>.txt` (`SetupLogging=yes`); ahí se ve el código de
retorno de cada `wusa`.

## Compilar

Requiere Inno Setup 6 y PowerShell.

```
powershell -ExecutionPolicy Bypass -File build.ps1
powershell -ExecutionPolicy Bypass -File build.ps1 -Version 1.1.0
```

`build.ps1` llama a `tools\download-kb.ps1` si faltan los archivos: baja los cuatro `.msu` del
Catálogo de Microsoft Update a `kb\` (con nombre estable `kbNNNNNNN-x64.msu`), baja
`isrgrootx1.der` y verifica su huella SHA-256. El resultado queda en `dist\`.

## Qué NO está en el repo

Los `.msu` y el `.exe` compilado están en `.gitignore`: son binarios de Microsoft y no se
redistribuyen desde aquí. Se bajan de la fuente oficial al compilar. `kb\SHA256SUMS.txt` guarda las
huellas de lo que se usó, para comprobar que el catálogo entrega lo mismo.

## Alternativa manual

`tools\habilitar-tls12-manual.ps1` hace lo mismo sin Inno (compatible con PowerShell 2.0), con
`-RutaKB` para una carpeta de `.msu` y `-CertRaiz` para una raíz.

## Limitaciones

- **No probado todavía en una máquina 2008 R2 real.** Compila, pero falta validar el ciclo
  completo: instalar, reiniciar y correr el instalador de Tactical.
- Arreglar TLS no garantiza que el agente corra. Las versiones recientes del agente de Tactical
  están escritas en Go, y Go dejó de soportar Windows 7/2008 R2 desde la 1.21. Si el agente no
  arranca aun con TLS bien, es una limitación del binario, no de este arreglo.
- 2008 R2 está fuera de soporte desde enero de 2020. Esto es un paliativo.
- Si `wusa` falla con un `.msu`, revisar que el equipo tenga SP1 y actualizaciones al día; los
  paquetes firmados solo con SHA-2 requieren KB4474419 en 2008 R2.

## Fuentes

- [Update to enable TLS 1.1 and TLS 1.2 as default secure protocols in WinHTTP](https://support.microsoft.com/en-us/topic/update-to-enable-tls-1-1-and-tls-1-2-as-default-secure-protocols-in-winhttp-in-windows-c4bd73d2-31d7-761e-0178-11268bb10392)
- [Update to add RDS support for TLS 1.1 and TLS 1.2 in Windows 7 or Server 2008 R2](https://support.microsoft.com/en-us/topic/update-to-add-rds-support-for-tls-1-1-and-tls-1-2-in-windows-7-or-windows-server-2008-r2-8aff6954-a80d-411c-c75c-6aeaaab4f570)
