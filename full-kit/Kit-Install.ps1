# Kit-Install.ps1 - GUI installer entry point.
# Loaded via Invoke-Expression by bootstrap.ps1, or runnable directly:
#   powershell -ExecutionPolicy Bypass -File .\full-kit\Kit-Install.ps1

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# ---------------------------------------------------------------------------
# Transcript log - captures everything to %TEMP%\PowerInstall\<timestamp>.log
# ---------------------------------------------------------------------------
$logDir  = Join-Path $env:TEMP 'PowerInstall'
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir | Out-Null }
$script:LogPath = Join-Path $logDir ("install-{0}.log" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
try { Start-Transcript -Path $script:LogPath -ErrorAction Stop | Out-Null } catch { Write-Warning "Transcript failed: $_" }

# ---------------------------------------------------------------------------
# Load the package catalog. Dot-source when local, iex when fetched from web.
# ---------------------------------------------------------------------------
$Packages = $null
$localPackages = if ($PSScriptRoot) { Join-Path $PSScriptRoot 'Packages.ps1' } else { $null }

if ($localPackages -and (Test-Path $localPackages)) {
    . $localPackages
} else {
    $base = $env:PI_BASE_URL
    $ref  = if ($env:PI_TARGET_REF) { $env:PI_TARGET_REF } else { 'main' }
    if (-not $base) {
        throw "Cannot locate Packages.ps1. Set `$env:PI_BASE_URL or run locally."
    }
    $url = "${base}/${ref}/full-kit/Packages.ps1"
    Invoke-Expression ((New-Object Net.WebClient).DownloadString($url))
}

if (-not $Packages -or $Packages.Count -eq 0) {
    throw "No packages defined. Edit full-kit\Packages.ps1."
}

# Build name -> package index for fast lookup, and sanity-check Requires refs.
$PackageByName = @{}
foreach ($p in $Packages) { $PackageByName[$p.Name] = $p }
foreach ($p in $Packages) {
    if ($p.Requires) {
        foreach ($r in $p.Requires) {
            if (-not $PackageByName.ContainsKey($r)) {
                Write-Warning "Package '$($p.Name)' requires '$r', which is not in the catalog."
            }
        }
    }
}

# ---------------------------------------------------------------------------
# Environment / preflight helpers
# ---------------------------------------------------------------------------
function Test-IsElevated {
    $id = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $pr = New-Object System.Security.Principal.WindowsPrincipal($id)
    return $pr.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Test-WingetAvailable {
    [bool](Get-Command winget -ErrorAction SilentlyContinue)
}

# Rebuild process PATH from current Machine + User registry values. winget
# updates these mid-run but does NOT touch our $env:PATH, so without this,
# every binary installed during the session is invisible to later steps.
function Update-EnvPath {
    $m = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $u = [Environment]::GetEnvironmentVariable('Path', 'User')
    $combined = @()
    if ($m) { $combined += $m.TrimEnd(';') }
    if ($u) { $combined += $u.TrimEnd(';') }
    $env:PATH = $combined -join ';'
}

# ---------------------------------------------------------------------------
# Install logic
# ---------------------------------------------------------------------------
function Install-WingetPackage {
    param([string]$Id, [string]$Source = 'winget')
    $wingetArgs = @(
        'install', '--id', $Id, '--source', $Source,
        '--exact', '--silent',
        '--accept-package-agreements', '--accept-source-agreements',
        '--disable-interactivity'
    )
    Write-Host "  winget $($wingetArgs -join ' ')" -ForegroundColor DarkGray
    & winget @wingetArgs
    return $LASTEXITCODE
}

function Invoke-PackageInstall {
    param([hashtable]$Package)
    Write-Host ""
    Write-Host "==> Installing $($Package.Name)" -ForegroundColor Cyan

    if ($Package.Install -is [scriptblock]) {
        try {
            & $Package.Install
            Write-Host "    OK (custom)" -ForegroundColor Green
            return $true
        } catch {
            Write-Host "    FAILED: $_" -ForegroundColor Red
            return $false
        }
    }

    if (-not $Package.Id) {
        Write-Host "    SKIP: no Id and no Install scriptblock" -ForegroundColor Yellow
        return $false
    }

    if (-not (Test-WingetAvailable)) {
        Write-Host "    FAILED: winget not found on this machine" -ForegroundColor Red
        return $false
    }

    $source = if ($Package.Source) { $Package.Source } else { 'winget' }
    $code = Install-WingetPackage -Id $Package.Id -Source $source

    # winget exit codes: 0 = success; -1978335189 (0x8A150019) = already installed
    if ($code -eq 0) {
        Write-Host "    OK" -ForegroundColor Green
        return $true
    } elseif ($code -eq -1978335189) {
        Write-Host "    Already installed" -ForegroundColor DarkGreen
        return $true
    } else {
        Write-Host "    FAILED (winget exit $code)" -ForegroundColor Red
        return $false
    }
}

# Run the Verify check for a package: returns @{ Ran=$bool; Ok=$bool; Detail=$string }.
function Invoke-PackageVerify {
    param([hashtable]$Package)
    if (-not $Package.ContainsKey('Verify') -or $null -eq $Package.Verify) {
        return @{ Ran = $false; Ok = $true; Detail = '' }
    }
    Update-EnvPath
    try {
        if ($Package.Verify -is [scriptblock]) {
            # Scriptblock author owns its own success signal - throw on failure.
            & $Package.Verify | Out-Null
            return @{ Ran = $true; Ok = $true; Detail = 'scriptblock OK' }
        } else {
            $name = [string]$Package.Verify
            $cmd  = Get-Command $name -ErrorAction SilentlyContinue
            if ($cmd) {
                return @{ Ran = $true; Ok = $true;  Detail = $cmd.Source }
            } else {
                return @{ Ran = $true; Ok = $false; Detail = "'$name' not on PATH" }
            }
        }
    } catch {
        return @{ Ran = $true; Ok = $false; Detail = $_.Exception.Message }
    }
}

# Topologically sort selected packages so prerequisites install first.
function Get-InstallOrder {
    param([System.Collections.IEnumerable]$Selected)

    $selectedByName = @{}
    foreach ($p in $Selected) { $selectedByName[$p.Name] = $p }

    $visited = @{}
    $stack   = @{}
    $ordered = New-Object System.Collections.Generic.List[hashtable]

    function _Visit($name) {
        if ($visited[$name]) { return }
        if ($stack[$name])  { return }
        $stack[$name] = $true
        $pkg = $selectedByName[$name]
        if ($pkg.Requires) {
            foreach ($r in $pkg.Requires) {
                if ($selectedByName.ContainsKey($r)) { _Visit $r }
            }
        }
        $stack.Remove($name)
        $visited[$name] = $true
        $ordered.Add($pkg)
    }

    foreach ($p in $Selected) { _Visit $p.Name }
    # IMPORTANT: return as plain array so callers can foreach over hashtables.
    return $ordered.ToArray()
}

# ---------------------------------------------------------------------------
# Preflight
# ---------------------------------------------------------------------------
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

function Show-Preflight {
    if (-not (Test-WingetAvailable)) {
        [void][System.Windows.Forms.MessageBox]::Show(
            "winget is not on PATH.`n`nInstall 'App Installer' from the Microsoft Store (or update it if installed), then re-run Power Install.",
            'Power Install: winget missing',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error)
        return $false
    }
    if (-not (Test-IsElevated)) {
        $msg = @(
            "Power Install is not running as Administrator.",
            "",
            "These items will fail or trigger UAC prompts mid-run without elevation:",
            "  - WSL2",
            "  - Docker Desktop",
            "  - Visual Studio Build Tools",
            "  - winget machine-scope installers (Python, .NET, Git, etc.)",
            "",
            "Continue anyway?"
        ) -join "`n"
        $r = [System.Windows.Forms.MessageBox]::Show(
            $msg, 'Power Install: Not elevated',
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Warning)
        if ($r -ne [System.Windows.Forms.DialogResult]::Yes) { return $false }
    }
    return $true
}

if (-not (Show-Preflight)) {
    try { Stop-Transcript | Out-Null } catch {}
    return
}

# ---------------------------------------------------------------------------
# Build the GUI
# ---------------------------------------------------------------------------
$form = New-Object System.Windows.Forms.Form
$form.Text = 'Power Install: Select Packages'
$form.StartPosition = 'CenterScreen'
$form.MinimumSize = New-Object System.Drawing.Size(1000, 620)
$form.Size = New-Object System.Drawing.Size(1200, 740)

# Header
$header = New-Object System.Windows.Forms.Label
$header.Text = "Select the packages to install and click 'Install Packages'"
$header.AutoSize = $true
$header.Font = New-Object System.Drawing.Font('Segoe UI', 11, [System.Drawing.FontStyle]::Regular)
$header.Location = New-Object System.Drawing.Point(15, 12)
$form.Controls.Add($header)

# Select All / Deselect All
$btnSelectAll = New-Object System.Windows.Forms.Button
$btnSelectAll.Text = 'Select All'
$btnSelectAll.Size = New-Object System.Drawing.Size(110, 28)
$btnSelectAll.Location = New-Object System.Drawing.Point(15, 42)
$form.Controls.Add($btnSelectAll)

$btnDeselectAll = New-Object System.Windows.Forms.Button
$btnDeselectAll.Text = 'Deselect All'
$btnDeselectAll.Size = New-Object System.Drawing.Size(110, 28)
$btnDeselectAll.Location = New-Object System.Drawing.Point(15, 76)
$form.Controls.Add($btnDeselectAll)

# Sidebar label that announces auto-checked prerequisites
$autoLabel = New-Object System.Windows.Forms.Label
$autoLabel.Text = ''
$autoLabel.AutoSize = $false
$autoLabel.Size = New-Object System.Drawing.Size(110, 200)
$autoLabel.Location = New-Object System.Drawing.Point(15, 112)
$autoLabel.ForeColor = [System.Drawing.Color]::SteelBlue
$autoLabel.Font = New-Object System.Drawing.Font('Segoe UI', 8)
$form.Controls.Add($autoLabel)

# Scrollable panel that holds the checkbox grid + status column
$panel = New-Object System.Windows.Forms.Panel
$panel.Location = New-Object System.Drawing.Point(140, 42)
$panel.Anchor = 'Top, Left, Right, Bottom'
$panel.Size = New-Object System.Drawing.Size(($form.ClientSize.Width - 155), ($form.ClientSize.Height - 110))
$panel.AutoScroll = $true
$panel.BorderStyle = 'FixedSingle'
$form.Controls.Add($panel)

# Column layout: each cell = [checkbox 145px] [status 55px], 200px total.
$colWidth   = 200
$cbWidth    = 145
$statusW    = 50
$rowHeight  = 28
$leftPad    = 10
$topPad     = 8

$desiredCols = [Math]::Max(1, [Math]::Floor(($panel.ClientSize.Width - $leftPad) / $colWidth))
$rowsPerCol  = [Math]::Ceiling($Packages.Count / $desiredCols)

$checkboxes = @()
$rowsByName = @{}

for ($i = 0; $i -lt $Packages.Count; $i++) {
    $pkg = $Packages[$i]
    $col = [Math]::Floor($i / $rowsPerCol)
    $row = $i % $rowsPerCol
    $x   = $leftPad + $col * $colWidth
    $y   = $topPad  + $row * $rowHeight

    $cb = New-Object System.Windows.Forms.CheckBox
    $label = $pkg.Name
    if ($pkg.Note) { $label = "$label $($pkg.Note)" }
    $cb.Text = $label
    $cb.Tag  = $pkg
    $cb.AutoSize = $false
    $cb.Size = New-Object System.Drawing.Size($cbWidth, $rowHeight)
    $cb.Location = New-Object System.Drawing.Point($x, $y)

    if ($pkg.Requires) {
        $tt = New-Object System.Windows.Forms.ToolTip
        $tt.SetToolTip($cb, "Requires: $($pkg.Requires -join ', ')")
    }

    $status = New-Object System.Windows.Forms.Label
    $status.AutoSize = $false
    $status.Size = New-Object System.Drawing.Size($statusW, $rowHeight)
    $status.Location = New-Object System.Drawing.Point(($x + $cbWidth), $y)
    $status.Text = ''
    $status.ForeColor = [System.Drawing.Color]::DimGray
    $status.Font = New-Object System.Drawing.Font('Segoe UI', 8, [System.Drawing.FontStyle]::Bold)
    $status.TextAlign = 'MiddleLeft'

    $panel.Controls.Add($cb)
    $panel.Controls.Add($status)

    $checkboxes += $cb
    $rowsByName[$pkg.Name] = @{ Checkbox = $cb; Status = $status; Package = $pkg }
}

# Auto-check prerequisites - uses a depth counter so only the outermost
# handler renders the "auto-added" label.
$script:AutoCheckDepth = 0
$script:AutoAdded      = @()
$script:SuppressAuto   = $false

function _AutoCheckRequires {
    param([System.Windows.Forms.CheckBox]$Source)
    if (-not $Source.Checked) { return }
    $pkg = $Source.Tag
    if (-not $pkg.Requires) { return }
    foreach ($reqName in $pkg.Requires) {
        $reqCb = $rowsByName[$reqName].Checkbox
        if ($reqCb -and -not $reqCb.Checked) {
            $script:AutoAdded += $reqName
            $reqCb.Checked = $true   # recurses
        }
    }
}

foreach ($cb in $checkboxes) {
    $cb.Add_CheckedChanged({
        param($s, $e)
        if ($script:SuppressAuto) { return }
        $script:AutoCheckDepth++
        try {
            _AutoCheckRequires -Source $s
        } finally {
            $script:AutoCheckDepth--
        }
        if ($script:AutoCheckDepth -eq 0 -and $script:AutoAdded.Count -gt 0) {
            $unique = $script:AutoAdded | Select-Object -Unique
            $autoLabel.Text = "Auto-added prerequisites:`n  " + ($unique -join "`n  ")
            $script:AutoAdded = @()
        }
    })
}

# Bottom action buttons
$btnInstall = New-Object System.Windows.Forms.Button
$btnInstall.Text = 'Install Packages'
$btnInstall.Size = New-Object System.Drawing.Size(150, 32)
$btnInstall.Anchor = 'Bottom, Left'
$btnInstall.Location = New-Object System.Drawing.Point(15, ($form.ClientSize.Height - 50))
$form.Controls.Add($btnInstall)

$btnCancel = New-Object System.Windows.Forms.Button
$btnCancel.Text = 'Cancel'
$btnCancel.Size = New-Object System.Drawing.Size(110, 32)
$btnCancel.Anchor = 'Bottom, Left'
$btnCancel.Location = New-Object System.Drawing.Point(175, ($form.ClientSize.Height - 50))
$form.Controls.Add($btnCancel)

# Footer
$footer = New-Object System.Windows.Forms.Label
$footer.Text = "Log: $script:LogPath"
$footer.AutoSize = $true
$footer.ForeColor = [System.Drawing.Color]::DimGray
$footer.Anchor = 'Bottom, Left'
$footer.Location = New-Object System.Drawing.Point(15, ($form.ClientSize.Height - 18))
$form.Controls.Add($footer)

# Bulk buttons
$btnSelectAll.Add_Click({
    $script:SuppressAuto = $true
    foreach ($cb in $checkboxes) { $cb.Checked = $true }
    $script:SuppressAuto = $false
    $autoLabel.Text = ''
})
$btnDeselectAll.Add_Click({
    $script:SuppressAuto = $true
    foreach ($cb in $checkboxes) { $cb.Checked = $false }
    $script:SuppressAuto = $false
    $autoLabel.Text = ''
})
$btnCancel.Add_Click({ $form.Close() })

# Helper to update a row's status text + color.
function Set-RowStatus {
    param($Name, $Text, $Color, $Tooltip = $null)
    $row = $rowsByName[$Name]
    if (-not $row) { return }
    $row.Status.Text = $Text
    $row.Status.ForeColor = $Color
    if ($Tooltip) {
        $tt = New-Object System.Windows.Forms.ToolTip
        $tt.SetToolTip($row.Status, $Tooltip)
    }
    [System.Windows.Forms.Application]::DoEvents()
}

# ---------------------------------------------------------------------------
# Install button: runs the install pipeline IN-FORM. The form stays open;
# rows update with per-package status as work proceeds. When done the button
# turns into "Close".
# ---------------------------------------------------------------------------
$script:InstallDone = $false
$script:Results = @{ Ok = @(); Failed = @(); VerifyWarn = @() }

$btnInstall.Add_Click({
    if ($script:InstallDone) { $form.Close(); return }

    $selected = @($checkboxes | Where-Object { $_.Checked } | ForEach-Object { $_.Tag })
    if ($selected.Count -eq 0) {
        [void][System.Windows.Forms.MessageBox]::Show(
            'No packages selected.', 'Power Install',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information)
        return
    }

    $ordered = Get-InstallOrder -Selected $selected

    # Lock controls during install
    $btnInstall.Enabled    = $false
    $btnSelectAll.Enabled  = $false
    $btnDeselectAll.Enabled = $false
    $btnCancel.Enabled     = $false
    foreach ($cb in $checkboxes) { $cb.Enabled = $false }

    foreach ($pkg in $ordered) {
        Set-RowStatus -Name $pkg.Name -Text 'INSTALL' -Color ([System.Drawing.Color]::DarkOrange)

        $installOk = Invoke-PackageInstall -Package $pkg

        if (-not $installOk) {
            Set-RowStatus -Name $pkg.Name -Text 'FAIL' -Color ([System.Drawing.Color]::Firebrick) -Tooltip 'See log for details.'
            $script:Results.Failed += $pkg.Name
            continue
        }

        # PATH refresh + verify
        $verify = Invoke-PackageVerify -Package $pkg

        if (-not $verify.Ran) {
            Set-RowStatus -Name $pkg.Name -Text 'OK' -Color ([System.Drawing.Color]::ForestGreen)
            $script:Results.Ok += $pkg.Name
        } elseif ($verify.Ok) {
            Set-RowStatus -Name $pkg.Name -Text 'OK' -Color ([System.Drawing.Color]::ForestGreen) -Tooltip $verify.Detail
            $script:Results.Ok += $pkg.Name
            Write-Host "    Verify: $($verify.Detail)" -ForegroundColor DarkGreen
        } else {
            Set-RowStatus -Name $pkg.Name -Text 'PATH?' -Color ([System.Drawing.Color]::DarkGoldenrod) `
                -Tooltip "Installed but verify failed: $($verify.Detail). May need a new shell or reboot."
            $script:Results.VerifyWarn += $pkg.Name
            Write-Host "    Verify FAILED: $($verify.Detail) (a new shell or reboot may resolve)" -ForegroundColor Yellow
        }
    }

    # Done - flip button to Close, update footer summary.
    $okN   = $script:Results.Ok.Count
    $failN = $script:Results.Failed.Count
    $warnN = $script:Results.VerifyWarn.Count
    $footer.Text = "Installed: $okN  |  Verify warnings: $warnN  |  Failed: $failN  |  Log: $script:LogPath"
    $btnInstall.Text = 'Close'
    $btnInstall.Enabled = $true
    $script:InstallDone = $true
})

# Show
[void]$form.ShowDialog()

# ---------------------------------------------------------------------------
# Final console summary (also captured in transcript)
# ---------------------------------------------------------------------------
if ($script:InstallDone) {
    Write-Host ""
    Write-Host "===== Summary =====" -ForegroundColor White
    Write-Host "Succeeded:       $($script:Results.Ok.Count)" -ForegroundColor Green
    $script:Results.Ok | ForEach-Object { Write-Host "  + $_" -ForegroundColor DarkGreen }
    if ($script:Results.VerifyWarn.Count -gt 0) {
        Write-Host "Verify warnings: $($script:Results.VerifyWarn.Count) (installed but binary not on PATH yet)" -ForegroundColor Yellow
        $script:Results.VerifyWarn | ForEach-Object { Write-Host "  ~ $_" -ForegroundColor DarkYellow }
    }
    if ($script:Results.Failed.Count -gt 0) {
        Write-Host "Failed:          $($script:Results.Failed.Count)" -ForegroundColor Red
        $script:Results.Failed | ForEach-Object { Write-Host "  - $_" -ForegroundColor DarkRed }
    }
    Write-Host ""
    Write-Host "Log: $script:LogPath" -ForegroundColor DarkGray
}

try { Stop-Transcript | Out-Null } catch {}
