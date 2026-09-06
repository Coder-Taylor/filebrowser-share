<#
deploy-site.ps1 - one-key deploy of an independent FileBrowser site for one terminal
(part of the multi-site "pan" platform; server side uses pan-ctl add-site on the 47)

Runs on a Windows machine that hosts ONE site (its own FileBrowser + frpc).
Creates an isolated instance: own db, own admin, own tunnel, auto-start services.
Credentials (ServerAddr/ServerPort/RemotePort/Token) come from the platform owner
via `pan-ctl add-site <name>` on the 47 - share those privately with the site admin.

Usage (normal user is fine; script self-elevates for service install):
  powershell -ExecutionPolicy Bypass -File deploy-site.ps1 `
      -SiteName demo -ServerAddr <47ip> -ServerPort 7002 -RemotePort 8092 `
      -Token <token> -BinDir D:\Tools\fbwin -AdminPassword YourPw -EnablePointer

BinDir must contain filebrowser.exe, frpc.exe and nssm.exe (or nssm\nssm.exe).
Compatible with Windows PowerShell 5.1 (ASCII source, no fancy syntax).
#>
param(
    [Parameter(Mandatory=$true)][string]$SiteName,
    [Parameter(Mandatory=$true)][string]$ServerAddr,
    [Parameter(Mandatory=$true)][int]$ServerPort,
    [Parameter(Mandatory=$true)][int]$RemotePort,
    [Parameter(Mandatory=$true)][string]$Token,
    [string]$BinDir = $PSScriptRoot,
    [string]$DataDir = "",
    [string]$AdminPassword = "",
    [switch]$EnablePointer,
    [string]$BrandName = ""
)
# NOTE: keep 'Continue' - filebrowser writes routine info to stderr, which
# PowerShell 5.1 would turn into a terminating error under 'Stop'.
$ErrorActionPreference = 'Continue'

# Chinese dir names built from code points (keep source ASCII for PS 5.1)
$PUB = [string][char]0x516C + [char]0x5171   # GongGong (public)
$PRI = [string][char]0x79C1 + [char]0x4EBA   # SiRen   (private)

# ---------- re-launch elevated, forwarding all params ----------
function Relaunch-Elevated {
    $q = { param($s) if ($s -match '[\s"]') { '"' + ($s -replace '"','\"') + '"' } else { $s } }
    $al = @('-ExecutionPolicy','Bypass','-File',"`"$($MyInvocation.MyCommand.Path)`"")
    foreach ($k in 'SiteName','ServerAddr','ServerPort','RemotePort','Token','BinDir','DataDir','AdminPassword','BrandName') {
        $g = Get-Variable -Name $k -ErrorAction SilentlyContinue
        if ($g -and $g.Value) { $al += ("-" + $k); $al += (& $q ([string]$g.Value)) }
    }
    if ($EnablePointer) { $al += '-EnablePointer' }
    Start-Process powershell -Verb RunAs -ArgumentList $al
}
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host 'Requesting admin rights (accept the UAC prompt)...' -ForegroundColor Yellow
    Relaunch-Elevated
    exit
}
# transcript so the owner/installer can verify (even when running elevated)
$trLog = Join-Path $BinDir "deploy-$SiteName.log"
Start-Transcript -Path $trLog -Force | Out-Null
function Die($m){ Write-Host "ERROR: $m" -ForegroundColor Red; Stop-Transcript | Out-Null; if (-not $env:PAN_NOPAUSE) { Read-Host 'Press Enter to exit' }; exit 1 }
function Ok($m){ Write-Host "OK: $m" -ForegroundColor Green }
function FindExe($name){
    $c = Join-Path $BinDir $name;         if (Test-Path $c) { return $c }
    $c = Join-Path $BinDir "nssm\$name";  if (Test-Path $c) { return $c }
    Die "cannot find $name under BinDir '$BinDir' (need filebrowser.exe, frpc.exe, nssm.exe)"
}

# ---------- validate ----------
if ($SiteName -notmatch '^[A-Za-z0-9-]+$') { Die 'SiteName: only letters, digits, hyphen' }
$fbExe   = FindExe 'filebrowser.exe'
$frpcExe = FindExe 'frpc.exe'
$nssmExe = FindExe 'nssm.exe'
if ($DataDir -eq '') { $DataDir = Join-Path $BinDir "data-$SiteName" }
if ($BrandName -eq '') { $BrandName = $SiteName }
$fbSvc = "FB-$SiteName"; $frpSvc = "FRP-$SiteName"
if (Get-Service $fbSvc,$frpSvc -ErrorAction SilentlyContinue) { Die "services $fbSvc/$frpSvc already exist - site already deployed?" }

# pick a free LOCAL port for this site's filebrowser (multiple sites can share one BinDir)
$localPort = 18085
while (Get-NetTCPConnection -LocalPort $localPort -State Listen -ErrorAction SilentlyContinue) { $localPort++ }

# ---------- dirs & db ----------
New-Item -ItemType Directory -Force $DataDir | Out-Null
New-Item -ItemType Directory -Force (Join-Path $DataDir $PUB) | Out-Null
New-Item -ItemType Directory -Force (Join-Path $DataDir $PRI) | Out-Null
$db = Join-Path $BinDir "filebrowser-$SiteName.db"
$logDir = Join-Path $BinDir 'logs'; New-Item -ItemType Directory -Force $logDir | Out-Null

# generate password first (needed when creating the admin)
if ($AdminPassword -eq '') {
    $chars = 'abcdefghjkmnpqrstuvwxyzABCDEFGHJKMNPQRSTUVWXYZ23456789'
    $AdminPassword = -join (1..14 | ForEach-Object { $chars[(Get-Random -Maximum $chars.Length)] })
}
# init db if missing (FileBrowser 2.63 requires an explicit config init)
if (-not (Test-Path $db)) {
    Ok 'initializing filebrowser database...'
    & $fbExe -d $db config init | Out-Null
    if ($LASTEXITCODE -ne 0) { Die 'filebrowser config init failed' }
}
& $fbExe -d $db config set --locale zh-cn --branding.name $BrandName | Out-Null
# ensure the site admin exists with our password
$hasAdmin = (& $fbExe -d $db users ls 2>$null | Out-String) -match '(?m)^\s*\d+\s+admin\s'
if ($hasAdmin) {
    & $fbExe -d $db users update admin --password $AdminPassword | Out-Null
} else {
    & $fbExe -d $db users add admin $AdminPassword --perm.admin --scope . --locale zh-cn | Out-Null
}
if ($EnablePointer) {
    Ok 'enabling external-symlink pointer support (junction folders)...'
    & $fbExe -d $db config set --followExternalSymlinks 2>$null | Out-Null
}

# ---------- frpc.toml (UTF-8 without BOM) ----------
$toml = @"
serverAddr = "$ServerAddr"
serverPort = $ServerPort
auth.method = "token"
auth.token = "$Token"
loginFailExit = false
transport.heartbeatInterval = 10
transport.heartbeatTimeout = 30

[[proxies]]
name = "filebrowser-$SiteName"
type = "tcp"
localIP = "127.0.0.1"
localPort = $localPort
remotePort = $RemotePort
"@
$frpcCfg = Join-Path $BinDir "frpc-$SiteName.toml"
[System.IO.File]::WriteAllText($frpcCfg, $toml, (New-Object System.Text.UTF8Encoding($false)))

# ---------- register services ----------
function Nssm($a){ & $nssmExe @a; if ($LASTEXITCODE -ne 0) { Die "nssm $($a -join ' ') failed" } }
$fbArgs = "-r `"$DataDir`" -a 127.0.0.1 -p $localPort -d `"$db`""
Nssm @('install',$fbSvc,$fbExe)
Nssm @('set',$fbSvc,'AppParameters',$fbArgs)
Nssm @('set',$fbSvc,'AppDirectory',$BinDir)
Nssm @('set',$fbSvc,'AppStdout',(Join-Path $logDir "$SiteName-fb.out.log"))
Nssm @('set',$fbSvc,'AppStderr',(Join-Path $logDir "$SiteName-fb.err.log"))
Nssm @('set',$fbSvc,'AppExit','Default','Restart')
Nssm @('set',$fbSvc,'AppRestartDelay','5000')
Nssm @('set',$fbSvc,'Start','SERVICE_AUTO_START')

Nssm @('install',$frpSvc,$frpcExe)
Nssm @('set',$frpSvc,'AppParameters',"-c `"$frpcCfg`"")
Nssm @('set',$frpSvc,'AppDirectory',$BinDir)
Nssm @('set',$frpSvc,'AppStdout',(Join-Path $logDir "$SiteName-frp.out.log"))
Nssm @('set',$frpSvc,'AppStderr',(Join-Path $logDir "$SiteName-frp.err.log"))
Nssm @('set',$frpSvc,'AppExit','Default','Restart')
Nssm @('set',$frpSvc,'AppRestartDelay','5000')
Nssm @('set',$frpSvc,'Start','SERVICE_AUTO_START')

Nssm @('start',$fbSvc)
Nssm @('start',$frpSvc)
Start-Sleep -Seconds 5

# ---------- done ----------
Ok "site '$SiteName' deployed."
Write-Host ''
Write-Host "Services          : $fbSvc / $frpSvc (auto start on boot, auto reconnect)" -ForegroundColor Cyan
Write-Host "Public URL        : http://$ServerAddr/  (ask owner which port/path belongs to this site)" -ForegroundColor Cyan
Write-Host "Admin account     : admin"
Write-Host "Admin password    : $AdminPassword" -ForegroundColor Yellow
Write-Host "Data root         : $DataDir"
Write-Host "Share folder      : $DataDir\$PUB   (files placed here are visible to guests you create)"
Write-Host "Private folder    : $DataDir\$PRI"
if ($EnablePointer) {
    Write-Host 'Pointer(junction) is ON: see docs/06 for adding external folders safely.' -ForegroundColor DarkYellow
}
Write-Host ''
Write-Host 'IMPORTANT: write the admin password down now.' -ForegroundColor Yellow
Stop-Transcript | Out-Null
if (-not $env:PAN_NOPAUSE) { Read-Host 'Press Enter to finish' }
