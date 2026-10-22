; Inno Setup script for the Windows installer (used by the GitHub workflow).
#define AppName "TuitMate"
; The release workflow passes the pubspec.yaml version with /DAppVersion=x.y.z.
#ifndef AppVersion
  #define AppVersion "1.0.0"
#endif

[Setup]
AppId={{6F1C3B0E-6A54-4D1E-9A3E-2F73C8A1B7D4}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher=TuitMate (personal)
DefaultDirName={localappdata}\Programs\{#AppName}
DefaultGroupName={#AppName}
PrivilegesRequired=lowest
OutputBaseFilename=TuitMate-Setup
SetupIconFile=runner\resources\app_icon.ico
UninstallDisplayIcon={app}\TuitMate.exe
Compression=lzma2
SolidCompression=yes
ArchitecturesInstallIn64BitMode=x64compatible
WizardStyle=modern

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"
Name: "startup"; Description: "Start with Windows (for notifications)"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\TuitMate.exe"; AppUserModelID: "Uz.Personal.TuitMate"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\TuitMate.exe"; Tasks: desktopicon; AppUserModelID: "Uz.Personal.TuitMate"
Name: "{userstartup}\{#AppName}"; Filename: "{app}\TuitMate.exe"; Tasks: startup

[Run]
Filename: "{app}\TuitMate.exe"; Description: "{cm:LaunchProgram,{#AppName}}"; Flags: nowait postinstall skipifsilent
