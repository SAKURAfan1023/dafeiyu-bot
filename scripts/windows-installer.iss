; Per-user installer. QQ data is outside {app} and is never removed by uninstall.
#ifndef BundleDir
  #error BundleDir is required
#endif
#ifndef OutputDir
  #error OutputDir is required
#endif
#ifndef AppVersion
  #error AppVersion is required
#endif

[Setup]
AppId=org.dafeiyu.qq
AppName=大肥鱼 QQ
AppVersion={#AppVersion}
VersionInfoVersion=0.3.0.3
AppPublisher=SAKURAfan1023
AppPublisherURL=https://github.com/SAKURAfan1023/dafeiyu-bot
DefaultDirName={localappdata}\Programs\DaFeiYuQQ
DefaultGroupName=大肥鱼 QQ
PrivilegesRequired=lowest
ArchitecturesAllowed=x64os
ArchitecturesInstallIn64BitMode=x64os
MinVersion=10.0
DisableProgramGroupPage=yes
OutputDir={#OutputDir}
OutputBaseFilename=DaFeiYu-{#AppVersion}-windows-x64-setup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
CloseApplications=no
RestartApplications=no
UninstallDisplayIcon={app}\DaFeiYu.exe
InfoBeforeFile={#BundleDir}\README.txt

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; Flags: unchecked

[Files]
Source: "{#BundleDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{userprograms}\大肥鱼 QQ"; Filename: "{app}\DaFeiYu.exe"; WorkingDir: "{app}"
Name: "{userprograms}\打开内置 NapCat"; Filename: "{app}\DaFeiYu.exe"; Parameters: "--napcat"; WorkingDir: "{app}"
Name: "{userdesktop}\大肥鱼 QQ"; Filename: "{app}\DaFeiYu.exe"; WorkingDir: "{app}"; Tasks: desktopicon

[Run]
Filename: "{app}\DaFeiYu.exe"; Description: "Open DaFeiYu QQ"; Flags: nowait postinstall skipifsilent unchecked
