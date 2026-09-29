; ---------------------------------------------------------------------------
; Arreglo de WinHTTP/TLS 1.2 para Windows 7 SP1 y Windows Server 2008 R2
;
; Sin esto, los instaladores que usan WinHTTP (p. ej. el agente de TacticalRMM)
; fallan con "WinHttp.WinHttpRequest: Error de compatibilidad del canal seguro"
; porque el sistema solo habla TLS 1.0 por defecto.
;
; Hace:
;   1. Instala KB3140245 (TLS 1.1/1.2 en WinHTTP) y KB3080079 (TLS 1.1/1.2 RDS)
;   2. WinHttp\DefaultSecureProtocols = 0xA00 (64 y 32 bits)
;   3. SCHANNEL: TLS 1.2 cliente habilitado
;   4. (opcional) importa la raiz ISRG Root X1 de Let's Encrypt
;   5. Pide reinicio
;
; Compilar:   powershell -File build.ps1
; Silencioso: winhttp-fix-win7-2008r2.exe /VERYSILENT /NORESTART   (sin raiz: /TASKS="!isrg")
; ---------------------------------------------------------------------------

#define AppName      "Arreglo TLS 1.2 para Windows 7 y 2008 R2"
#ifndef AppVersion
  #define AppVersion "1.0.0"
#endif
#define Publisher    "TSI Dominicana"

[Setup]
AppId={{B3E7A2D4-6C1F-4E58-8A93-2F5D7C9E1B60}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher={#Publisher}
VersionInfoVersion={#AppVersion}
VersionInfoCompany={#Publisher}
VersionInfoDescription={#AppName}
CreateAppDir=no
Uninstallable=no
DisableDirPage=yes
DisableProgramGroupPage=yes
PrivilegesRequired=admin
MinVersion=6.1sp1
OnlyBelowVersion=6.2
ArchitecturesInstallIn64BitMode=x64compatible
AlwaysRestart=yes
OutputDir=dist
OutputBaseFilename=winhttp-fix-win7-2008r2
Compression=lzma2/max
SolidCompression=yes
WizardStyle=classic
SetupLogging=yes

[Languages]
Name: "es"; MessagesFile: "compiler:Languages\Spanish.isl"

[Messages]
es.WelcomeLabel1=Arreglo de TLS 1.2 para Windows 7 y 2008 R2
es.WelcomeLabel2=Este asistente habilita TLS 1.1/1.2 en WinHTTP para que instaladores como el del agente de TacticalRMM puedan conectarse al servidor.%n%nInstala dos actualizaciones de Microsoft (KB3140245 y KB3080079), ajusta el registro y necesitara reiniciar el equipo.
es.FinishedHeadingLabel=Cambios aplicados
es.FinishedLabel=Reinicia el equipo para que los cambios surtan efecto y vuelve a ejecutar el instalador que fallaba.

[Tasks]
Name: "isrg"; Description: "Importar la raiz de confianza ISRG Root X1 (Let's Encrypt)"; Flags: checkedonce

[Files]
Source: "kb\kb3140245-x64.msu"; DestDir: "{tmp}"; DestName: "kb3140245.msu"; Check: Is64BitInstallMode; Flags: deleteafterinstall
Source: "kb\kb3080079-x64.msu"; DestDir: "{tmp}"; DestName: "kb3080079.msu"; Check: Is64BitInstallMode; Flags: deleteafterinstall
Source: "kb\kb3140245-x86.msu"; DestDir: "{tmp}"; DestName: "kb3140245.msu"; Check: not Is64BitInstallMode; Flags: deleteafterinstall
Source: "kb\kb3080079-x86.msu"; DestDir: "{tmp}"; DestName: "kb3080079.msu"; Check: not Is64BitInstallMode; Flags: deleteafterinstall
Source: "kb\isrgrootx1.der"; DestDir: "{tmp}"; Tasks: isrg; Flags: deleteafterinstall

[Registry]
; DefaultSecureProtocols = TLS 1.1 (0x200) + TLS 1.2 (0x800)
Root: HKLM64; Subkey: "SOFTWARE\Microsoft\Windows\CurrentVersion\Internet Settings\WinHttp"; ValueType: dword; ValueName: "DefaultSecureProtocols"; ValueData: "$00000A00"; Check: Is64BitInstallMode
Root: HKLM32; Subkey: "SOFTWARE\Microsoft\Windows\CurrentVersion\Internet Settings\WinHttp"; ValueType: dword; ValueName: "DefaultSecureProtocols"; ValueData: "$00000A00"
Root: HKLM64; Subkey: "SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.2\Client"; ValueType: dword; ValueName: "Enabled"; ValueData: "1"; Check: Is64BitInstallMode
Root: HKLM64; Subkey: "SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.2\Client"; ValueType: dword; ValueName: "DisabledByDefault"; ValueData: "0"; Check: Is64BitInstallMode
Root: HKLM32; Subkey: "SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.2\Client"; ValueType: dword; ValueName: "Enabled"; ValueData: "1"; Check: not Is64BitInstallMode
Root: HKLM32; Subkey: "SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.2\Client"; ValueType: dword; ValueName: "DisabledByDefault"; ValueData: "0"; Check: not Is64BitInstallMode

[Code]
// Instala un .msu con wusa. 0 = ok, 3010 = ok pendiente reinicio,
// 2359302 (0x240006) = ya instalado. Todo lo demas es fallo.
procedure InstallMsu(const Name, Kb: String);
var
  Code: Integer;
  Wusa: String;
begin
  WizardForm.StatusLabel.Caption := 'Instalando ' + Kb + ' (puede tardar varios minutos)...';
  WizardForm.ProgressGauge.Style := npbstMarquee;
  // En modo 64 bits Inno desactiva la redireccion, asi que {sys} es el wusa de 64 bits
  Wusa := ExpandConstant('{sys}\wusa.exe');
  if not Exec(Wusa, '"' + ExpandConstant('{tmp}\' + Name) + '" /quiet /norestart',
              '', SW_HIDE, ewWaitUntilTerminated, Code) then
    RaiseException('No se pudo ejecutar wusa.exe para ' + Kb);
  Log(Kb + ': wusa devolvio ' + IntToStr(Code));
  if (Code <> 0) and (Code <> 3010) and (Code <> 2359302) then
    RaiseException(Kb + ' fallo (wusa devolvio ' + IntToStr(Code) + '). Revisa el log de Setup.');
end;

procedure CurStepChanged(CurStep: TSetupStep);
var
  Code: Integer;
begin
  if CurStep = ssPostInstall then
  begin
    InstallMsu('kb3140245.msu', 'KB3140245');
    InstallMsu('kb3080079.msu', 'KB3080079');
    if WizardIsTaskSelected('isrg') then
    begin
      WizardForm.StatusLabel.Caption := 'Importando ISRG Root X1...';
      if not Exec(ExpandConstant('{sys}\certutil.exe'),
                  '-addstore -f Root "' + ExpandConstant('{tmp}\isrgrootx1.der') + '"',
                  '', SW_HIDE, ewWaitUntilTerminated, Code) or (Code <> 0) then
        RaiseException('No se pudo importar ISRG Root X1 (certutil devolvio ' + IntToStr(Code) + ').');
    end;
  end;
end;
