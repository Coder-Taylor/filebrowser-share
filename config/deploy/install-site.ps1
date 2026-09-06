<#
install-site.ps1 - 一键把当前文件夹变成你的专属网盘(给"朋友/站点主人"用)

用法(双击或右键-用 PowerShell 运行;会自动请求管理员):
  它会问你: ① 47 服务器地址  ② 站主发给你的邀请码  ③ 放网盘内容的文件夹
  之后全自动:47 帮你建站并分配端口 -> 本文件夹生成完整网盘(公共/私人 + 启动/停止/
  指针助手/说明),服务自动注册开机自启。

运行前提:本脚本与 filebrowser.exe、frpc.exe、nssm.exe(或 nssm\nssm.exe)在同一个目录。
(站主给的安装包已含全部程序。)
#>
param([string]$Invite = "", [string]$ServerAddr = "", [string]$DataDir = "", [string]$AdminPassword = "", [switch]$EnablePointer)
$ErrorActionPreference = 'Continue'
$PUB = [string][char]0x516C + [char]0x5171   # 公共
$PRI = [string][char]0x79C1 + [char]0x4EBA   # 私人
$PANEL = "_面板"

function Relaunch-Elevated {
    # Re-run the same interactive script elevated; no params are forwarded
    # (everything is collected interactively inside the elevated window).
    Start-Process powershell -Verb RunAs -ArgumentList @(
        '-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$($MyInvocation.MyCommand.Path)`""
    )
}
function Die($m){ Write-Host "ERROR: $m" -ForegroundColor Red; if (-not $env:PAN_NOPAUSE) { Read-Host '回车退出' }; exit 1 }
function Ok($m){ Write-Host "OK: $m" -ForegroundColor Green }

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host '需要管理员权限,即将弹出 UAC,请点"是"...' -ForegroundColor Yellow
    Relaunch-Elevated; exit
}

# ---------- 交互收集 ----------
if ($ServerAddr -eq '') { $ServerAddr = Read-Host '47 服务器地址(站主给你,形如 1.2.3.4)' }
if ($ServerAddr -eq '') { Die '未输入服务器地址' }
if ($Invite -eq '')     { $Invite = Read-Host '输入站主发的邀请码(形如 PAN-XXXXXXXX)' }
if ($Invite -eq '')     { Die '未输入邀请码' }
if ($DataDir -eq '')    {
    $d = Read-Host "放网盘内容的文件夹(可留空 = 本目录下的 我的网盘)"
    $DataDir = if ($d -eq '') { Join-Path $PSScriptRoot '我的网盘' } else { $d }
}
if ($AdminPassword -eq '') {
    $a = Read-Host '设置你的网盘管理员密码(≥12位;会显示)'
    if ($a.Length -lt 12) { Die '密码需 ≥12 位' }
    $AdminPassword = $a
}
# 指针默认开启(之后用网盘文件夹里的 指针助手.bat 挂载具体文件夹;无需在安装时选择)
$script:EnablePointer = $true

# ---------- 兑换邀请码(47 自动建站) ----------
Write-Host "正在向 $ServerAddr 兑换邀请码并自动建站..."
$body = @{ invite = $Invite } | ConvertTo-Json
try {
    $resp = Invoke-RestMethod -Uri "http://${ServerAddr}:8089/api/invite/redeem" -Method Post -ContentType 'application/json' -Body $body -TimeoutSec 60
} catch { Die "兑换失败: $($_.Exception.Message) —— 检查服务器地址/邀请码是否有效" }
if (-not $resp.ok) { Die "兑换失败: $($resp.error)" }
$siteName = $resp.siteName; $httpPort = [int]$resp.httpPort
$remotePort = [int]$resp.remotePort; $serverPort = [int]$resp.serverPort
$token = $resp.token
Ok "站点 $siteName 已创建 —— 你的网盘地址 http://${ServerAddr}:$httpPort"

# ---------- 定位程序 ----------
function FindExe($n){
    $c = Join-Path $PSScriptRoot $n;     if (Test-Path $c) { return $c }
    $c = Join-Path $PSScriptRoot "nssm\$n"; if (Test-Path $c) { return $c }
    Die "缺少 $n —— 请确认安装包完整(和本脚本同目录)"
}
$fbExe0 = FindExe 'filebrowser.exe'; $frpcExe0 = FindExe 'frpc.exe'; $nssmExe0 = FindExe 'nssm.exe'

# ---------- 建文件夹结构 ----------
New-Item -ItemType Directory -Force $DataDir | Out-Null
New-Item -ItemType Directory -Force (Join-Path $DataDir $PUB), (Join-Path $DataDir $PRI) | Out-Null
$panel = Join-Path $DataDir $PANEL
New-Item -ItemType Directory -Force $panel, (Join-Path $panel 'nssm'), (Join-Path $panel 'logs') | Out-Null
# 拷贝程序进 _面板(自足,可随文件夹整体搬走)
Copy-Item $fbExe0  (Join-Path $panel 'filebrowser.exe')  -Force
Copy-Item $frpcExe0 (Join-Path $panel 'frpc.exe')  -Force
Copy-Item $nssmExe0 (Join-Path $panel 'nssm\nssm.exe') -Force
$fbExe = Join-Path $panel 'filebrowser.exe'; $frpcExe = Join-Path $panel 'frpc.exe'; $nssmExe = Join-Path $panel 'nssm\nssm.exe'

# ---------- 初始化 db ----------
$db = Join-Path $panel "filebrowser.db"
if (-not (Test-Path $db)) { Ok '初始化网盘数据库...'; & $fbExe -d $db config init | Out-Null }
& $fbExe -d $db config set --locale zh-cn --branding.name $siteName | Out-Null
$hasAdmin = (& $fbExe -d $db users ls 2>$null | Out-String) -match '(?m)^\s*\d+\s+admin\s'
if ($hasAdmin) { & $fbExe -d $db users update admin --password $AdminPassword | Out-Null }
else { Push-Location $DataDir; & $fbExe -d $db users add admin $AdminPassword --perm.admin --scope . --locale zh-cn | Out-Null; Pop-Location }
Ok '指针已开启(用文件夹里的 指针助手.bat 可把其他文件夹挂进网盘)...'
& $fbExe -d $db config set --followExternalSymlinks 2>$null | Out-Null

# ---------- 本地空闲端口 ----------
$localPort = 18085
while (Get-NetTCPConnection -LocalPort $localPort -State Listen -ErrorAction SilentlyContinue) { $localPort++ }

# ---------- frpc.toml ----------
$toml = @"
serverAddr = "$ServerAddr"
serverPort = $serverPort
auth.method = "token"
auth.token = "$token"
loginFailExit = false
transport.heartbeatInterval = 10
transport.heartbeatTimeout = 30

[[proxies]]
name = "filebrowser-$siteName"
type = "tcp"
localIP = "127.0.0.1"
localPort = $localPort
remotePort = $remotePort
"@
$frpcCfg = Join-Path $panel 'frpc.toml'
[System.IO.File]::WriteAllText($frpcCfg, $toml, (New-Object System.Text.UTF8Encoding($false)))

# ---------- 注册服务 ----------
$fbSvc = "FB-$siteName"; $frpSvc = "FRP-$siteName"
foreach($s in $fbSvc,$frpSvc){ if (Get-Service $s -ErrorAction SilentlyContinue) { sc.exe delete $s | Out-Null } }
function Nssm($a){ & $nssmExe @a; if ($LASTEXITCODE -ne 0) { Die "nssm $($a -join ' ') failed" } }
$fbArgs = "-r `"$DataDir`" -a 127.0.0.1 -p $localPort -d `"$db`""
Nssm @('install',$fbSvc,$fbExe);  Nssm @('set',$fbSvc,'AppParameters',$fbArgs)
Nssm @('set',$fbSvc,'AppDirectory',$panel); Nssm @('set',$fbSvc,'AppExit','Default','Restart')
Nssm @('set',$fbSvc,'AppRestartDelay','5000'); Nssm @('set',$fbSvc,'Start','SERVICE_AUTO_START')
Nssm @('install',$frpSvc,$frpcExe); Nssm @('set',$frpSvc,'AppParameters',"-c `"$frpcCfg`"")
Nssm @('set',$frpSvc,'AppDirectory',$panel); Nssm @('set',$frpSvc,'AppExit','Default','Restart')
Nssm @('set',$frpSvc,'AppRestartDelay','5000'); Nssm @('set',$frpSvc,'Start','SERVICE_AUTO_START')
Nssm @('start',$fbSvc); Nssm @('start',$frpSvc)
Start-Sleep -Seconds 5

# ---------- 管理工具子目录:启停/状态脚本(模板复制 + 占位替换) ----------
$toolsDir = Join-Path $DataDir '管理工具'
New-Item -ItemType Directory -Force $toolsDir | Out-Null
$tmpl = Join-Path $PSScriptRoot 'pan-tools'
$gbkW = [System.Text.Encoding]::GetEncoding(936)
$siteUrl = "http://$ServerAddr`:$httpPort"
foreach ($f in '启动网盘.bat','停止网盘.bat','查看状态.bat') {
    $t = [System.IO.File]::ReadAllText((Join-Path $tmpl $f))
    $t = $t.Replace('__FB__', $fbSvc).Replace('__FRP__', $frpSvc).Replace('__URL__', $siteUrl)
    $t = (($t -replace "`r`n", "`n") -replace "`n", "`r`n")
    [System.IO.File]::WriteAllText((Join-Path $toolsDir $f), $t, $gbkW)
}
$pubFull = Join-Path $DataDir $PUB; $priFull = Join-Path $DataDir $PRI

# ---------- 指针助手(复制模板;支持挂载 文件/文件夹、可定位子目录与名称、可删除,放 管理工具) ----------
Copy-Item (Join-Path $tmpl '指针助手.bat')  $toolsDir -Force
Copy-Item (Join-Path $tmpl '指针助手.ps1')  $toolsDir -Force

# ---------- 使用说明 ----------
@"
【我的专属网盘】 $siteName
访问地址: http://$ServerAddr`:$httpPort
管理员账号: admin    密码: $AdminPassword
(请记牢;忘了可用 _面板\filebrowser.exe users update admin --password 新密码 重置)

目录说明
  $pubFull   ← 往这里放文件,朋友(guest)就能下载
  $priFull   ← 只你自己看
  _面板\     ← 程序与配置(别删,guest 看不到)
常用
  启动网盘.bat / 停止网盘.bat / 查看状态.bat   ← 一键启停
  指针助手.bat    ← 把别的文件夹挂进网盘(不复制)
给朋友开号:登录网盘 → 左下角设置(齿轮)→ 用户 → 新增;
           用户名任意 / 密码≥12位 / 目录范围填 /公共 / 只勾"下载"
提示
  只有你电脑开机且网盘服务在跑,朋友才访问得到
  大文件断点续传/自动重连都已内置;文件单个放,别用文件夹打包下载大件
  指针(符号链接)放公共 = guest 也能看;想只给自己看就挂到私人
"@ | Set-Content (Join-Path $DataDir '使用说明.txt') -Encoding Default

# ---------- post-fix all generated .bat: CRLF line endings + drop 'chcp 65001' (cmd reads GBK) ----------
$gbk = [System.Text.Encoding]::GetEncoding(936)
Get-ChildItem $DataDir -Filter '*.bat' -Recurse | ForEach-Object {
    $c = [System.IO.File]::ReadAllText($_.FullName, $gbk)
    $c = $c -replace '(?i)^chcp 65001 >nul[ \t]*\r?\n', ''
    $c = (($c -replace "`r`n", "`n") -replace "`n", "`r`n")
    [System.IO.File]::WriteAllText($_.FullName, $c, $gbk)
}

# ---------- done ----------
Ok "网盘装好了: $siteName"
Write-Host ''
Write-Host "访问: http://$ServerAddr`:$httpPort   账号 admin / $AdminPassword" -ForegroundColor Cyan
Write-Host "服务: $fbSvc + $frpSvc(开机自启,断线自愈)"
Write-Host "文件夹: $DataDir"
if (-not $env:PAN_NOPAUSE) { Read-Host '回车结束' }
