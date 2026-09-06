# 指针助手:把电脑上的文件夹/单个文件"挂"进本网盘(符号链接,不复制)
# 用法:双击同目录 指针助手.bat(自动以管理员运行本脚本)。
# 数据目录 = 本脚本所在"管理工具"的上一级(即网盘根,含 公共/私人)。
$ErrorActionPreference = 'Continue'
$tools = $PSScriptRoot
$data  = Split-Path $tools -Parent
$pub   = Join-Path $data ([string][char]0x516C + [char]0x5171)  # 公共
$pri   = Join-Path $data ([string][char]0x79C1 + [char]0x4EBA)  # 私人
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

function All-Links {
    Get-ChildItem -Path $pub, $pri -Recurse -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.LinkType }
}
function Write-Links {
    $links = @(All-Links)
    if ($links.Count -eq 0) { Write-Host '  (还没有挂载任何指针)' -ForegroundColor DarkGray; return }
    for ($i = 0; $i -lt $links.Count; $i++) {
        Write-Host ("  [{0}] {1}  ->  {2}" -f ($i + 1), $links[$i].FullName, $links[$i].Target)
    }
}
function Do-Mount {
    Write-Host ''
    $src = Read-Host ' 要挂载的源路径(文件夹 或 单个文件,如 D:\Video\狂飙\01.mp4)'
    $src = $src.Trim().Trim('"')
    if (-not (Test-Path $src)) { Write-Host '  ✗ 该路径不存在' -ForegroundColor Red; return }
    $isDir = (Get-Item $src).PSIsContainer
    Write-Host ('  源类型: ' + $(if ($isDir) { '文件夹' } else { '文件' }))
    $which = Read-Host '  挂到 1=公共(guest可看) 2=私人(仅自己) [1]'
    $base = if ($which -eq '2') { $pri } else { $pub }
    $sub = (Read-Host '  目标子文件夹(可多级,如 nihao\我好;留空=直接放该区)').Trim()
    $targetDir = if ($sub -eq '') { $base } else { $t = Join-Path $base $sub; [System.IO.Directory]::CreateDirectory($t) | Out-Null; $t }
    $defName = Split-Path $src -Leaf
    $name = (Read-Host "  在网盘里显示的名字(回车默认 `"$defName`")").Trim()
    if ($name -eq '') { $name = $defName }
    $link = Join-Path $targetDir $name
    if (Test-Path $link) { Write-Host '  ✗ 该位置已存在同名项' -ForegroundColor Red; return }
    try {
        New-Item -ItemType SymbolicLink -Path $link -Target $src -ErrorAction Stop | Out-Null
        Write-Host "  ✓ 已挂载:`n    $link  ->  $src" -ForegroundColor Green
    } catch {
        Write-Host ('  ✗ 失败: ' + $_.Exception.Message) -ForegroundColor Red
        if (-not $isAdmin) { Write-Host '  提示:创建符号链接需要管理员(请用 指针助手.bat 打开)' -ForegroundColor Yellow }
    }
}
function Do-Delete {
    Write-Host ''
    $links = @(All-Links)
    if ($links.Count -eq 0) { Write-Host '  (没有可删除的指针)'; return }
    Write-Links
    $sel = Read-Host '  输入要删除的编号(多个用逗号,如 1,3;回车取消)'
    if ($sel.Trim() -eq '') { return }
    foreach ($n in $sel.Split(',')) {
        $n = $n.Trim()
        if ($n -match '^\d+$') {
            $i = [int]$n - 1
            if ($i -ge 0 -and $i -lt $links.Count) {
                $lnk = $links[$i]
                $srcTarget = $lnk.Target
                Remove-Item -LiteralPath $lnk.FullName -Force -ErrorAction SilentlyContinue
                Write-Host ("  已删除指针: " + $lnk.FullName + " (源文件未动: " + $srcTarget + ")")
            }
        }
    }
}
do {
    Clear-Host
    Write-Host ''
    Write-Host '  ══════════════════════════════════════'
    Write-Host '    指针助手 · 把别的文件/文件夹挂进网盘'
    Write-Host '    (符号链接,不复制数据;需管理员)'
    Write-Host '  ══════════════════════════════════════'
    Write-Host '  1  挂载(文件夹/单个文件)'
    Write-Host '  2  删除已挂载的指针  (会先列出,供你挑选)'
    Write-Host '  3  列出已挂载'
    Write-Host '  0  退出'
    $c = Read-Host '  请选择'
    switch ($c) {
        '1' { Do-Mount }
        '2' { Do-Delete }
        '3' { Write-Host ''; Write-Links }
    }
    if ($c -ne '0') { Write-Host ''; Read-Host '  回车返回主菜单' }
} while ($c -ne '0')
Write-Host '  再见'
