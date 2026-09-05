#!/usr/bin/env python3
"""FileBrowser 登录空格过滤器：把 /api/login 的用户名/密码去掉首尾空格后转发。

部署：存为 /srv/fbproxy.py，配 systemd 常驻（端口 8086，仅监听 127.0.0.1），
nginx 将 /api/login 指向本服务。
2026-09-06 起：FileBrowser 改到本地 Windows 经 frp 隧道提供，
BACKEND 转发目标从 8085(Docker) 改为 8087(frps 数据口)。
"""
import http.server, json, http.client

BACKEND = ("127.0.0.1", 8087)
HOP = {"host","content-length","connection","keep-alive","proxy-connection",
       "transfer-encoding","upgrade","te"}

class Handler(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def _relay(self):
        n = int(self.headers.get("Content-Length") or 0)
        raw = self.rfile.read(n) if n else b""
        try:
            d = json.loads(raw.decode("utf-8") or "{}")
            changed = False
            for k in ("username","password"):
                if isinstance(d.get(k), str):
                    d[k] = d[k].strip(); changed = True
            if changed:
                raw = json.dumps(d).encode()
        except Exception:
            pass  # 非 JSON 原样转发
        h = {k: v for k, v in self.headers.items()
             if k.lower() not in HOP}
        h["Host"] = "127.0.0.1:8087"
        c = http.client.HTTPConnection(*BACKEND, timeout=60)
        try:
            c.request("POST", self.path, body=raw, headers=h)
            r = c.getresponse()
            body = r.read()
            self.send_response(r.status)
            for k, v in r.getheaders():
                if k.lower() not in HOP:
                    self.send_header(k, v)
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        finally:
            c.close()

    do_POST = _relay

    def _deny(self):
        self.send_response(404); self.send_header("Content-Length","0"); self.end_headers()
    do_GET = do_PUT = do_DELETE = do_HEAD = do_OPTIONS = do_PATCH = _deny

    def log_message(self, *a):
        pass

http.server.ThreadingHTTPServer(("127.0.0.1", 8086), Handler).serve_forever()
