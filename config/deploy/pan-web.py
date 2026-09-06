#!/usr/bin/env python3
"""pan-web —— 多网盘平台 owner 门户 + 邀请码注册服务(跑在 47,127.0.0.1:9100)

职责:
  1. owner 门户(仅经 SSH 隧道访问,不暴露公网): 总览各站 / 发邀请码 / 停/启/删站点
  2. 邀请码兑换 API(经 nginx 8089 暴露公网,一次有效):
       POST /api/invite/redeem  {"invite":"PAN-xxxx"} -> {siteName, httpPort, serverPort, remotePort, token}
部署:
  /usr/local/bin/pan-web (systemd pan-web.service, Restart=always)
  先设 owner 密码: pan-web setpass '<强口令>'
数据(均在 /etc/frp-sites, root 600):
  owner.hash   = salt:sha256(salt+password)
  invites.conf = code|siteName|created|expires|status|note    (status: new|used)
  (站点注册表 pan-ctl 管: sites.conf)
"""
import os, sys, json, time, hmac, hashlib, secrets, subprocess, urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

DIR  = "/etc/frp-sites"
OWNER_HASH = os.path.join(DIR, "owner.hash")
INVITES    = os.path.join(DIR, "invites.conf")
PUB_IP     = os.path.join(DIR, "public_ip")
PAN_CTL    = "/usr/local/bin/pan-ctl"
HOST, PORT = "127.0.0.1", 9100
INVITE_TTL = 24 * 3600

def pub_ip():
    try: return open(PUB_IP).read().strip()
    except Exception: return "<SERVER_IP>"

def now(): return int(time.time())

# ---------- owner password ----------
def setpass(pw):
    if len(pw) < 8: print("password too short"); sys.exit(1)
    salt = secrets.token_hex(8)
    h = hashlib.sha256((salt + pw).encode()).hexdigest()
    with open(OWNER_HASH, "w") as f: f.write(f"{salt}:{h}")
    os.chmod(OWNER_HASH, 0o600)
    print("owner password saved.")

def check_pw(pw):
    try:
        salt, h = open(OWNER_HASH).read().strip().split(":")
        return hmac.compare_digest(hashlib.sha256((salt + pw).encode()).hexdigest(), h)
    except Exception: return False

# ---------- invite store ----------
def _invites():
    out = []
    if os.path.exists(INVITES):
        for line in open(INVITES):
            line = line.strip()
            if line: out.append(line.split("|"))
    return out

def add_invite(site):
    code = "PAN-" + secrets.token_hex(6).upper()
    with open(INVITES, "a") as f:
        f.write(f"{code}|{site}|{now()}|{now()+INVITE_TTL}|new|-\n")
    os.chmod(INVITES, 0o600)
    return code

def find_invite(code):
    for row in _invites():
        if row[0] == code: return row
    return None

def mark_used(code):
    rows = _invites()
    with open(INVITES, "w") as f:
        for r in rows:
            r[4] = "used" if r[0] == code else r[4]
            f.write("|".join(r) + "\n")

def redeem(invite):
    row = find_invite(invite)
    if not row:                       return None, "邀请码不存在"
    code, site, created, expires, status, note = row
    if status == "used":              return None, "邀请码已被使用"
    if int(expires) < now():          return None, "邀请码已过期"
    p = subprocess.run([PAN_CTL, "add-site", site], capture_output=True, text=True)
    if p.returncode != 0:
        return None, "建站失败: " + p.stdout.strip().splitlines()[-1] if p.stdout else "pan-ctl error"
    # read the site's row from registry
    line = None
    for l in open("/etc/frp-sites/sites.conf"):
        parts = l.strip().split("|")
        if len(parts) >= 7 and parts[1] == site: line = parts
    if not line:
        return None, "建站后注册表读取失败"
    mark_used(invite)
    _idx, _n, http, ctrl, data, _fb, tok = line
    return {"siteName": site, "serverAddr": pub_ip(), "httpPort": int(http),
            "serverPort": int(ctrl), "remotePort": int(data), "token": tok}, None

# ---------- session ----------
_sessions = {}   # token -> expiry
def new_session():
    t = secrets.token_hex(16); _sessions[t] = now() + 3600; return t
def valid(tok): return tok in _sessions and _sessions[tok] > now()

# ---------- site listing ----------
def list_sites():
    out = []
    if os.path.exists("/etc/frp-sites/sites.conf"):
        for l in open("/etc/frp-sites/sites.conf"):
            p = l.strip().split("|")
            if len(p) < 7: continue
            name = p[1]; st = "down"
            r = subprocess.run(["systemctl","is-active", f"frps-{name}"], capture_output=True, text=True)
            if r.returncode == 0: st = "up"
            out.append({"idx": p[0], "name": name, "http": p[2], "ctrl": p[3],
                        "data": p[4], "tok": p[6][:6], "status": st,
                        "url": f"http://{pub_ip()}:{p[2]}"})
    return out

# ---------- HTTP ----------
class H(BaseHTTPRequestHandler):
    def _send(self, code, body, ctype="text/html; charset=utf-8"):
        if isinstance(body, str): body = body.encode()
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _json(self, obj, code=200):
        self._send(code, json.dumps(obj, ensure_ascii=False), "application/json")

    def _cookie(self):
        return self.headers.get("Cookie", "")

    def _authed(self):
        c = self._cookie()
        for part in c.split(";"):
            if part.strip().startswith("pan="):
                return valid(part.strip()[4:])
        return False

    # ---- pages ----
    def _page(self):
        sites = list_sites()
        inv = [{"code": r[0], "site": r[1], "status": r[4]} for r in _invites()][-8:]
        rows = "".join(
            f"<tr><td>{s['name']}</td><td><a href='{s['url']}'>{s['url']}</a></td>"
            f"<td>{s['status']}</td><td>{s['tok']}</td>"
            f"<td><form method='post' style='display:inline'><input type='hidden' name='act' value='start'/>"
            f"<input type='hidden' name='site' value='{s['name']}'/><button>启动</button></form>"
            f"<form method='post' style='display:inline'><input type='hidden' name='act' value='stop'/>"
            f"<input type='hidden' name='site' value='{s['name']}'/><button>停止</button></form>"
            f"<form method='post' style='display:inline' onsubmit=\"return confirm('确认删除 {s['name']}?')\">"
            f"<input type='hidden' name='act' value='rm'/><input type='hidden' name='site' value='{s['name']}'/>"
            f"<button style='color:red'>删除</button></form></td></tr>"
            for s in sites)
        invrows = "".join(f"<tr><td><code>{i['code']}</code></td><td>{i['site']}</td><td>{i['status']}</td></tr>" for i in inv)
        html = f"""<!doctype html><html><head><meta charset="utf-8"><title>网盘平台 · 站主门户</title>
<style>body{{font-family:system-ui;max-width:820px;margin:30px auto;padding:0 16px}}
table{{border-collapse:collapse;width:100%;margin:10px 0}}td,th{{border:1px solid #ddd;padding:6px 9px;text-align:left;font-size:14px}}
code{{background:#f4f4f4;padding:2px 6px}}button{{cursor:pointer}}</style></head><body>
<h2>🖥 网盘平台 · 站主门户</h2>
<p>访问说明:本页经 SSH 隧道访问(浏览器开 localhost:9200)。朋友站用户由该站 admin 自管(数据在各自电脑)。</p>
<h3>站点总览</h3><table><tr><th>站点</th><th>公网地址</th><th>状态</th><th>token前6</th><th>操作</th></tr>{rows}</table>
<h3>发新邀请码</h3>
<form method="post"><input name="act" type="hidden" value="newinv"/>
站点名(给该朋友备注,字母数字-):<input name="site" required placeholder="如 xiaozhang"/>
<button>生成邀请码</button></form>
<h3>最近邀请码</h3><table><tr><th>邀请码</th><th>站点</th><th>状态</th></tr>{invrows}</table>
<form method="post" style="margin-top:26px"><input type="hidden" name="act" value="logout"/><button>退出</button></form>
</body></html>"""
        return html

    def do_GET(self):
        p = urllib.parse.urlparse(self.path)
        if p.path == "/" and self._authed():
            return self._send(200, self._page())
        if p.path == "/login":
            return self._send(200, "<!doctype html><html><head><meta charset='utf-8'><title>登录</title></head><body><h2>站主门户 · 登录</h2><form method='post' action='/login'><input type='password' name='pw' placeholder='owner 密码' autofocus/><br/><br/><button>登录</button></form></body></html>")
        if p.path == "/health":
            return self._json({"status": "ok"})
        self._send(404, "not found")

    def do_POST(self):
        p = urllib.parse.urlparse(self.path)
        ln = int(self.headers.get("Content-Length") or 0)
        body = self.rfile.read(ln)
        # invite redeem (public, via nginx 8089) - no session needed
        if p.path == "/api/invite/redeem":
            try:
                d = json.loads(body.decode() or "{}")
            except Exception:
                return self._json({"ok": False, "error": "bad json"}, 400)
            res, err = redeem(str(d.get("invite", "")))
            if err: return self._json({"ok": False, "error": err}, 400)
            return self._json({"ok": True, **res})
        ct = self.headers.get("Content-Type", "")
        d = urllib.parse.parse_qs(body.decode()) if "urlencoded" in ct else {}
        # login: allowed without session
        if p.path == "/login":
            pw = (d.get("pw") or [""])[0]
            if check_pw(pw):
                tok = new_session()
                self.send_response(303)
                self.send_header("Location", "/")
                self.send_header("Set-Cookie", f"pan={tok}; Path=/; HttpOnly")
                self.end_headers()
                return
            return self._send(403, "密码错误")
        # all other posts require an active session
        if not self._authed():
            return self._send(403, "forbidden")
        act = (d.get("act") or [""])[0]
        site = (d.get("site") or [""])[0]
        if act == "logout":
            return self._send(200, "logged out")
        if act == "newinv":
            code = add_invite(site or "site") if site else None
            msg = f"邀请码生成:<br><big><code>{code}</code></big><br><a href='/'>← 返回</a>" if code else "无效站点名"
            return self._send(200, msg)
        if act in ("start", "stop", "rm") and site:
            cmd = {"start": "start", "stop": "stop", "rm": "rm-site"}[act]
            r = subprocess.run([PAN_CTL, cmd, site], capture_output=True, text=True)
            ok = "OK" if r.returncode == 0 else ("FAIL: " + (r.stdout or r.stderr))
            return self._send(200, f"{ok}<br><a href='/'>← 返回</a>")
        self._send(400, "bad request")

    def log_message(self, *a): pass

if __name__ == "__main__":
    if len(sys.argv) >= 3 and sys.argv[1] == "setpass":
        setpass(sys.argv[2]); sys.exit(0)
    os.makedirs(DIR, exist_ok=True)
    if not os.path.exists(OWNER_HASH):
        print("owner password not set. Run: pan-web setpass '<strong password>'"); sys.exit(1)
    print(f"pan-web listening on {HOST}:{PORT}")
    ThreadingHTTPServer((HOST, PORT), H).serve_forever()
