#!/usr/bin/env python3
"""FileBrowser 登录空格过滤器：把 /api/login 的用户名/密码去掉首尾空格后转发。

多站点版(2026-09)：支持参数化 —— 每个站点一个实例、转发到各自的 frp 数据口。
用法:
    fbproxy.py                      # 默认:监听 127.0.0.1:8086,转发 127.0.0.1:8087(= 站1 现状,兼容)
    fbproxy.py <listen_port> <backend_port>   # 例如站点2: 8086 传 8086 10086? 否 —— 用下面格式

    fbproxy.py 8087_2 ...            # 见下文
推荐清晰格式(站主 pan-ctl 会按此生成 systemd unit):
    fbproxy.py <listen_port> <backend_port>
    例: python3 /srv/fbproxy.py 8086 8087       # 站1
        python3 /srv/fbproxy.py 18086 18087     # 站2(监听 127.0.0.1:18086 → 转发 18087)

仅监听 127.0.0.1；nginx 将各站 /api/login 指到对应实例。
"""
import sys, http.server, json, http.client

DEFAULT_LISTEN, DEFAULT_BACKEND = 8086, 8087
args = sys.argv[1:]
if len(args) >= 2:
    listen_port, backend_port = int(args[0]), int(args[1])
else:
    listen_port, backend_port = DEFAULT_LISTEN, DEFAULT_BACKEND
print(f"fbproxy: listen 127.0.0.1:{listen_port} -> 127.0.0.1:{backend_port}", file=sys.stderr)

BACKEND = ("127.0.0.1", backend_port)
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
        h["Host"] = f"127.0.0.1:{backend_port}"
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

http.server.ThreadingHTTPServer(("127.0.0.1", listen_port), Handler).serve_forever()
