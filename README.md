# FileBrowser 共享网盘

> 把本地大文件（4K 电影、老友记全季、软件包等）分享给朋友的完整方案。
> 2026-09-06 起:**FileBrowser 主服务跑在本地 Windows(E:\NetDist 当仓库),云服务器(47)只留作公网入口(frps + nginx + fbproxy + frp 隧道)**,详见 `docs/05-本地存储与frp穿透.md`。
> 本项目是可复现的配置存档 + 部署文档 + 操作日志，**不含任何真实密码 / 服务器 IP / 个人信息**。

## 它能做什么

- 网页网盘，浏览器直接上传 / 下载 / 在线看文件
- **强制简体中文**（连登录前的页面也是中文，见 `docs/03-中文界面补丁.md`）
- **公私隔离**：`公共/` 目录对 guest 只读开放，`私人/` 只有自己能看到（scope 隔离，越权访问返回 404）
- 登录时用户名 / 密码**自动去掉首尾空格**（防止手滑复制多打空格）
- **单个文件 = 源格式下载**（不压缩）；**文件夹 / 多选 = 打包成 zip** 后下载（无损）
- **单文件下载支持 HTTP Range 断点续传**（实测 206），网络断了可恢复，配合下载工具可全自动续传
- 容量受本地磁盘限制（E:\NetDist ≈ 537G），不再受云盘 40G 约束
- **多站点平台**：站主(47)用 `pan-ctl` 接入多台终端，每台终端一个完全隔离的网盘(独立 frps/token/db)，见 `docs/06-多站点平台.md`
- **指针功能**：开启后可用符号链接把电脑其他位置的文件夹"挂"进网盘浏览/下载，无需复制
- **一键部署**：`config/deploy/deploy-site.ps1` 让任意 Windows 一键搭好一个站点
- **朋友自助安装**：owner 在网页门户发一次性邀请码 → 朋友双击 `install-site.ps1` 输码选文件夹，自动生成完整网盘（见 `docs/07`）
- **owner 网页门户**：SSH 隧道访问 `localhost:9200`，看所有站点/发邀请/停启删（见 `docs/07`）

## 技术栈

| 组件 | 位置 | 说明 |
|------|------|------|
| FileBrowser 2.63.23 | 每台终端 Windows | 网页文件管理器（每站独立 db，NSSM 服务自动启动） |
| frpc 0.71.0 | 每台终端 Windows | 隧道客户端（`loginFailExit=false` 断线自愈） |
| frps 0.71.0 | 47 | 隧道服务端（站1 legacy 走 443；多站 `frps-<站>` 独立端口/token，systemd） |
| nginx | 47 | 对外反代：站1 8081，各站 8080+N |
| fbproxy.py | 47 | 登录空格过滤器（参数化，每站一个实例） |
| pan-ctl | 47 | 站主编排工具（建/停/删站、重置 token；`config/deploy/pan-ctl`） |
| deploy-site.ps1 | 仓库 | 客户端一键部署脚本 |

> ⚠️ FileBrowser 官方已于 2026-09-01 归档停止维护。当前版本可用但不再更新；如需长期维护可考虑社区 fork（本项目锁定 2.63.23，与 i18n 补丁 hash 耦合，升级需重做补丁）。
> ⚠️ 数据通过隧道流经 47 但不落盘；文件大小只受本地磁盘限制，与 47 无关。

## 目录结构（网盘内，本地 E:\NetDist）

```
E:\NetDist（FileBrowser 根 ≈537G）
├── 公共/                  ← guest 只读可见
│   ├── 使用说明.txt
│   ├── Software installation package/
│   └── 老友记/              (全季 4K,每集 2~3G 单文件)
└── 私人/                  ← 仅 admin
```

## 账号模型

| 账号  | 权限范围 | 能力         | 用途         |
|-------|----------|--------------|--------------|
| admin | `/`（全部） | 全部（含上传/整理） | 你自己     |
| guest | `/公共`   | 只读         | 分享给朋友 |

> 真实密码保存在服务器本地凭据文件 / 密码管理器，**绝不写入本仓库**。

## 仓库结构

```
├── README.md
├── CHANGELOG.md                  # 变更日志
├── records/                      # 操作记录（做了什么，脱敏）
├── docs/
│   ├── 01-架构说明.md            # 当前拓扑（本地存储 + frp）
│   ├── 02-部署与配置.md          # 47 侧 nginx/fbproxy 部署（FileBrowser 已迁本地，回源改为 8087）
│   ├── 03-中文界面补丁.md
│   ├── 04-大文件上传经验.md      # 历史经验：47 存储时代的分片上传（现已被本地存储取代）
│   ├── 05-本地存储与frp穿透.md   # ★ 2026-09-06 架构：本地 FileBrowser + frp 隧道
│   ├── 06-多站点平台.md          # ★ 站主 + 多终端隔离网盘 + 指针 + 一键部署
│   ├── 07-产品化安装与owner门户.md# ★ 邀请码安装包 + owner 网页门户
│   └── 给朋友的使用说明.md       # 模板（真实密码当面给，不入仓库）
├── config/
│   ├── deploy/
│   │   ├── pan-ctl               # 站主工具模板(部署到 47:/usr/local/bin/pan-ctl)
│   │   ├── pan-web.py            # owner 门户 + 邀请码服务(部署到 47)
│   │   ├── deploy-site.ps1       # 客户端手动部署(Windows)
│   │   └── install-site.ps1      # 客户端自助安装向导(邀请码,UTF-8 BOM)
│   ├── nginx-site.conf           # 47 nginx 反代（回源 8087；多站由 pan-ctl 生成）
│   ├── fbproxy.py                # 登录空格过滤器（参数化: <监听口> <转发口>）
│   ├── frps.toml / frpc.toml     # frps/frpc 配置模板（token 占位）
│   ├── frps.service              # frps systemd 单元
│   ├── filebrowser-windows.txt   # 本地 FileBrowser 运行/NSSM 注册说明
│   ├── filebrowser-docker.txt    # 历史：Docker 挂载 / 端口（已停用）
│   └── filebrowser-users.txt     # 用户 / 权限命令模板
└── 计网实战课/                   # 用本项目学计网：九课 + 课程地图
```

## 发布前检查

- [ ] 全局搜索，确认无 IP、密码、学号等敏感字段
- [ ] 若公开仓库，可用 Gitee / GitHub；国内访问选 Gitee 更稳
- [ ] 授权方式（开源协议）发布前决定

---
*License：发布前待定。*
