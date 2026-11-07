#!/usr/bin/env python3
"""Ask a Chromium-based app which codecs it can decode and which version it is. It serves one page on a free local port, starts the app with
its own data folder, and prints what the page reports. Run it under the native lock.

    codec-probe.py <Brk executable> <report.json> [KEY=VALUE environment ...]
    codec-probe.py --plain-chromium <Chromium executable> <report.json>     # the unmodified build, which takes a command line instead
"""
import http.server, json, os, socket, subprocess, sys, tempfile, threading, time, urllib.parse
plain = sys.argv[1] == '--plain-chromium'
arguments = sys.argv[2:] if plain else sys.argv[1:]
app, out = arguments[0], arguments[1]
extra_env = dict(a.split('=', 1) for a in arguments[2:])
PAGE = """<!doctype html><title>codec probe</title><script>
const v=document.createElement('video'), a=document.createElement('audio');
const list={h264:'video/mp4; codecs="avc1.42E01E"',h264high:'video/mp4; codecs="avc1.640028"',hevc:'video/mp4; codecs="hvc1.1.6.L93.B0"',vp8:'video/webm; codecs="vp8"',vp9:'video/webm; codecs="vp9"',av1:'video/mp4; codecs="av01.0.05M.08"',aac:'audio/mp4; codecs="mp4a.40.2"',mp3:'audio/mpeg',opus:'audio/webm; codecs="opus"',flac:'audio/flac',ac3:'audio/mp4; codecs="ac-3"'};
const r={ua:navigator.userAgent,canPlay:{},mse:{}};
if(navigator.userAgentData){navigator.userAgentData.getHighEntropyValues(['fullVersionList']).then(v=>{r.fullVersionList=v.fullVersionList});}
for(const k in list){r.canPlay[k]=(k=='aac'||k=='mp3'||k=='opus'||k=='flac'||k=='ac3'?a:v).canPlayType(list[k]);r.mse[k]=MediaSource.isTypeSupported(list[k]);}
const cfg=[{initDataTypes:['cenc'],videoCapabilities:[{contentType:'video/mp4; codecs="avc1.42E01E"'},{contentType:'video/webm; codecs="vp9"'}]}];
(navigator.requestMediaKeySystemAccess?navigator.requestMediaKeySystemAccess('com.widevine.alpha',cfg).then(()=>'available',e=>'unavailable: '+e.name):Promise.resolve('no EME API (insecure context?)')).then(w=>{r.widevine=w;return fetch('/report?'+encodeURIComponent(JSON.stringify(r)));});
</script>"""
done = threading.Event(); result = {}
class H(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def do_GET(self):
        if self.path.startswith('/report?'):
            result.update(json.loads(urllib.parse.unquote(self.path[8:]))); done.set()
        self.send_response(200); self.send_header('Content-Type', 'text/html'); self.end_headers(); self.wfile.write(PAGE.encode())
srv = http.server.ThreadingHTTPServer(('127.0.0.1', 0), H); port = srv.server_address[1]
threading.Thread(target=srv.serve_forever, daemon=True).start()
data = tempfile.mkdtemp(prefix='brk-codec-probe-', dir='/tmp')
env = {k: v for k, v in os.environ.items() if not k.startswith('BRK_')}
env.update(BRK_DATA_DIR=data, BRK_CONTROL_SOCKET=os.path.join(data, 'c.sock'), BRK_START_URL=f'http://127.0.0.1:{port}/', BRK_TEST_NO_GLOBAL_SHORTCUT='1')
env.update(extra_env)
command = [app]
if plain:
    command += [f'--user-data-dir={data}', '--no-first-run', '--no-default-browser-check', '--use-mock-keychain', f'http://127.0.0.1:{port}/']
p = subprocess.Popen(command, env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
ok = done.wait(60)
p.terminate()
try: p.wait(25)
except subprocess.TimeoutExpired: p.kill()
json.dump(result if ok else {'error': 'no report in 60 s'}, open(out, 'w'), indent=1)
print(json.dumps(result if ok else {'error': 'no report'}, indent=1))
