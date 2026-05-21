# Power Install

A GUI-driven Windows dev-machine installer. Open a checkbox list, pick the tools you want, and click **Install Packages**. Dependencies install in the right order, PATH is refreshed between packages, and each install is verified against the live Windows PATH before being reported as OK.

Inspired by the kind of internal "DevOps-Setup" tools larger orgs ship to onboard new engineers - except this one is yours, the catalog is a single PowerShell file you edit, and the whole thing runs from a one-line PowerShell command.

![Version](https://img.shields.io/badge/version-0.5.0-blue) ![Platform](https://img.shields.io/badge/platform-Windows%2011-success) ![Shell](https://img.shields.io/badge/shell-PowerShell%205.1%2B-informational)

---

## Quick start

Open PowerShell (Run as Administrator recommended) and paste:

```powershell
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; iex ((New-Object Net.WebClient).DownloadString('https://raw.githubusercontent.com/packetloss404/powerinstall/main/bootstrap.ps1')); exit
```

That fetches the bootstrap, which fetches the GUI installer, which loads the package catalog. No clone, no install step, no PowerShell module to register.

### Run locally instead

```powershell
git clone https://github.com/packetloss404/powerinstall.git
cd powerinstall
powershell -ExecutionPolicy Bypass -File .\full-kit\Kit-Install.ps1
```

---

## What it does

When you launch it you get a WinForms window:

- A scrollable grid of checkboxes, one per package, organized into categories (AI/coding tools, editors, terminals, languages, cloud CLIs, containers, API tools, design, system utilities).
- **Select All** / **Deselect All** at the top-left.
- A **prerequisite auto-check** sidebar: tick *Aider* and Python 3.12 gets auto-checked; tick *Vercel CLI* and Node.js gets auto-checked. The sidebar tells you which prereqs were added.
- A per-row **status column** (blank → `INSTALL` → `OK` / `PATH?` / `FAIL`) that updates live during install.
- A **log path** in the footer pointing at the full transcript of the run.

Click **Install Packages** and the form stays open while installs run. Each row updates as work proceeds.

---

## Catalog (v0.5.0)

Edit [`full-kit/Packages.ps1`](full-kit/Packages.ps1) to add, remove, or rename anything. Current default catalog:

| Category | Packages |
| --- | --- |
| AI / coding assistants | Claude Desktop, Claude Code CLI, Codex CLI, OpenCode CLI, Cursor, Windsurf, Aider, Continue.dev, Factory.ai (Droid), Perplexity Desktop, Open WebUI |
| Editors / IDEs | VS Code, Notepad++, Obsidian |
| Terminals / shells | Warp, WezTerm, Windows Terminal, PowerShell 7 |
| Git GUIs | GitHub Desktop |
| Languages / runtimes | Node.js (LTS), Python 3.12, .NET Runtime 8, Visual Studio Build Tools, Rust (rustup), Ollama |
| Cloud / dev CLIs | AWS CLI, Azure CLI, Google Cloud SDK, GitHub CLI, Vercel CLI, Cloudflare Wrangler, Railway CLI, Git, uv |
| Containers | Docker Desktop |
| API tools | Postman, Bruno |
| Design | Figma |
| System / utilities | WSL2, 7-Zip, AutoHotkey, PowerToys, ShareX, Password Safe, FileZilla, WinSCP, PuTTY |

Most install via `winget`. The ones that don't:

- npm-based CLIs (Claude Code, Codex, OpenCode, Vercel, Wrangler, Railway) - installed via `npm install -g`, auto-require Node.js.
- pip-based CLIs (Aider, Open WebUI) - installed via `python -m pip install --user`, auto-require Python.
- VS Code extensions (Continue.dev) - installed via `code --install-extension`, auto-require VS Code.
- WSL2 - runs `wsl --install` (needs admin + reboot).
- Factory.ai Droid - runs the official installer (`irm https://app.factory.ai/cli/windows | iex`).
- Visual Studio Build Tools - winget with an `--override` so the C++ workload is included (so Rust on MSVC actually compiles).

---

## How it works

```
bootstrap.ps1                        ← what the one-liner fetches
  └─ downloads + iex's full-kit/Kit-Install.ps1
        ├─ loads full-kit/Packages.ps1   (dot-source if local, web-fetch if remote)
        ├─ preflight (winget present? running as admin?)
        ├─ Start-Transcript → %TEMP%\PowerInstall\install-<timestamp>.log
        ├─ build WinForms GUI
        └─ on Install Packages click:
              ├─ topo-sort selected packages by `Requires`
              └─ for each package:
                    ├─ run install (winget OR custom scriptblock)
                    ├─ refresh process PATH from Machine + User registry
                    └─ run Verify (Get-Command on the expected binary)
```

### Package shape

Each entry in `Packages.ps1` is a hashtable. Minimum fields are `Name` and either `Id` (winget) or `Install` (scriptblock):

```powershell
@{ Name = 'Git'; Id = 'Git.Git'; Verify = 'git' }

@{
    Name     = 'Aider'
    Requires = @('Python 3.12')          # auto-checks this prereq in the GUI
    Verify   = 'aider'                   # post-install: Get-Command aider
    Install  = { Install-PipUser 'aider-chat' }
}
```

| Field | Required | Purpose |
| --- | :-: | --- |
| `Name` | yes | Display label, must be unique (used by `Requires`). |
| `Id` | one of | winget package ID. |
| `Install` | one of | Scriptblock that runs in place of winget. |
| `Source` | no | winget source (default `winget`, use `msstore` for Store apps). |
| `Requires` | no | `string[]` of other package `Name`s to auto-check and install first. |
| `Verify` | no | A binary name (`Get-Command`) or a scriptblock that throws on failure. Skipped for GUI-only apps. |
| `Note` | no | Suffix shown after the label in the GUI. |

### Verify and the PATH check

After each install, Power Install:

1. Reads the current `Path` from `HKLM:\System\CurrentControlSet\Control\Session Manager\Environment` (machine) and `HKCU:\Environment` (user) - the same values Windows shows in **System Properties → Environment Variables**.
2. Rebuilds the running process's `$env:PATH` from those values. This is the step that catches the silent winget gotcha: winget writes to the registry but does **not** update the current process's PATH.
3. Runs `Get-Command <Verify>` against that freshly-rebuilt PATH.

That gives three reported outcomes per package:

| Status | Meaning |
| --- | --- |
| `OK` (green) | Installer succeeded and the binary is on the Windows PATH. Tooltip shows the resolved path. |
| `PATH?` (gold) | Installer succeeded but the binary is not on the Windows PATH yet - usually needs a new shell or reboot. |
| `FAIL` (red) | Installer itself failed. See the transcript log for details. |

---

## Customizing

### Add a package via winget

```powershell
# In Packages.ps1, inside the $Packages = @( ... ) block:
@{ Name = 'jq'; Id = 'jqlang.jq'; Verify = 'jq' }
```

### Add a package with custom install logic

```powershell
@{
    Name    = 'Corp Root Certs'
    Install = {
        $url = 'https://your-host/corp-root.cer'
        $tmp = Join-Path $env:TEMP 'corp-root.cer'
        (New-Object Net.WebClient).DownloadFile($url, $tmp)
        Import-Certificate -FilePath $tmp -CertStoreLocation Cert:\LocalMachine\Root | Out-Null
    }
}
```

### Override the bootstrap source at runtime

The bootstrap defaults to `https://raw.githubusercontent.com/packetloss404/powerinstall` on `main`. Override either with environment variables:

```powershell
$env:PI_BASE_URL   = 'https://raw.githubusercontent.com/yourname/yourfork'
$env:PI_TARGET_REF = 'feature/some-branch'
# now run the one-liner; it'll fetch from your fork
```

### Local-only catalog overrides

Create `full-kit/Packages.local.ps1` with extra entries. It's gitignored, so personal additions won't end up committed. (You'll need to dot-source it yourself from `Packages.ps1` for now - tracked for a future release.)

---

## Logs and output

Each run writes a transcript to:

```
%TEMP%\PowerInstall\install-<yyyyMMdd-HHmmss>.log
```

The path is shown in the GUI footer during install and in the final console summary. The log captures winget output verbatim, so when something fails the actual error is there.

---

## Troubleshooting

**`winget` not found / preflight blocks me.**
On a fresh Windows 11 box, App Installer (which provides `winget`) sometimes needs an update from the Microsoft Store before the `winget` command is available. Open the Store → search "App Installer" → Update. Then re-run.

**Package shows `PATH?` after install.**
The installer succeeded but the binary isn't on the rebuilt PATH. Usually fixed by opening a fresh PowerShell window. WSL2 and Visual Studio Build Tools may need a reboot.

**Custom install (npm/pip) fails with "command not found".**
This shouldn't happen with v0.5.0 because PATH is refreshed between packages, but if it does, make sure the prereq (Node.js or Python) actually finished installing - check its row status before assuming the dependent failed for its own reasons.

**UAC prompts during install.**
Several catalog items (WSL2, Docker Desktop, machine-scope winget installers) need admin. Run the original PowerShell session as Administrator to avoid mid-run prompts.

**Em-dash / weird characters in the title bar.**
Fixed in v0.5.0 - if you see this, you're on an older copy. Pull again.

---

## Layout

```
powerinstall/
├── bootstrap.ps1                 ← entry point for the one-liner
├── full-kit/
│   ├── Kit-Install.ps1           ← GUI + install pipeline
│   └── Packages.ps1              ← the catalog (edit this)
├── README.md
├── DEFERRED.md                   ← what was deliberately cut from v0.5.0
└── .gitignore
```

---

## What's intentionally NOT in v0.5.0

See [`DEFERRED.md`](DEFERRED.md) for the running list. Highlights:

- Search/filter box and section headers in the GUI.
- Persisted selections between runs (`%APPDATA%\PowerInstall\selections.json`).
- `--resume` from a previous run's transcript.
- Self-elevation (currently just warns when not elevated).
- Reboot tracking after WSL/Build Tools installs.
- Per-package log files (transcript captures everything for now).
- Verify checks for GUI-only apps without a CLI.
- WebView2 Runtime, Nerd Font, Ubuntu WSL distro picker.
- LibreChat, Codex Desktop, OpenCode Desktop (no verified Windows install path at v0.5.0 cut).

---

## Versioning

Semantic-ish. Major bumps for breaking changes to `Packages.ps1` schema or the bootstrap protocol; minor for new features and catalog expansion; patch for fixes and small additions. Tags live on `main`.

- **v0.5.0** - First tagged release. GUI installer with prerequisite auto-check, dependency-ordered installs, in-form status column, post-install PATH verification, transcript logging.

---

## Contributing

This is intentionally a small surface: three PowerShell files. To add packages, edit `Packages.ps1`. To change install behavior, edit `Kit-Install.ps1`. To change how the one-liner fetches things, edit `bootstrap.ps1`. Parse-check your changes with:

```powershell
[System.Management.Automation.Language.Parser]::ParseFile('full-kit\Kit-Install.ps1', [ref]$null, [ref]$errors)
$errors
```

Pull requests welcome. Match the existing style: hashtable-per-package, ASCII-only in `.ps1` files (so Windows PowerShell 5.1 without a UTF-8 BOM renders correctly), comments only where the "why" isn't obvious.

---

## License

No license declared yet. Treat as "all rights reserved" until that changes.
