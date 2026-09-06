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
    $q = { param($s) if ($s -match '[\s"]') { '"' + ($s -replace '"','\"') + '"' } else { $s } }
    $al = @('-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$($MyInvocation.MyCommand.Path)`"")
    foreach ($k in 'Invite','ServerAddr','DataDir','AdminPassword') {
        $g = Get-Variable -Name $k -ErrorAction SilentlyContinue
        if ($g -and $g.Value) { $al += ("-" + $k); $al += (& $q ([string]$g.Value)) }
    }
    if ($EnablePointer) { $al += '-EnablePointer' }
    Start-Process powershell -Verb RunAs -ArgumentList $al
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

# ---------- 生成启动/停止/状态 bat ----------
$pubFull = Join-Path $DataDir $PUB; $priFull = Join-Path $DataDir $PRI
@"
@echo off
chcp 65001 >nul
net session >nul 2>&1 || (powershell -Command "Start-Process '%~f0' -Verb RunAs" & exit /b)
net start $fbSvc >nul 2>&1
net start $frpSvc >nul 2>&1
echo 网盘已启动。访问 http://$ServerAddr`:$httpPort
pause
"@ | Set-Content (Join-Path $DataDir '启动网盘.bat') -Encoding Default
@"
@echo off
chcp 65001 >nul
net session >nul 2>&1 || (powershell -Command "Start-Process '%~f0' -Verb RunAs" & exit /b)
net stop $fbSvc >nul 2>&1
net stop $frpSvc >nul 2>&1
echo 网盘已停止。
pause
"@ | Set-Content (Join-Path $DataDir '停止网盘.bat') -Encoding Default
@"
@echo off
chcp 65001 >nul
sc query $fbSvc | findstr STATE
sc query $frpSvc | findstr STATE
echo 访问地址: http://$ServerAddr`:$httpPort
pause
"@ | Set-Content (Join-Path $DataDir '查看状态.bat') -Encoding Default

# ---------- 指针助手(ps1 + 薄 bat) ----------
$pubName = $PUB; $priName = $PRI; $dataFull = $DataDir
$helper = @"
`$ErrorActionPreference='Continue'
`$data = '$dataFull'
`$pub = Join-Path `$data '$pubName'; `$pri = Join-Path `$data '$priName'
Write-Host '=== 指针助手:把电脑上别的文件夹"挂"进本网盘(不复制文件)==='
Write-Host "1) 公共(guest 也能看)   2) 私人(只自己看)"
`$c = Read-Host '选 1 或 2'
`$tgt = Read-Host '输入要挂载的完整目录(如 D:\downloads\电影)'
if (-not (Test-Path `$tgt)) { Write-Host '目录不存在'; Read-Host '回车退出'; exit }
`$link = if (`$c -eq '1') { Join-Path `$pub ([IO.Path]::GetFileName(`$tgt.TrimEnd('\'))) } else { Join-Path `$pri ([IO.Path]::GetFileName(`$tgt.TrimEnd('\'))) }
try { New-Item -ItemType SymbolicLink -Path `$link -Target `$tgt -ErrorAction Stop | Out-Null; Write-Host "已挂载: `$link -> `$tgt" -ForegroundColor Green }
catch { Write-Host "失败: `$(`$_.Exception.Message) (符号链接需要管理员或开发者模式,脚本已尽量提权)" -ForegroundColor Red }
Write-Host "--- 本网盘已挂载的指针 ---"
Get-ChildItem `$pub,`$pri -Force -ErrorAction SilentlyContinue | Where-Object { `$_.LinkType } | ForEach-Object { Write-Host ("`$(`$_.FullName) -> `$(`$_.Target)") }
Read-Host '回车退出'
"@
[System.IO.File]::WriteAllText((Join-Path $DataDir '指针助手.ps1'), $helper, (New-Object System.Text.UTF8Encoding($true)))
@"
@echo off
chcp 65001 >nul
powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process powershell -Verb RunAs -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','%~dp0指针助手.ps1'"
"@ | Set-Content (Join-Path $DataDir '指针助手.bat') -Encoding Default

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

# ---------- done ----------
Ok "网盘装好了: $siteName"
Write-Host ''
Write-Host "访问: http://$ServerAddr`:$httpPort   账号 admin / $AdminPassword" -ForegroundColor Cyan
Write-Host "服务: $fbSvc + $frpSvc(开机自启,断线自愈)"
Write-Host "文件夹: $DataDir"
if (-not $env:PAN_NOPAUSE) { Read-Host '回车结束' }
