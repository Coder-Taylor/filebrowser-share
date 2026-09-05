# 05 · 本地存储 + frp 内网穿透(2026-09-06 起)

## 为什么改造

47 轻量(40G 盘)装不下本地 `E:\NetDist`(≈537G:老友记全季 4K + 软件包,两千多个 2~3G 视频)。
目标:FileBrowser 主服务搬到本地 Windows,47 只保留为公网入口。访问地址、账号、界面体验全部不变。

## 架构(现状)

```
朋友 / 自己(浏览器)
      │ http://<SERVER_IP>:8081
      ▼
47 轻量(公网入口,几乎不存数据)
   nginx  :8081 对外
      ├── POST /api/login → fbproxy(127.0.0.1:8086,去空格)→ 8087
      ├── GET /static/assets/i18n-C0UlxgXD.js → 本地补丁文件(alias,no-cache)
      └── 其余 → proxy_pass 127.0.0.1:8087
                      │
              frps :443(公网,控制+数据单口,token 认证)
                      │ frp 隧道(本地主动连出,无需公网 IP/端口映射)
                      ▼
  本地 Windows(NSSM 服务,自动启动)
      ├─ FrpcSvc  → frpc.exe(loginFailExit=false,断线自动重连)
      └─ FileBrowserSvc → filebrowser.exe(2.63.23)
                            -r E:\NetDist(顶层 公共/、私人/)
                            -a 127.0.0.1 -p 8085
                            -d D:\Tools\fbwin\filebrowser.db(从 47 迁移)
```

## 关键设计点(实测结论)

1. **数据流经不落盘**:nginx `proxy_buffering off` + frps 纯 TCP 转发,47 的磁盘/内存与文件大小无关。文件上限 = 本地 E 盘空间 + 下载方磁盘 + 时间(校园网上行 4~5MB/s,2~3G 视频约 8~12 分钟/个)。
2. **断点续传可用(实测 206)**:FileBrowser 单文件下载端点原生支持 `Range`/`Accept-Ranges`(底层 Go http.ServeContent)。多选/文件夹 zip 打包是流式生成、**不支持续传**,大文件分享一律用单文件。
3. **断链自愈链路**:frpc `loginFailExit=false` 指数退避重连 + NSSM 崩溃 5s 重启。实测:47 上 frps 停止 8s 再启动,frpc ~5s 自动重连;续传第二段与第一段拼接后与源文件 **md5 一致**。
4. **传输中的下载中断怎么办**:进行中的 TCP 会断,下载任务需下载器重试/续传。浏览器下载列表点"恢复";要全自动用 Motrix/IDM/迅雷(均支持 Range 自动断点续传)。
5. **端口选择 443 的原因(踩坑记录)**:阿里云轻量控制台**后添加的防火墙规则(TCP 7000/7500)显示"已启用"但不生效**(外网与手机流量均超时,连续两个端口);系统预置规则(80/443/22)正常。解决:frp 控制端口用预置放行的 **443**。若将来 443 要留给 HTTPS,需回控制台处理规则异常(删除重建可能无效,必要时重启实例/工单)。
6. **中文补丁零迁移**:FileBrowser 仍是 2.63.23(与 47 原版本一致),i18n 资产文件名 hash 不变,47 上 nginx alias 原样指向 `/srv/fb-custom/i18n-C0UlxgXD.js`。
7. **账号数据迁移**:47 的 `/srv/fb/filebrowser.db`(40K)拷到本地即带走全部:admin/guest、guest scope=`/公共`、zh-cn locale、品牌名。目录结构已本地化:E:\NetDist 顶层建 `公共/`(Software installation package、老友记、使用说明.txt)与 `私人/`(空)。

## 日常操作

- **加内容**:直接复制文件到 `E:\NetDist\公共\…`,立刻可见,无任何"上传"动作。
- **朋友下载速度**:受本地网络**上行**限制(校园网实测 4.3MB/s),与 47 带宽无关。
- **下线**:笔记本关机/睡眠 = 网盘下线。开机后 NSSM 自动拉起两个服务,frpc 自动重连,通常 1 分钟内恢复。

## 故障排查

| 现象 | 检查 |
|------|------|
| 外网打不开 :8081 | ① 电脑是否开机/服务是否 Running(`sc query FileBrowserSvc FrpcSvc`)② 47 上 `systemctl status frps nginx fbproxy` ③ 隧道是否在线:47 看 `journalctl -u frps` 最近是否有 login |
| frpc 连不上 | 本地看 `D:\Tools\fbwin\logs\frpc-svc.out.log`;47 看 `ss -ltn` 443 是否监听;token 是否与 47 frps.toml 一致 |
| 下载断但没恢复 | 朋友在浏览器下载列表点"恢复"(需服务端 Range,已确认支持);想全自动让朋友用 Motrix/IDM 之类下载器 |
| 登录失败 | 走 fbproxy 链路 `/api/login`,用户名密码首尾空格会被自动去掉;若改过 fbproxy 记得 `systemctl restart fbproxy` |
| 中文没了 | 见 docs/03(先确认 FileBrowser 版本还是 2.63.23,升级会改 hash 文件名) |

## 相关文件

- 配置:`config/nginx-site.conf`(回源 8087)、`config/fbproxy.py`(BACKEND 8087)、`config/frps.toml`、`config/frpc.toml`、`config/frps.service`、`config/filebrowser-windows.txt`
- 47 数据(冷备):`/srv/alist/storage`(旧网盘内容 29G)、`/srv/fb/filebrowser.db`(旧库备份,容器已停 `--restart=no`)
