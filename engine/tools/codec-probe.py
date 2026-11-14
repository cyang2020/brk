#!/usr/bin/env python3
"""Ask a Chromium-based app which codecs it can decode and which version it is. It serves one page on a free local port, starts the app with
its own data folder, and prints what the page reports. Run it under the native lock.

    codec-probe.py <Brk executable> <report.json> [KEY=VALUE environment ...]
    codec-probe.py --plain-chromium <Chromium executable> <report.json>     # the unmodified build, which takes a command line instead
    codec-probe.py --plain-chromium --headless --require-h264-aac --sample sample.mp4 <Chromium executable> <report.json>
"""
import argparse, http.server, json, os, shutil, subprocess, sys, tempfile, threading, urllib.parse
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--plain-chromium', action='store_true')
parser.add_argument('--headless', action='store_true')
parser.add_argument('--require-h264-aac', action='store_true')
parser.add_argument('--sample', type=Path, help='An H.264/AAC MP4 to decode and play to completion')
parser.add_argument('app')
parser.add_argument('report', type=Path)
parser.add_argument('environment', nargs='*', help='KEY=VALUE environment overrides')
args = parser.parse_args()
if args.headless and not args.plain_chromium:
    parser.error('--headless requires --plain-chromium')
if any('=' not in value for value in args.environment):
    parser.error('Environment overrides must be KEY=VALUE')
sample = args.sample.read_bytes() if args.sample else None
extra_env = dict(value.split('=', 1) for value in args.environment)
PAGE = """<!doctype html><title>codec probe</title><body><script>
const v=document.createElement('video'), a=document.createElement('audio');
const list={h264:'video/mp4; codecs="avc1.42E01E"',h264main:'video/mp4; codecs="avc1.4D401E"',h264high:'video/mp4; codecs="avc1.640028"',hevc:'video/mp4; codecs="hvc1.1.6.L93.B0"',vp8:'video/webm; codecs="vp8"',vp9:'video/webm; codecs="vp9"',av1:'video/mp4; codecs="av01.0.05M.08"',aac:'audio/mp4; codecs="mp4a.40.2"',mp3:'audio/mpeg',opus:'audio/webm; codecs="opus"',flac:'audio/flac',ac3:'audio/mp4; codecs="ac-3"'};
const r={ua:navigator.userAgent,canPlay:{},mse:{}};
const version=navigator.userAgentData?navigator.userAgentData.getHighEntropyValues(['fullVersionList']).then(v=>{r.fullVersionList=v.fullVersionList}):Promise.resolve();
for(const k in list){r.canPlay[k]=(k=='aac'||k=='mp3'||k=='opus'||k=='flac'||k=='ac3'?a:v).canPlayType(list[k]);r.mse[k]=MediaSource.isTypeSupported(list[k]);}
const cfg=[{initDataTypes:['cenc'],videoCapabilities:[{contentType:'video/mp4; codecs="avc1.42E01E"'},{contentType:'video/webm; codecs="vp9"'}]}];
const widevine=(navigator.requestMediaKeySystemAccess?navigator.requestMediaKeySystemAccess('com.widevine.alpha',cfg).then(()=>'available',e=>'unavailable: '+e.name):Promise.resolve('no EME API (insecure context?)')).then(w=>{r.widevine=w});
const playback=__HAS_SAMPLE__?new Promise(resolve=>{
  const video=document.createElement('video');
  document.body.appendChild(video);
  const timer=setTimeout(()=>finish({ended:false,error:'playback timeout'}),15000);
  function finish(result){clearTimeout(timer);r.playback=result;video.pause();resolve();}
  video.onended=()=>finish({ended:true,currentTime:video.currentTime,decodedFrames:video.getVideoPlaybackQuality().totalVideoFrames});
  video.onerror=()=>finish({ended:false,error:video.error?.message||'media error',code:video.error?.code});
  video.src='/sample.mp4';
  video.play().catch(e=>finish({ended:false,error:e.name+': '+e.message}));
}):Promise.resolve();
Promise.all([version,widevine,playback]).then(()=>fetch('/report?'+encodeURIComponent(JSON.stringify(r))));
</script>"""
PAGE = PAGE.replace('__HAS_SAMPLE__', 'true' if sample is not None else 'false')
done = threading.Event(); result = {}
class H(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def do_GET(self):
        if self.path == '/sample.mp4' and sample is not None:
            self.send_response(200); self.send_header('Content-Type', 'video/mp4'); self.send_header('Content-Length', str(len(sample))); self.end_headers(); self.wfile.write(sample)
            return
        if self.path.startswith('/report?'):
            result.update(json.loads(urllib.parse.unquote(self.path[8:]))); done.set()
        self.send_response(200); self.send_header('Content-Type', 'text/html'); self.end_headers(); self.wfile.write(PAGE.encode())
srv = http.server.ThreadingHTTPServer(('127.0.0.1', 0), H); port = srv.server_address[1]
threading.Thread(target=srv.serve_forever, daemon=True).start()
data = tempfile.mkdtemp(prefix='brk-codec-probe-', dir='/tmp')
env = {k: v for k, v in os.environ.items() if not k.startswith('BRK_')}
env.update(BRK_DATA_DIR=data, BRK_CONTROL_SOCKET=os.path.join(data, 'c.sock'), BRK_START_URL=f'http://127.0.0.1:{port}/', BRK_TEST_NO_GLOBAL_SHORTCUT='1')
env.update(extra_env)
command = [args.app]
if args.plain_chromium:
    command += [f'--user-data-dir={data}', '--no-first-run', '--no-default-browser-check', '--use-mock-keychain', f'http://127.0.0.1:{port}/']
    if args.headless:
        command += ['--headless=new', '--autoplay-policy=no-user-gesture-required', '--mute-audio', '--disable-background-networking']
p = subprocess.Popen(command, env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
ok = done.wait(60)
p.terminate()
try: p.wait(25)
except subprocess.TimeoutExpired: p.kill(); p.wait()
srv.shutdown(); srv.server_close()
shutil.rmtree(data)
if not ok:
    result = {'error': 'no report in 60 s'}
args.report.write_text(json.dumps(result, indent=1) + '\n')
print(json.dumps(result, indent=1))
supported = all(result.get('canPlay', {}).get(codec) and result.get('mse', {}).get(codec)
                for codec in ('h264', 'h264main', 'h264high', 'aac'))
played = sample is None or (result.get('playback', {}).get('ended') and result.get('playback', {}).get('decodedFrames', 0) > 0)
sys.exit(0 if ok and played and (not args.require_h264_aac or supported) else 1)
