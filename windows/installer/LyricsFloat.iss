; Keep AppId and install mode stable across releases so upgrades reuse the install.
#ifndef AppVersion
  #define AppVersion "1.0.0"
#endif

[Setup]
AppId={{9248678E-8577-4B21-968C-84032EB63782}
AppName=LyricsFloat
AppVersion={#AppVersion}
AppPublisher=LyricsFloat
AppPublisherURL=https://github.com/MrRice-TW/LyricsFloat
DefaultDirName={localappdata}\Programs\LyricsFloat
DefaultGroupName=LyricsFloat
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
UsePreviousAppDir=yes
DisableProgramGroupPage=yes
OutputDir=..\..\dist
OutputBaseFilename=LyricsFloat-Windows-x64-Setup
SetupIconFile=..\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\lyrics_float.exe
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
CloseApplications=yes
RestartApplications=no

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "..\..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\LyricsFloat"; Filename: "{app}\lyrics_float.exe"; WorkingDir: "{app}"
Name: "{autodesktop}\LyricsFloat"; Filename: "{app}\lyrics_float.exe"; WorkingDir: "{app}"; Tasks: desktopicon

[Run]
Filename: "{app}\lyrics_float.exe"; Description: "{cm:LaunchProgram,LyricsFloat}"; Flags: nowait postinstall skipifsilent

; User data lives in LocalAppData\LyricsFloat, outside the installation directory.
; Do not remove it during upgrades or uninstall.
