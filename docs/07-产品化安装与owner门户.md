# 07 · 产品化安装与 owner 门户(2026-09-06 阶段二)

> MVP(每终端独立站 + pan-ctl + deploy-site.ps1)之后的产品化:**朋友拿到一个安装包 + 一行邀请码,双击就在自己文件夹里长出一个完整网盘**;owner 通过网页门户统一看站/发邀请/停启。
> 配套:`config/deploy/install-site.ps1`(客户端向导)、`config/deploy/pan-web.py`(47 上门户 + 邀请码服务)、`config/deploy/pan-ctl`(47 站主 CLI)。

## 两条用户路径

### 朋友(站点主人)——只会"双击"

owner 给朋友两样东西:① **安装包**(一个文件夹:install-site.ps1 + filebrowser.exe + frpc.exe + nssm.exe)② **一行邀请码**(如 `PAN-XXXXXXXX`)。

朋友:双击 install-site.ps1 → 按提示:输入 47 地址 → 粘贴邀请码 → 选一个空文件夹当网盘 → 设 admin 密码 → 回车。
完成后的文件夹(自足,可整体搬走):

```
我的网盘/
├─ 公共/  私人/                 ← 内容根:往 公共 丢文件 = 分享给 guest
├─ _面板/                       ← 程序+db+配置+日志(guest 看不到)
├─ 启动网盘.bat / 停止网盘.bat / 查看状态.bat
├─ 指针助手.bat                 ← 把别的文件夹挂进网盘(指针默认开启)
└─ 使用说明.txt                 ← 地址/账号/给朋友开号方法/指针边界
```

全部自动:兑换邀请码(47 建站分端口)→ 拷贝程序 → 初始化独立 db → 注册服务 `FB-<站>`/`FRP-<站>`(开机自启、断线自愈)→ 生成上述 bat/说明。服务/指针/断点续传全内置,**朋友全程不用懂技术**。

### owner(站主=你)

- 发邀请:登录门户 → "发新邀请码"填站点名(朋友备注)→ 把码发给朋友;
- 看站/停/启/删:门户总览页一个按钮;
- 命令行替代:`pan-ctl ls / stop / start / rm-site / reset-token`。

## 邀请码兑换(全自动分配端口)

```
朋友脚本 → POST http://<SERVER_IP>:8089/api/invite/redeem {"invite":"PAN-xxx"}
    → 47:pan-web 校验(一次性、24h 有效)→ 调 pan-ctl add-site 自动分端口/token
    → 返回 {siteName, httpPort, serverPort, remotePort, token}
    → 脚本据此在本地生成全部配置
```
- 8089 是 nginx 上唯一暴露给公网的端口(只转发 redeem 端点),**门户本身只监听 127.0.0.1**。
- 邀请码二次使用会被拒(实测)。
- 端口分配上限 8 个站点(HTTP 8082..8088;8089 留给 redeem;多了先删站)。

## owner 门户怎么进

门户监听 47 的 127.0.0.1:9100,**不暴露公网**。owner 通过 SSH 隧道访问:
```
ssh -L 9200:127.0.0.1:9100 root@<SERVER_IP>     # 保持这个窗口开着
浏览器打开 http://localhost:9200                # 输入 owner 密码
```
> 可以做一个 `看门户.bat`:`ssh -N -L 9200:127.0.0.1:9100 root@<SERVER_IP> && start http://localhost:9200`
> owner 密码设置/找回:47 上 `pan-web setpass '<新密码>'`(密码以 salt+sha256 存 `/etc/frp-sites/owner.hash`,root 600)。
> **给朋友的安装包在门户里直接下载**:门户页顶部「⬇ 下载 pan-install.zip」(内含 install-site.ps1 + filebrowser/frpc/nssm,约 22MB,存 `/srv/pan-dist/pan-install.zip`)。更新包后覆盖该文件即可。

## 能力边界(重要,README 同)

- owner 统一管的是 **平台站点**(建/停/删/发邀请)和他自己站的 guest;
- **朋友站的 guest 在他自己电脑的 db 里,owner 无法远程增删**(物理边界)——朋友在网页"设置→用户"自己管;
- 每站 admin = 该站主人;每站一个独立 FileBrowser 实例(db/token/端口全隔离)。

## 指针(默认开启)

- 安装默认开启 `followExternalSymlinks`(不再询问);
- 挂载具体文件夹用网盘文件夹里的 **指针助手.bat**(交互:输入目录 → 选 公共/私人 → 建符号链接);
- ⚠️ 必须用**符号链接 mklink /D**(junction 列目录会 500,快捷方式无效);建链接需要管理员或"开发者模式";
- ⚠️ 挂在 `公共/` 的指针 = 该站 guest 也能顺进去看;只自己看的挂 `私人/`。

## 47 端组件

| 组件 | 位置 |
|---|---|
| pan-web | `/usr/local/bin/pan-web`(py)+ systemd `pan-web.service`(127.0.0.1:9100)|
| nginx redeem 口 | `/etc/nginx/sites-available/pan-owner`(listen 8089,只 `/api/invite/redeem`)|
| 邀请码表 | `/etc/frp-sites/invites.conf`(root 600)|
| owner 密码 | `/etc/frp-sites/owner.hash`(root 600)|
| 站点注册表 | `/etc/frp-sites/sites.conf`(pan-ctl 管)|
| 公网 IP | `/etc/frp-sites/public_ip`|

## 给朋友发安装包(站主动作)

把 `config/deploy/install-site.ps1` 连同四个程序(filebrowser.exe、frpc.exe、nssm.exe、`nssm\nssm.exe`)放一个文件夹打成 zip(install-site.ps1 会按 UTF-8 BOM 保存;从本仓库拿时注意编码)。发 zip + 邀请码给朋友即可。程序版本须为 2.63.23(frp 0.71.0),否则 i18n 补丁/隧道不匹配。

## 故障排查

| 现象 | 查 |
|---|---|
| redeem 失败 | 邀请码是否有效/未用过(门户"最近邀请码"看状态);47 时间是否正常(过期判断) |
| 门户打不开 | SSH 隧道是否建立(keep window open);`systemctl status pan-web`;owner 密码是否设置 |
| 朋友装完打不开网址 | 朋友电脑是否开机/服务 Running;`pan-ctl ls` 该站状态 |
| 端口撞车 | pan-ctl 上限 8 站;删站用 `pan-ctl rm-site` |
| 指针列不出 | 确认符号链接(非 junction);朋友是否管理员/开发者模式 |
