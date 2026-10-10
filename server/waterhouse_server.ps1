# Runs the Valheim dedicated server on the Waterhouse world, kept in sync with GitHub.
#
#  1. On start: fetch the world repo, show what changed on GitHub, fast-forward to it.
#     Refuses to start if local and GitHub history have diverged (someone else hosted
#     while this copy also had unpushed saves) so neither copy gets overwritten.
#  2. While running: after a world save ("World save (5/5) done"), commit and push if the
#     last commit is at least -CommitIntervalMinutes old (default 4 hours).
#  3. On shutdown (Ctrl-C): wait for the server's final save, then commit and push.
#
# Started from a .bat in the Valheim dedicated server folder (see start_server.example.bat
# and README.md). Stop the server with Ctrl-C, not by closing the window, so the final
# save gets made and pushed.
param(
    [Parameter(Mandatory)][string]$Password,
    [string]$ServerName = 'My server',
    [string]$ServerDir = 'C:\Program Files (x86)\Steam\steamapps\common\Valheim dedicated server',
    [int]$Port = 2456,
    [string]$World = 'Waterhouse',
    [string]$SaveDir = "$env:USERPROFILE\ValheimSaves",
    [int]$SaveInterval = 0,   # seconds; 0 = Valheim default (1800)
    [switch]$Crossplay,
    # Extra valheim_server options passed through as-is, e.g. world modifiers:
    #   "-preset hard -modifier deathpenalty veryeasy -modifier resources more -setkey nomap"
    # They are stored in the world, so every host should use the same ones.
    [string]$ExtraArgs = '',
    # Minimum time between auto-save commits while running; 0 = commit every world save.
    # Startup recovery and shutdown always commit.
    [int]$CommitIntervalMinutes = 240
)

$ErrorActionPreference = 'Stop'
$Repo = Join-Path $SaveDir "worlds_local\$World"
$LogFile = Join-Path $SaveDir 'server.log'

function Write-Sync([string]$Message, [string]$Color = 'Cyan') {
    Write-Host "[sync $(Get-Date -Format HH:mm:ss)] $Message" -ForegroundColor $Color
}

function Invoke-Git {
    # PowerShell 5.1 turns native stderr into errors when redirected; don't let that throw.
    $ErrorActionPreference = 'Continue'
    $out = & git -C $Repo @args 2>&1 | ForEach-Object { "$_" }
    [pscustomobject]@{ Code = $LASTEXITCODE; Out = ($out -join "`n").Trim() }
}

function Get-SaveNumber {
    $ok = Get-ChildItem $Repo -Filter '_main.*.ok' | Select-Object -First 1
    if ($ok) { $ok.Name.Split('.')[1] } else { '?' }
}

function Push-World {
    $push = Invoke-Git push -q origin HEAD
    if ($push.Code -eq 0) {
        Write-Sync 'Pushed to GitHub.' Green
    } else {
        Write-Sync "Push FAILED; will retry after the next save.`n$($push.Out)" Yellow
    }
}

function Save-World([string]$Reason, [switch]$NoPush) {
    Invoke-Git add -A | Out-Null
    if ((Invoke-Git diff --cached --quiet).Code -eq 0) { return $false }
    $commit = Invoke-Git commit -q -m "$Reason (save #$(Get-SaveNumber), host $env:COMPUTERNAME)"
    if ($commit.Code -ne 0) {
        Write-Sync "Commit FAILED:`n$($commit.Out)" Red
        return $false
    }
    Write-Sync "Committed: $Reason (save #$(Get-SaveNumber))" Green
    if (-not $NoPush) { Push-World }
    return $true
}

# --- Startup sync --------------------------------------------------------------------

if (-not (Test-Path (Join-Path $Repo '.git'))) {
    throw "World repo not found at $Repo"
}

if (Save-World 'Recovered unsynced save found at startup' -NoPush) {
    Write-Sync 'Found save files that were never committed (last run was not shut down cleanly).' Yellow
}

Write-Sync "Checking GitHub for changes to $World..."
$fetch = Invoke-Git fetch -q origin
if ($fetch.Code -ne 0) {
    Write-Sync "Could not reach GitHub:`n$($fetch.Out)" Red
    $answer = Read-Host 'Start anyway with the local copy of the world? (y/N)'
    if ($answer -notmatch '^y') { exit 1 }
} else {
    $ahead, $behind = (Invoke-Git rev-list --left-right --count 'HEAD...@{u}').Out -split '\s+' | ForEach-Object { [int]$_ }
    if ($ahead -gt 0 -and $behind -gt 0) {
        Write-Sync "Local world and GitHub have DIVERGED ($ahead local / $behind remote commits):" Red
        Write-Host (Invoke-Git log --oneline --left-right 'HEAD...@{u}').Out
        Write-Sync "Refusing to start so neither copy is lost. Decide which one to keep, then resolve in $Repo" Red
        exit 1
    }
    if ($behind -gt 0) {
        Write-Sync "GitHub has $behind newer save(s):" Yellow
        (Invoke-Git log --format='%h %ad %an: %s' --date=format:'%Y-%m-%d %H:%M' 'HEAD..@{u}').Out -split "`n" |
            ForEach-Object { Write-Host "  $_" }
        Write-Host "  $((Invoke-Git diff --shortstat HEAD '@{u}').Out)"
        $merge = Invoke-Git merge -q --ff-only '@{u}'
        if ($merge.Code -ne 0) {
            Write-Sync "Update FAILED:`n$($merge.Out)" Red
            exit 1
        }
        Write-Sync "Updated local world to save #$(Get-SaveNumber)." Green
    } elseif ($ahead -gt 0) {
        Write-Sync "Local world has $ahead unpushed save(s); pushing." Yellow
        Push-World
    } else {
        Write-Sync "World is up to date with GitHub (save #$(Get-SaveNumber))." Green
    }
}

# --- Run server ----------------------------------------------------------------------

# From here on, git must never block waiting for a login prompt.
$env:GCM_INTERACTIVE = 'never'
$env:GIT_TERMINAL_PROMPT = '0'
$env:SteamAppId = '892970'

$serverArgs = @(
    '-nographics', '-batchmode',
    '-name', "`"$ServerName`"",
    '-port', $Port,
    '-world', "`"$World`"",
    '-password', "`"$Password`"",
    '-savedir', "`"$SaveDir`"",
    '-logFile', "`"$LogFile`""
)
if ($SaveInterval -gt 0) { $serverArgs += '-saveinterval', $SaveInterval }
if ($Crossplay) { $serverArgs += '-crossplay' }
$serverArgs += $ExtraArgs -split '\s+' | Where-Object { $_ }
if ($ExtraArgs) { Write-Sync "Extra server options: $ExtraArgs" }

# ServersideQoL mods: keep their settings in the world folder (this repo) so every host
# runs the same ones. Only the ConfigPerWorld switch itself lives in the host's BepInEx.
$sqolPlugin = Join-Path $ServerDir 'BepInEx\plugins\ArgusMagnus-ServersideQoL'
if (Test-Path $sqolPlugin) {
    $sqolCfg = Join-Path $ServerDir 'BepInEx\config\ArgusMagnus.ServersideQoL.cfg'
    if (-not (Test-Path $sqolCfg)) {
        New-Item -ItemType Directory -Force (Split-Path $sqolCfg) | Out-Null
        Set-Content $sqolCfg "[General]`r`nConfigPerWorld = true" -Encoding utf8
    } elseif ((Get-Content $sqolCfg -Raw) -match 'ConfigPerWorld = false') {
        (Get-Content $sqolCfg -Raw) -replace 'ConfigPerWorld = false', 'ConfigPerWorld = true' |
            Set-Content $sqolCfg -Encoding utf8 -NoNewline
    }
    Write-Sync 'ServersideQoL mods found; using mod settings from the world repo.'
} else {
    Write-Sync 'ServersideQoL mods NOT installed on this host; mod features will be off (see README).' Yellow
}

if (Test-Path $LogFile) { Remove-Item $LogFile }
Write-Sync 'Starting server. Press Ctrl-C to stop (it will save and push before exiting).'
$server = Start-Process (Join-Path $ServerDir 'valheim_server.exe') -ArgumentList $serverArgs `
    -WorkingDirectory $ServerDir -NoNewWindow -PassThru
$null = $server.Handle  # keep the handle so HasExited/ExitCode stay available

$reader = $null
$pending = ''
function Read-LogLines {
    if (-not $script:reader) {
        if (-not (Test-Path $LogFile)) { return }
        $fs = [IO.File]::Open($LogFile, 'Open', 'Read', 'ReadWrite, Delete')
        $script:reader = New-Object IO.StreamReader($fs)
    }
    # Only hand back complete lines; keep a trailing partial line for the next read.
    $parts = ($script:pending + $script:reader.ReadToEnd()) -split "`r?`n"
    $script:pending = $parts[-1]
    if ($parts.Count -gt 1) { $parts[0..($parts.Count - 2)] }
}

try {
    while (-not $server.HasExited) {
        $lines = @(Read-LogLines)
        foreach ($line in $lines) {
            Write-Host $line
            if ($line -match 'World save \(5/5\) done') {
                # Measured from the last commit (whoever made it), so restarts don't reset it.
                $lastCommit = [DateTimeOffset]::FromUnixTimeSeconds([long](Invoke-Git log -1 --format=%ct).Out)
                if (([DateTimeOffset]::Now - $lastCommit).TotalMinutes -ge $CommitIntervalMinutes) {
                    $null = Save-World 'Auto-save'
                }
            }
        }
        if ($lines.Count -eq 0) { Start-Sleep -Milliseconds 500 }
    }
} finally {
    # Runs on Ctrl-C too: the server is shutting down and writing its final save.
    if (-not $server.HasExited) {
        Write-Sync 'Waiting for the server to finish saving and exit...'
        $server.WaitForExit()
    }
    Read-LogLines | ForEach-Object { Write-Host $_ }
    if ($reader) { $reader.Close() }
    Write-Sync "Server exited (code $($server.ExitCode))."
    if (-not (Save-World 'Save on shutdown')) {
        # Nothing new to commit, but an earlier push may have failed.
        if ((Invoke-Git rev-list --count '@{u}..HEAD').Out -ne '0') { Push-World }
    }
}
