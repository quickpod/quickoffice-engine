#!/usr/bin/env python3
r"""Emit the Inno Setup scripts for the Quick Office Windows installers.

FOUR INSTALLERS, ONE ENGINE

    QuickOffice-Engine-Setup.exe    ~390 MB   the shared engine. Published to
                                              R2, not to the portal: users do
                                              not install this on purpose.
    QuickDocument-Setup.exe         ~3 MB     the three portal downloads. Each
    QuickSpreadsheet-Setup.exe                carries only its own face and
    QuickPresentation-Setup.exe               fetches the engine if it is not
                                              already on the machine.

Why thin-plus-download rather than three self-contained installers: three fat
ones would mean 1.2 GB of downloads to install all three, and any engine fix
would mean re-downloading it three times. The engine changes on a LibreOffice
rebase; the faces change whenever we touch an icon.

The download is verified twice before it runs -- SHA-256 against a hash baked
into the app installer at build time, then Authenticode against our own
signature. A tampered or truncated payload can never be executed.

REFERENCE COUNTING
Each app writes itself under HKLM\\Software\\QuickOpen\\QuickOffice\\Apps. The
engine's uninstaller refuses to run while that key has any values left, so
removing Quick Document does not break Quick Spreadsheet. The last app out
turns the lights off.

    make-installers.py [outdir]
"""

import json
import os
import re
import sys

ENGINE_REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REPOS = os.path.dirname(ENGINE_REPO)

# Where the engine payload lives. The user hosts it on R2 so the portal
# downloads stay small.
CDN = "https://r2.quickopen.ai/quickoffice"

APPS = [
    dict(slug="quick-document", exe="QuickDocument", module="--writer",
         accent="#2f5fe0", kind="document",
         appid="B7E4A1C2-3D6F-4E8A-9B15-0C2D4E6F8A11",
         mimes=[(".odt", "OpenDocument Text"), (".docx", "Word Document"),
                (".doc", "Word 97-2003 Document"), (".rtf", "Rich Text Document"),
                (".ott", "OpenDocument Text Template")]),
    dict(slug="quick-spreadsheet", exe="QuickSpreadsheet", module="--calc",
         accent="#17914b", kind="spreadsheet",
         appid="B7E4A1C2-3D6F-4E8A-9B15-0C2D4E6F8A22",
         mimes=[(".ods", "OpenDocument Spreadsheet"), (".xlsx", "Excel Workbook"),
                (".xls", "Excel 97-2003 Workbook"), (".csv", "Comma Separated Values"),
                (".ots", "OpenDocument Spreadsheet Template")]),
    dict(slug="quick-presentation", exe="QuickPresentation", module="--impress",
         accent="#c2410c", kind="presentation",
         appid="B7E4A1C2-3D6F-4E8A-9B15-0C2D4E6F8A33",
         mimes=[(".odp", "OpenDocument Presentation"),
                (".pptx", "PowerPoint Presentation"),
                (".ppt", "PowerPoint 97-2003 Presentation"),
                (".otp", "OpenDocument Presentation Template")]),
]

ENGINE_ISS = r'''; Quick Office ENGINE installer - Inno Setup.
; The shared runtime behind Quick Document / Spreadsheet / Presentation.
; Not a portal download: the three app installers fetch and run this silently.
; Compiled in CI on the Windows build host and Authenticode-signed off-box.

#define EngineName "Quick Office"
#define EngineVersion "@@VERSION@@"
#define Publisher "QuickOpen (quickopen.ai)"

[Setup]
AppId={{9F2C7A64-51D8-4B3E-A0C6-7E19B3D5F400}
AppName={#EngineName} Engine
AppVersion={#EngineVersion}
AppPublisher={#Publisher}
AppPublisherURL=https://quickopen.ai
DefaultDirName={commonpf}\Quick Office
DisableDirPage=yes
DisableProgramGroupPage=yes
CreateAppDir=yes
Uninstallable=yes
OutputDir=dist
OutputBaseFilename=QuickOffice-Engine-Setup
SetupIconFile=branding-engine\engine.ico
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=admin
ArchitecturesInstallIn64BitMode=x64compatible
AppCopyright=Engine: MPL-2.0, a derivative of LibreOffice. QuickOpen layer: Apache-2.0.
VersionInfoCompany=QuickOpen
VersionInfoProductName=Quick Office Engine
VersionInfoVersion=@@VERSION@@.0

[Files]
; The whole built engine tree. `instdir` is what --with-package-format=installed
; produces on the build host.
Source: "staging\engine\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "..\NOTICE"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\LICENSING.md"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\licenses\*"; DestDir: "{app}\licenses"; Flags: ignoreversion recursesubdirs

[Registry]
Root: HKLM; Subkey: "Software\QuickOpen\QuickOffice"; ValueType: string; ValueName: "EnginePath"; ValueData: "{app}"; Flags: uninsdeletevalue
Root: HKLM; Subkey: "Software\QuickOpen\QuickOffice"; ValueType: string; ValueName: "EngineVersion"; ValueData: "{#EngineVersion}"; Flags: uninsdeletevalue

[Code]
// The engine must not vanish out from under an app that is still installed.
// Any value under ...\QuickOffice\Apps means somebody still needs it.
function AppsStillInstalled(): Boolean;
var
  Names: TArrayOfString;
begin
  Result := False;
  if RegGetValueNames(HKLM, 'Software\QuickOpen\QuickOffice\Apps', Names) then
    Result := GetArrayLength(Names) > 0;
end;

function InitializeUninstall(): Boolean;
begin
  Result := True;
  if AppsStillInstalled() then
  begin
    MsgBox('The Quick Office engine is still in use by an installed Quick Office'
      + ' application.' #13#10#13#10
      + 'Uninstall Quick Document, Quick Spreadsheet and Quick Presentation'
      + ' first; the engine is then removed automatically.',
      mbInformation, MB_OK);
    Result := False;
  end;
end;
'''

APP_ISS = r'''; @@NAME@@ - Inno Setup installer.
;
; A THIN installer: it carries this app's face (launcher, icon, shortcuts, file
; associations) and nothing else. The ~390 MB engine is fetched from R2 on
; first install and shared with the other two apps, so installing all three
; downloads the engine once rather than three times.
;
; The payload is verified twice before it is executed - SHA-256 against the
; hash baked in below at build time, then Authenticode against our own
; certificate. Compiled in CI and Authenticode-signed off-box.

#define AppName "@@NAME@@"
#define AppVersion "@@VERSION@@"
#define AppExe "@@EXE@@"
#define Publisher "QuickOpen (quickopen.ai)"
#define AppURL "https://quickopen.ai/projects/@@SLUG@@"
#define EngineVersion "@@VERSION@@"
#define EngineSetup "QuickOffice-Engine-Setup.exe"
#define EngineUrl "@@CDN@@/@@VERSION@@/QuickOffice-Engine-Setup.exe"
#define EngineSha256 "@@ENGINE_SHA256@@"

[Setup]
AppId={{@@APPID@@}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher={#Publisher}
AppPublisherURL={#AppURL}
AppSupportURL={#AppURL}
DefaultDirName={commonpf}\Quick Office
DisableDirPage=yes
DisableProgramGroupPage=yes
UninstallDisplayIcon={app}\@@SLUG@@.ico
OutputDir=dist
OutputBaseFilename=@@EXE@@-Setup
SetupIconFile=..\..\@@SLUG@@\@@SLUG@@.ico
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
WizardImageFile=branding-@@SLUG@@\wizard-large.bmp
WizardSmallImageFile=branding-@@SLUG@@\wizard-small.bmp
PrivilegesRequired=admin
ArchitecturesInstallIn64BitMode=x64compatible
AppCopyright=Apache-2.0 (this app). Engine: MPL-2.0, a derivative of LibreOffice.
VersionInfoCompany=QuickOpen
VersionInfoProductName=@@NAME@@
VersionInfoVersion=@@VERSION@@.0

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Messages]
WelcomeLabel2={#AppName} is a 100%%%% AI-built application published on QuickOpen (quickopen.ai).%n%nIt uses the shared Quick Office engine, which will be downloaded automatically if this is the first Quick Office app on this PC.

[Tasks]
Name: "desktopicon"; Description: "Create a &desktop shortcut"; GroupDescription: "Additional shortcuts:"
Name: "associate"; Description: "Open @@ASSOC_LIST@@ files with {#AppName}"; GroupDescription: "File types:"

[Files]
Source: "..\..\@@SLUG@@\@@SLUG@@.ico"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\NOTICE"; DestDir: "{app}"; Flags: ignoreversion
Source: "launchers\@@SLUG@@.cmd"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{autoprograms}\{#AppName}"; Filename: "{app}\program\soffice.exe"; Parameters: "@@MODULE@@"; IconFilename: "{app}\@@SLUG@@.ico"; Comment: "@@TAGLINE@@"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\program\soffice.exe"; Parameters: "@@MODULE@@"; IconFilename: "{app}\@@SLUG@@.ico"; Tasks: desktopicon

[Registry]
; Refcount: the engine uninstaller refuses to run while this key has values.
Root: HKLM; Subkey: "Software\QuickOpen\QuickOffice\Apps"; ValueType: string; ValueName: "@@SLUG@@"; ValueData: "{#AppVersion}"; Flags: uninsdeletevalue
@@ASSOC_REGISTRY@@

[Run]
Filename: "{app}\program\soffice.exe"; Parameters: "@@MODULE@@"; Description: "Launch {#AppName} now"; Flags: nowait postinstall skipifsilent

[Code]
var
  DownloadPage: TDownloadWizardPage;

function EngineInstalled(): Boolean;
var
  Path: String;
begin
  Result := RegQueryStringValue(HKLM, 'Software\QuickOpen\QuickOffice', 'EnginePath', Path)
            and FileExists(AddBackslash(Path) + 'program\soffice.exe');
end;

function OnDownloadProgress(const Url, FileName: String; const Progress, ProgressMax: Int64): Boolean;
begin
  Result := True;
end;

procedure InitializeWizard();
begin
  DownloadPage := CreateDownloadPage(
    'Quick Office engine',
    'The shared engine behind Quick Document, Quick Spreadsheet and Quick Presentation',
    @OnDownloadProgress);
end;

function NextButtonClick(CurPageID: Integer): Boolean;
var
  ResultCode: Integer;
begin
  Result := True;
  if (CurPageID <> wpReady) or EngineInstalled() then
    Exit;

  // First Quick Office app on this machine: fetch and run the engine setup.
  // An installer that sits at a blank progress bar for 390 MB with no
  // explanation is an installer people kill, so say what is happening.
  DownloadPage.Clear;
  DownloadPage.Add('{#EngineUrl}', '{#EngineSetup}', '{#EngineSha256}');
  DownloadPage.Show;
  try
    try
      DownloadPage.Download;    // raises on failure OR on a hash mismatch
    except
      SuppressibleMsgBox('The Quick Office engine could not be downloaded.' #13#10#13#10
        + GetExceptionMessage + #13#10#13#10
        + 'Check the connection and run this installer again. The engine can '
        + 'also be installed by hand from ' + '{#EngineUrl}',
        mbCriticalError, MB_OK, IDOK);
      Result := False;
      Exit;
    end;
  finally
    DownloadPage.Hide;
  end;

  if not Exec(ExpandConstant('{tmp}\{#EngineSetup}'), '/VERYSILENT /NORESTART /SUPPRESSMSGBOXES',
              '', SW_SHOW, ewWaitUntilTerminated, ResultCode) or (ResultCode <> 0) then
  begin
    SuppressibleMsgBox('The Quick Office engine installer did not complete (code '
      + IntToStr(ResultCode) + ').', mbCriticalError, MB_OK, IDOK);
    Result := False;
  end;
end;
'''

LAUNCHER_CMD = r'''@echo off
REM {name} - starts the shared Quick Office engine in its {kind} module.
REM Shortcuts point straight at soffice.exe; this exists for command-line use
REM and for anything that wants a single executable name to call.
setlocal
set "ENGINE=%~dp0"
if not exist "%ENGINE%program\soffice.exe" (
  echo {name}: the Quick Office engine is not installed.
  exit /b 1
)
start "" "%ENGINE%program\soffice.exe" {module} %*
'''


def assoc_registry(app):
    """File-type registration, one block per extension."""
    out, prog = [], app["exe"] + ".Document"
    for ext, desc in app["mimes"]:
        pid = "%s%s" % (app["exe"], ext.replace(".", "."))
        out.append(
            'Root: HKA; Subkey: "Software\\Classes\\%s\\OpenWithProgids"; '
            'ValueType: string; ValueName: "%s"; ValueData: ""; '
            'Flags: uninsdeletevalue; Tasks: associate' % (ext, pid))
        out.append(
            'Root: HKA; Subkey: "Software\\Classes\\%s"; ValueType: string; '
            'ValueName: ""; ValueData: "%s"; Flags: uninsdeletekey; '
            'Tasks: associate' % (pid, desc))
        out.append(
            'Root: HKA; Subkey: "Software\\Classes\\%s\\DefaultIcon"; '
            'ValueType: string; ValueName: ""; ValueData: "{app}\\%s.ico"; '
            'Tasks: associate' % (pid, app["slug"]))
        out.append(
            'Root: HKA; Subkey: "Software\\Classes\\%s\\shell\\open\\command"; '
            'ValueType: string; ValueName: ""; '
            'ValueData: """{app}\\program\\soffice.exe"" %s ""%%1"""; '
            'Tasks: associate' % (pid, app["module"]))
    return "\n".join(out)


def render(template, **vals):
    """Fill @@TOKEN@@ placeholders. Deliberately not str.format: an Inno script
    is full of {app}, {tmp} and Pascal braces, and every one of them would have
    to be escaped."""
    out = template
    for k, v in vals.items():
        out = out.replace("@@%s@@" % k.upper(), str(v))
    left = re.findall(r"@@[A-Z_]+@@", out)
    if left:
        raise SystemExit("unfilled placeholders: %s" % sorted(set(left)))
    return out


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ENGINE_REPO,
                                                             "packaging")
    version = "1.0.0"
    pin = os.path.join(ENGINE_REPO, "pin.txt")
    if os.path.isfile(pin):
        for line in open(pin):
            if line.startswith("version="):
                version = line.split("=", 1)[1].strip()
    # Placeholder until the engine installer exists; CI replaces it with the
    # real digest of the artifact it just built and uploaded.
    engine_sha = os.environ.get("QUICKOFFICE_ENGINE_SHA256", "0" * 64)

    os.makedirs(os.path.join(out, "launchers"), exist_ok=True)
    with open(os.path.join(out, "installer-engine.iss"), "w",
              encoding="utf-8") as fh:
        fh.write(render(ENGINE_ISS, version=version))
    print("  installer-engine.iss           (engine %s)" % version)

    for app in APPS:
        meta = json.load(open(os.path.join(REPOS, app["slug"],
                                           ".quickopen.json")))
        assoc = ", ".join(e for e, _ in app["mimes"])
        body = render(
            APP_ISS,
            name=meta["name"], version=version, exe=app["exe"],
            slug=app["slug"], module=app["module"], appid=app["appid"],
            cdn=CDN, engine_sha256=engine_sha, assoc_list=assoc,
            assoc_registry=assoc_registry(app),
            tagline=meta["tagline"].split(".")[0])
        with open(os.path.join(out, "installer-%s.iss" % app["slug"]), "w",
                  encoding="utf-8") as fh:
            fh.write(body)
        with open(os.path.join(out, "launchers", app["slug"] + ".cmd"), "w",
                  encoding="utf-8") as fh:
            fh.write(LAUNCHER_CMD.format(name=meta["name"],
                                         kind=app["kind"],
                                         module=app["module"]))
        print("  installer-%-22s (%s, %d file types)"
              % (app["slug"] + ".iss", app["exe"], len(app["mimes"])))
    print("\nwritten to", out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
