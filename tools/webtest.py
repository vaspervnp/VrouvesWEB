"""Try the web build in a headless Edge through the DevTools protocol (stdlib only; run it with
the Windows python, while build/web is served on localhost:8060). Screenshots go to OUTDIR.
    python.exe tools\\webtest.py OUTDIR URL step step ...
steps: wait:SECS  shot:NAME  click:X,Y  tap:X,Y  touch  key:CODE  eval:JS  size:W,H
"""
import base64, json, os, socket, struct, subprocess, sys, time, urllib.request

EDGE = r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"
PORT = 9333


class WS:
    def __init__(self, url):
        host, path = url[len("ws://"):].split("/", 1)
        h, p = host.split(":")
        self.s = socket.create_connection((h, int(p)))
        key = base64.b64encode(os.urandom(16)).decode()
        self.s.send((f"GET /{path} HTTP/1.1\r\nHost: {host}\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n"
                     f"Sec-WebSocket-Key: {key}\r\nSec-WebSocket-Version: 13\r\n\r\n").encode())
        buf = b""
        while b"\r\n\r\n" not in buf:
            buf += self.s.recv(1)
        self.n = 0
        self.events = []

    def _recv_exact(self, n):
        b = b""
        while len(b) < n:
            c = self.s.recv(n - len(b))
            if not c:
                raise EOFError
            b += c
        return b

    def recv(self):
        data = b""
        while True:
            h = self._recv_exact(2)
            fin, op, ln = h[0] & 0x80, h[0] & 0x0F, h[1] & 0x7F
            if ln == 126:
                ln = struct.unpack(">H", self._recv_exact(2))[0]
            elif ln == 127:
                ln = struct.unpack(">Q", self._recv_exact(8))[0]
            data += self._recv_exact(ln)
            if fin:
                return json.loads(data)

    def send(self, method, **params):
        self.n += 1
        msg = json.dumps({"id": self.n, "method": method, "params": params}).encode()
        mask = os.urandom(4)
        hdr = bytes([0x81])
        if len(msg) < 126:
            hdr += bytes([0x80 | len(msg)])
        elif len(msg) < 65536:
            hdr += bytes([0x80 | 126]) + struct.pack(">H", len(msg))
        else:
            hdr += bytes([0x80 | 127]) + struct.pack(">Q", len(msg))
        self.s.send(hdr + mask + bytes(b ^ mask[i % 4] for i, b in enumerate(msg)))
        while True:
            r = self.recv()
            if r.get("id") == self.n:
                return r.get("result", r.get("error"))
            self.events.append(r)


def main():
    out, url, steps = sys.argv[1], sys.argv[2], sys.argv[3:]
    os.makedirs(out, exist_ok=True)
    prof = os.path.join(os.environ["TEMP"], "vrouves_cdp")
    ed = subprocess.Popen([EDGE, "--headless=new", f"--remote-debugging-port={PORT}", f"--user-data-dir={prof}",
                           "--window-size=1280,800", "--autoplay-policy=no-user-gesture-required",
                           "--enable-unsafe-swiftshader", "--no-first-run", "about:blank"])
    try:
        for _ in range(50):
            try:
                tabs = json.load(urllib.request.urlopen(f"http://127.0.0.1:{PORT}/json"))
                break
            except Exception:
                time.sleep(0.2)
        tab = [t for t in tabs if t["type"] == "page"][0]
        ws = WS(tab["webSocketDebuggerUrl"])
        ws.send("Runtime.enable")
        ws.send("Log.enable")
        ws.send("Page.enable")
        ws.send("Page.navigate", url=url)
        for st in steps:
            kind, _, arg = st.partition(":")
            if kind == "wait":
                end = time.time() + float(arg)
                while time.time() < end:
                    ws.send("Runtime.evaluate", expression="1")
                    time.sleep(0.25)
            elif kind == "size":
                w, h = map(int, arg.split(","))
                ws.send("Emulation.setDeviceMetricsOverride", width=w, height=h, deviceScaleFactor=1, mobile=False)
            elif kind == "touch":
                ws.send("Emulation.setTouchEmulationEnabled", enabled=True, maxTouchPoints=5)
            elif kind == "shot":
                r = ws.send("Page.captureScreenshot", format="png")
                open(os.path.join(out, arg + ".png"), "wb").write(base64.b64decode(r["data"]))
            elif kind == "click":
                x, y = map(float, arg.split(","))
                ws.send("Input.dispatchMouseEvent", type="mouseMoved", x=x, y=y)
                time.sleep(0.1)
                ws.send("Input.dispatchMouseEvent", type="mousePressed", x=x, y=y, button="left", clickCount=1)
                time.sleep(0.08)
                ws.send("Input.dispatchMouseEvent", type="mouseReleased", x=x, y=y, button="left", clickCount=1)
            elif kind == "tap":
                x, y = map(float, arg.split(","))
                ws.send("Input.dispatchTouchEvent", type="touchStart", touchPoints=[{"x": x, "y": y}])
                time.sleep(0.08)
                ws.send("Input.dispatchTouchEvent", type="touchEnd", touchPoints=[])
            elif kind == "key":
                code = arg
                ws.send("Input.dispatchKeyEvent", type="keyDown", key=code, code=code,
                        windowsVirtualKeyCode=ord(code[-1]) if len(code) <= 4 else 0)
                ws.send("Input.dispatchKeyEvent", type="keyUp", key=code, code=code,
                        windowsVirtualKeyCode=ord(code[-1]) if len(code) <= 4 else 0)
            elif kind == "eval":
                r = ws.send("Runtime.evaluate", expression=arg, returnByValue=True, awaitPromise=True)
                print("eval:", json.dumps(r.get("result", r))[:2000])
        for e in ws.events:
            m = e.get("method")
            if m == "Runtime.consoleAPICalled":
                p = e["params"]
                print("console." + p["type"] + ":", " ".join(str(a.get("value", a.get("description", ""))) for a in p["args"])[:400])
            elif m == "Runtime.exceptionThrown":
                print("EXCEPTION:", json.dumps(e["params"]["exceptionDetails"])[:600])
            elif m == "Log.entryAdded":
                print("log." + e["params"]["entry"]["level"] + ":", e["params"]["entry"]["text"][:400])
    finally:
        ed.terminate()
        try:
            ed.wait(5)
        except Exception:
            pass


if __name__ == "__main__":
    main()
