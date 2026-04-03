param(
    [Parameter(Mandatory = $true)]
    [string]$Ip,
    [string]$Password = "",
    [string]$HostKey = "",
    [int]$Port = 22,
    [switch]$All,
    [switch]$PerFile,
    [switch]$DryRun,
    [switch]$TailLogs
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$RemoteRoot = "/run/muos/storage/application/Scrappy"
$User = "root"
$UsePuttyAuth = -not [string]::IsNullOrWhiteSpace($Password)
$PasswordFallback = $false

if ($UsePuttyAuth) {
    if (-not (Get-Command plink -ErrorAction SilentlyContinue) -or -not (Get-Command pscp -ErrorAction SilentlyContinue)) {
        Write-Warning "Password auth requested, but PuTTY tools (plink/pscp) are not available."
        Write-Warning "Falling back to OpenSSH (ssh/scp). Password will be prompted by ssh/scp."
        $UsePuttyAuth = $false
        $PasswordFallback = $true
    }
}

function To-UnixPath {
    param([string]$Path)
    return ($Path -replace "\\", "/")
}

function Is-RuntimePath {
    param([string]$RelPath)

    $p = (To-UnixPath -Path $RelPath).TrimStart("./")

    # App launcher lives at app root, not in .scrappy
    if ($p -eq "mux_launch.sh") { return $true }

    # Runtime files/directories used by the app
    $prefixes = @(
        "helpers/",
        "lib/",
        "scenes/",
        "scripts/",
        "templates/",
        "assets/",
        "static/",
        "bin/",
        "data/",
        "sample/",
        "logs/"
    )
    foreach ($prefix in $prefixes) {
        if ($p.StartsWith($prefix)) { return $true }
    }

    $rootFiles = @(
        "conf.lua",
        "globals.lua",
        "main.lua",
        "config.ini.example",
        "skyscraper_config.ini.example",
        "theme.ini",
        "theme_light.ini",
        "theme_classic.ini",
        "theme_light_classic.ini"
    )
    if ($rootFiles -contains $p) { return $true }

    return $false
}

function Get-ChangedFiles {
    param([string]$RepoRoot)

    $results = New-Object System.Collections.Generic.HashSet[string]

    $unstaged = git -C $RepoRoot diff --name-only
    $staged = git -C $RepoRoot diff --cached --name-only
    $untracked = git -C $RepoRoot ls-files --others --exclude-standard

    foreach ($entry in @($unstaged + $staged + $untracked)) {
        if (-not [string]::IsNullOrWhiteSpace($entry)) {
            $null = $results.Add((To-UnixPath -Path $entry))
        }
    }

    return @($results)
}

function Get-AllRuntimeFiles {
    param([string]$RepoRoot)

    $all = New-Object System.Collections.Generic.List[string]

    $runtimeDirs = @(
        "helpers", "lib", "scenes", "scripts", "templates", "assets", "static", "bin", "data", "sample", "logs"
    )
    foreach ($dir in $runtimeDirs) {
        $full = Join-Path $RepoRoot $dir
        if (Test-Path -LiteralPath $full -PathType Container) {
            Get-ChildItem -LiteralPath $full -Recurse -File | ForEach-Object {
                $rel = $_.FullName.Substring($RepoRoot.Length).TrimStart("\", "/")
                $all.Add((To-UnixPath -Path $rel))
            }
        }
    }

    $rootFiles = @(
        "mux_launch.sh",
        "conf.lua",
        "globals.lua",
        "main.lua",
        "config.ini.example",
        "skyscraper_config.ini.example",
        "theme.ini",
        "theme_light.ini",
        "theme_classic.ini",
        "theme_light_classic.ini"
    )
    foreach ($file in $rootFiles) {
        $full = Join-Path $RepoRoot $file
        if (Test-Path -LiteralPath $full -PathType Leaf) {
            $all.Add((To-UnixPath -Path $file))
        }
    }

    return $all | Sort-Object -Unique
}

function Invoke-RemoteCommand {
    param(
        [Parameter(Mandatory = $true)][string]$Command
    )
    if ($UsePuttyAuth) {
        $plinkArgs = @("-batch", "-P", $Port, "-l", $User, "-pw", $Password)
        if (-not [string]::IsNullOrWhiteSpace($HostKey)) {
            $plinkArgs += @("-hostkey", $HostKey)
        }
        $plinkArgs += @($Ip, $Command)
        & plink @plinkArgs
    } else {
        & ssh -p $Port "$User@$Ip" $Command
    }
}

function Copy-RemoteFile {
    param(
        [Parameter(Mandatory = $true)][string]$LocalPath,
        [Parameter(Mandatory = $true)][string]$RemotePath
    )
    if ($UsePuttyAuth) {
        $pscpArgs = @("-batch", "-P", $Port, "-l", $User, "-pw", $Password)
        if (-not [string]::IsNullOrWhiteSpace($HostKey)) {
            $pscpArgs += @("-hostkey", $HostKey)
        }
        $pscpArgs += @($LocalPath, "${Ip}:$RemotePath")
        & pscp @pscpArgs
    } else {
        & scp -P $Port $LocalPath "${User}@${Ip}:$RemotePath"
    }
}

function Sync-BySingleArchive {
    param(
        [Parameter(Mandatory = $true)][string[]]$RelFiles,
        [Parameter(Mandatory = $true)][string]$RepoRoot
    )

    $guid = [Guid]::NewGuid().ToString("N")
    $stageRoot = Join-Path $env:TEMP ("scrappy_sync_" + $guid)
    $archivePath = Join-Path $env:TEMP ("scrappy_sync_" + $guid + ".tar")
    $remoteArchive = "/tmp/scrappy_dev_sync.tar"

    try {
        New-Item -ItemType Directory -Force -Path $stageRoot | Out-Null

        foreach ($rel in $RelFiles) {
            $localPath = Join-Path $RepoRoot ($rel -replace "/", [IO.Path]::DirectorySeparatorChar)
            if (-not (Test-Path -LiteralPath $localPath -PathType Leaf)) {
                continue
            }

            $stageRel = if ($rel -eq "mux_launch.sh") {
                "mux_launch.sh"
            } else {
                ".scrappy/$rel"
            }

            $destPath = Join-Path $stageRoot ($stageRel -replace "/", [IO.Path]::DirectorySeparatorChar)
            $destDir = Split-Path -Parent $destPath
            New-Item -ItemType Directory -Force -Path $destDir | Out-Null
            Copy-Item -LiteralPath $localPath -Destination $destPath -Force
        }

        # Build one tarball for a single upload
        & tar -cf $archivePath -C $stageRoot .
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to create sync archive."
        }

        # Upload archive
        Copy-RemoteFile -LocalPath $archivePath -RemotePath $remoteArchive
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to upload sync archive."
        }

        # Extract remotely into app root
        Invoke-RemoteCommand -Command "mkdir -p '$RemoteRoot' && tar -xf '$remoteArchive' -C '$RemoteRoot' && rm -f '$remoteArchive'"
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to extract sync archive on device."
        }
    }
    finally {
        if (Test-Path -LiteralPath $stageRoot) {
            Remove-Item -LiteralPath $stageRoot -Recurse -Force
        }
        if (Test-Path -LiteralPath $archivePath) {
            Remove-Item -LiteralPath $archivePath -Force
        }
    }
}

Write-Host "Project: $ProjectRoot"
Write-Host "Device:  $User@$Ip`:$Port"
Write-Host "Target:  $RemoteRoot"
Write-Host "Auth:    $(if ($UsePuttyAuth) { 'password (PuTTY)' } else { 'ssh/scp (key or prompt)' })"
if ($UsePuttyAuth -and [string]::IsNullOrWhiteSpace($HostKey)) {
    Write-Host "Tip: add -HostKey `<fingerprint>` on first run to avoid host key cache prompts in batch mode." -ForegroundColor Yellow
}
if ($PasswordFallback) {
    Write-Host "Note: -Password ignored because PuTTY tools are unavailable." -ForegroundColor Yellow
}

$candidateFiles = if ($All) {
    Write-Host "Mode: full runtime sync"
    Get-AllRuntimeFiles -RepoRoot $ProjectRoot
} else {
    Write-Host "Mode: changed files sync"
    Get-ChangedFiles -RepoRoot $ProjectRoot
}

$filesToSync = @()
$skipped = @()

foreach ($rel in $candidateFiles) {
    if (Is-RuntimePath -RelPath $rel) {
        $localPath = Join-Path $ProjectRoot ($rel -replace "/", [IO.Path]::DirectorySeparatorChar)
        if (Test-Path -LiteralPath $localPath -PathType Leaf) {
            $filesToSync += $rel
        }
    } else {
        $skipped += $rel
    }
}

if ($filesToSync.Count -eq 0) {
    Write-Host "No runtime files to sync."
    if ($skipped.Count -gt 0) {
        Write-Host "Skipped non-runtime paths:"
        $skipped | Sort-Object | ForEach-Object { Write-Host "  - $_" }
    }
    exit 0
}

Write-Host ""
Write-Host ("Will sync {0} file(s):" -f $filesToSync.Count)
$filesToSync | Sort-Object | ForEach-Object { Write-Host "  - $_" }

if ($DryRun) {
    Write-Host ""
    Write-Host "Dry-run only. No files were copied."
    exit 0
}

if ($PerFile) {
    Write-Host "Transfer: per-file mode"
    foreach ($rel in ($filesToSync | Sort-Object)) {
        $localPath = Join-Path $ProjectRoot ($rel -replace "/", [IO.Path]::DirectorySeparatorChar)
        $remotePath = if ($rel -eq "mux_launch.sh") {
            "$RemoteRoot/mux_launch.sh"
        } else {
            "$RemoteRoot/.scrappy/$rel"
        }
        $remoteDir = $remotePath.Substring(0, $remotePath.LastIndexOf("/"))

        Invoke-RemoteCommand -Command "mkdir -p `"$remoteDir`""
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to create remote directory: $remoteDir"
        }

        Copy-RemoteFile -LocalPath $localPath -RemotePath $remotePath
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to copy file: $rel"
        }
    }
} else {
    Write-Host "Transfer: archive mode (single upload)"
    Sync-BySingleArchive -RelFiles ($filesToSync | Sort-Object) -RepoRoot $ProjectRoot
}

if ($filesToSync -contains "mux_launch.sh") {
    Write-Host ""
    Write-Host "Normalizing mux_launch.sh line endings on device..."
    Invoke-RemoteCommand -Command "dos2unix '$RemoteRoot/mux_launch.sh' >/dev/null 2>&1 || true"
}

Write-Host ""
Write-Host "Sync complete."
Write-Host "Now relaunch Scrappy from Applications on the device."

if ($TailLogs) {
    Write-Host ""
    Write-Host "Tailing latest Scrappy log (Ctrl+C to stop)..."
    $tailCmd = 'latest=$(ls -t {0}/.scrappy/logs/*.log 2>/dev/null | head -n 1); [ -n "$latest" ] && tail -f "$latest" || echo "No log files found yet."' -f $RemoteRoot
    Invoke-RemoteCommand -Command $tailCmd
}
