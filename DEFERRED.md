# Deferred from v0.5.0

Items intentionally cut from v0.5.0 so the release has a focused scope. Each entry is a candidate for v0.6.x — revisit when the v0.5.0 shape proves itself in real use.

## GUI / UX

- **Search/filter box** above the checkbox grid. At ~45 packages, scanning is still tolerable; becomes essential as the catalog grows.
- **Section headers** rendered in the grid (currently only in the source as `# -----` comments). Reference Boeing tool has visible category labels.
- **Persisted selections** — write last-chosen packages to `%APPDATA%\PowerInstall\selections.json` and pre-check them on next launch.
- **Per-package description / homepage link** — tooltip currently only shows `Requires`. Could surface a one-line description and an "open homepage" button.
- **Disk-impact preview** — show estimated download/install size next to each package; sum at the bottom.
- **Live log pane** inside the form (currently log only goes to console + transcript file). Would let users see winget progress without alt-tabbing.
- **Visual differentiation for unverified winget IDs** — color/icon instead of a `*` suffix. Not needed in v0.5.0 since all `*`-marked entries were removed.

## Install pipeline

- **`--resume` flag** that reads the previous run's results from the transcript folder and skips already-OK packages. Useful when a long run hits one failure and the user wants to retry.
- **Self-elevation** — auto-relaunch with `Start-Process -Verb RunAs` when admin packages are selected and the session isn't elevated. v0.5.0 just warns in the preflight dialog.
- **Reboot detection** — `wsl --install`, `.NET Runtime`, and Visual Studio Build Tools can require a reboot. v0.5.0 prints "may need reboot" in the WSL2 install message but doesn't track or surface the requirement in the final summary.
- **Idempotency in custom Install scriptblocks** — `Install-NpmGlobal` and `Install-PipUser` re-download on every run instead of checking "is this already current?". Winget paths are already idempotent (handles "already installed" exit code).
- **Per-package log files** — winget output is captured by transcript but isn't broken out per package. A `%TEMP%\PowerInstall\<timestamp>\<package>.log` layout would make triage easier.
- **summary.json on disk** — machine-readable run summary next to the transcript log.
- **Verify scriptblock semantics** — v0.5.0 accepts a scriptblock for `Verify` but the contract is "must throw on failure"; `$LASTEXITCODE` is intentionally ignored to avoid carryover. If we want a richer verify, formalize a return contract (e.g., `@{ Ok = $true; Detail = '...' }`).
- **PATH-not-on-disk warnings** — currently we refresh process PATH from registry. We don't tell the user that *new* shells they open will also have the updated PATH (since registry was written by winget). A one-line note in the summary would help.

## Catalog

- **WebView2 Runtime** — usually preinstalled on modern Windows 11. Not added in v0.5.0 because the winget ID was unverified at write time. Likely `Microsoft.EdgeWebView2`; add when verified.
- **Nerd Font (CascadiaCode or JetBrainsMono)** — Starship is in the catalog but its glyphs need a Nerd Font. Pending: pick a font, decide install method (winget vs. download-from-releases + Add-Font via Shell.Application).
- **Ubuntu WSL distro** — current `WSL2` entry runs `wsl --install` which installs the kernel + default distro (Ubuntu) on modern Windows. Explicit distro selection (`wsl --install -d <name>`) deferred until we offer a picker.
- **PacketCode** — removed in v0.5.0 because the original term was unrecognized. Add when the user clarifies what tool this refers to.
- **LibreChat** — removed in v0.5.0. Real install is `git clone` + `docker compose up`. Add later as a custom Install scriptblock that clones to a chosen folder and starts compose.
- **Codex Desktop / OpenCode Desktop** — removed because no verified install path on Windows existed at write time. Reintroduce once OpenAI/sst ship official installers.
- **JetBrains Toolbox** — entry into all JetBrains IDEs. Worth adding as a single catalog entry.
- **OpenSSH server enable** — `Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0`. Useful for dev boxes that accept inbound SSH.
- **Modern Python tooling alongside `uv`** — `pipx` deliberately omitted since `uv tool install` covers the same ground. Reconsider if user feedback wants both.
- **Candidates to drop in v0.6.0** (per UX reviewer; KEPT in v0.5.0 because the user explicitly listed them):
  - PuTTY — OpenSSH ships with Windows.
  - FileZilla — adware history in the official installer.
  - Password Safe — niche compared to 1Password / Bitwarden.

## Catalog hardening (not strictly cut, but tracked)

- **Verify scriptblocks for GUI-only apps** — packages without a CLI (Postman, Bruno, Figma, Obsidian, Notepad++, GitHub Desktop, Fork, Docker Desktop's GUI shell, PowerToys, ShareX, etc.) have no `Verify` field, so post-install only reports the installer's exit code. Could add `Test-Path`-based verify against expected install dirs.
- **Re-verify winget IDs** for Cursor (`Anysphere.Cursor`), Windsurf (`Codeium.Windsurf`), Warp (`Warp.Warp`), WezTerm (`wez.wezterm`), Fork (`Fork.Fork`), Excalidraw (removed). These were best-guess at write time.
- **VS Build Tools workload override** — v0.5.0 installs `Microsoft.VisualStudio.Workload.VCTools --includeRecommended`. Confirm this is the right minimal set for Rust+MSVC; add Windows SDK explicitly if not already pulled in.

## v0.5.0 scope reminder (what DID ship)

1. `return ,$ordered` → `$ordered.ToArray()` (was a showstopper — every install silently no-op'd).
2. `Update-EnvPath` after each install — refreshes process PATH from Machine+User registry.
3. AutoAdded prerequisite label now uses a recursion-depth counter; outermost handler renders.
4. Preflight gate: detects missing winget (blocks) and missing admin (warns with proceed/abort).
5. Transcript log to `%TEMP%\PowerInstall\install-<timestamp>.log`; path shown in the GUI footer.
6. In-form install-status column (`INSTALL` → `OK` / `PATH?` / `FAIL`), form stays open after install completes.
7. Per-package `Verify` field: after install + PATH refresh, runs `Get-Command <name>` (or a scriptblock). Distinct status for "installed but not on PATH yet".
8. Catalog hygiene: removed PacketCode/LibreChat/Excalidraw stubs; added GitHub CLI, uv, Visual Studio Build Tools; Rust now requires Build Tools.
