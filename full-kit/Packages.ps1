# Package catalog for the installer GUI.
#
# Each entry is a hashtable. Fields:
#   Name      - Display label in the GUI (required, must be unique - used by Requires)
#   Id        - winget package ID, used when Install is not supplied
#   Source    - winget source (default: winget). Use "msstore" for Store apps.
#   Install   - Optional scriptblock. If present, runs instead of winget.
#   Requires  - Optional string[] of other package Names. Checking this box
#               auto-checks those, and installs run dependencies first.
#   Verify    - Optional. After install, refresh PATH and check this binary is
#               callable. String = `Get-Command <name>`. Scriptblock = run, must
#               not throw and (if it sets $LASTEXITCODE) must exit 0.
#               Omit for GUI-only packages with no CLI to test.
#   Note      - Optional suffix shown after the label.
#
# Order here is the order shown in the GUI (filled column-by-column).

# --- Helpers usable inside Install scriptblocks --------------------------------
function Install-NpmGlobal {
    param([Parameter(Mandatory)][string]$Package)
    if (-not (Get-Command npm -ErrorAction SilentlyContinue)) {
        throw "npm not found. Install Node.js first."
    }
    & npm install -g $Package
    if ($LASTEXITCODE -ne 0) { throw "npm install -g $Package failed (exit $LASTEXITCODE)" }
}

function Install-PipUser {
    param([Parameter(Mandatory)][string]$Package)
    $py = Get-Command python -ErrorAction SilentlyContinue
    if (-not $py) { $py = Get-Command py -ErrorAction SilentlyContinue }
    if (-not $py) { throw "python not found. Install Python first." }
    & $py.Source -m pip install --user --upgrade $Package
    if ($LASTEXITCODE -ne 0) { throw "pip install $Package failed (exit $LASTEXITCODE)" }
}

function Install-VSCodeExtension {
    param([Parameter(Mandatory)][string]$ExtensionId)
    $code = Get-Command code -ErrorAction SilentlyContinue
    if (-not $code) { throw "VS Code 'code' CLI not found on PATH. Install VS Code first." }
    & $code.Source --install-extension $ExtensionId --force
    if ($LASTEXITCODE -ne 0) { throw "code --install-extension $ExtensionId failed (exit $LASTEXITCODE)" }
}

# --- Catalog ------------------------------------------------------------------
$Packages = @(
    # ----- AI / coding assistants -----
    @{ Name = 'Claude (Desktop)';     Id = 'Anthropic.Claude' }
    @{ Name = 'Claude Code CLI';      Requires = @('Node.js (LTS)'); Verify = 'claude';   Install = { Install-NpmGlobal '@anthropic-ai/claude-code' } }
    @{ Name = 'Codex CLI';            Requires = @('Node.js (LTS)'); Verify = 'codex';    Install = { Install-NpmGlobal '@openai/codex' } }
    @{ Name = 'OpenCode CLI';         Requires = @('Node.js (LTS)'); Verify = 'opencode'; Install = { Install-NpmGlobal 'opencode-ai' } }
    @{ Name = 'Cursor';               Id = 'Anysphere.Cursor';        Verify = 'cursor' }
    @{ Name = 'Windsurf';             Id = 'Codeium.Windsurf';        Verify = 'windsurf' }
    @{ Name = 'Aider';                Requires = @('Python 3.12');    Verify = 'aider'; Install = { Install-PipUser 'aider-chat' } }
    @{ Name = 'Continue.dev';         Requires = @('VS Code');        Install = { Install-VSCodeExtension 'Continue.continue' } }
    @{ Name = 'Factory.ai (Droid)';   Verify = 'droid'; Install = {
        Invoke-Expression ((New-Object Net.WebClient).DownloadString('https://app.factory.ai/cli/windows'))
    } }
    @{ Name = 'Perplexity (Desktop)'; Id = 'Perplexity.Perplexity' }
    @{ Name = 'Open WebUI';           Requires = @('Python 3.12');    Verify = 'open-webui'; Install = {
        Install-PipUser 'open-webui'
        Write-Host "    Installed. Start with: open-webui serve" -ForegroundColor DarkGreen
    } }

    # ----- Editors / IDEs -----
    @{ Name = 'VS Code';              Id = 'Microsoft.VisualStudioCode'; Verify = 'code' }
    @{ Name = 'Notepad++';            Id = 'Notepad++.Notepad++' }
    @{ Name = 'Obsidian';             Id = 'Obsidian.Obsidian' }

    # ----- Terminals / shells -----
    @{ Name = 'Warp';                 Id = 'Warp.Warp' }
    @{ Name = 'WezTerm';              Id = 'wez.wezterm';        Verify = 'wezterm' }
    @{ Name = 'Windows Terminal';     Id = 'Microsoft.WindowsTerminal'; Verify = 'wt' }
    @{ Name = 'PowerShell 7';         Id = 'Microsoft.PowerShell';      Verify = 'pwsh' }

    # ----- Git GUIs -----
    @{ Name = 'GitHub Desktop';       Id = 'GitHub.GitHubDesktop' }

    # ----- Languages / runtimes -----
    @{ Name = 'Node.js (LTS)';        Id = 'OpenJS.NodeJS.LTS';      Verify = 'node' }
    @{ Name = 'Python 3.12';          Id = 'Python.Python.3.12';     Verify = 'python' }
    @{ Name = '.NET Runtime 8';       Id = 'Microsoft.DotNet.Runtime.8'; Verify = 'dotnet' }
    @{ Name = 'Visual Studio Build Tools'; Verify = 'cl'; Install = {
        # BuildTools alone is unusable for Rust without the C++ workload, so we
        # override winget to install the VCTools workload + recommended bits.
        if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
            throw "winget not found"
        }
        $override = '--quiet --wait --norestart --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended'
        & winget install --id Microsoft.VisualStudio.2022.BuildTools --exact --silent `
            --accept-package-agreements --accept-source-agreements `
            --disable-interactivity --override $override
        if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne -1978335189) {
            throw "winget install BuildTools failed (exit $LASTEXITCODE)"
        }
    } }
    @{ Name = 'Rust (rustup)';        Requires = @('Visual Studio Build Tools'); Id = 'Rustlang.Rustup'; Verify = 'cargo' }
    @{ Name = 'Ollama';               Id = 'Ollama.Ollama'; Verify = 'ollama' }

    # ----- Cloud / dev CLIs -----
    @{ Name = 'AWS CLI';              Id = 'Amazon.AWSCLI';            Verify = 'aws' }
    @{ Name = 'Azure CLI';            Id = 'Microsoft.AzureCLI';       Verify = 'az' }
    @{ Name = 'Google Cloud SDK';     Id = 'Google.CloudSDK';          Verify = 'gcloud' }
    @{ Name = 'GitHub CLI';           Id = 'GitHub.cli';               Verify = 'gh' }
    @{ Name = 'Vercel CLI';           Requires = @('Node.js (LTS)');   Verify = 'vercel';   Install = { Install-NpmGlobal 'vercel' } }
    @{ Name = 'Cloudflare Wrangler';  Requires = @('Node.js (LTS)');   Verify = 'wrangler'; Install = { Install-NpmGlobal 'wrangler' } }
    @{ Name = 'Railway CLI';          Requires = @('Node.js (LTS)');   Verify = 'railway';  Install = { Install-NpmGlobal '@railway/cli' } }
    @{ Name = 'Git';                  Id = 'Git.Git';                  Verify = 'git' }
    @{ Name = 'uv (Python)';          Id = 'astral-sh.uv';             Verify = 'uv' }

    # ----- Containers -----
    @{ Name = 'Docker Desktop';       Id = 'Docker.DockerDesktop';     Verify = 'docker' }

    # ----- API / DB tools -----
    @{ Name = 'Postman';              Id = 'Postman.Postman' }
    @{ Name = 'Bruno';                Id = 'Bruno.Bruno' }

    # ----- Design -----
    @{ Name = 'Figma';                Id = 'Figma.Figma' }

    # ----- System / utilities -----
    @{ Name = 'WSL2';                 Verify = 'wsl'; Install = {
        Write-Host "    Running 'wsl --install' (requires admin; reboot may be needed)." -ForegroundColor Yellow
        & wsl --install
        if ($LASTEXITCODE -ne 0) { throw "wsl --install failed (exit $LASTEXITCODE)" }
    } }
    @{ Name = '7-Zip';                Id = '7zip.7zip' }
    @{ Name = 'AutoHotkey';           Id = 'AutoHotkey.AutoHotkey' }
    @{ Name = 'PowerToys';            Id = 'Microsoft.PowerToys' }
    @{ Name = 'ShareX';               Id = 'ShareX.ShareX' }
    @{ Name = 'Password Safe';        Id = 'RonyShapiro.PasswordSafe' }
    @{ Name = 'FileZilla';            Id = 'TimKosse.FileZilla.Client' }
    @{ Name = 'WinSCP';               Id = 'WinSCP.WinSCP' }
    @{ Name = 'PuTTY';                Id = 'PuTTY.PuTTY' }
)
