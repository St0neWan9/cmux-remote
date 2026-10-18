#!/usr/bin/env python3
"""Host side of MobileReconnectQuietUITests: two isolated demo Bridges, one of which goes away.

Setup (Mac A on 7801, Mac B on 7802, each with its own home so neither touches the installed Bridge):
  for each of a b: CFFIXED_USER_HOME=/tmp/cmuxe2e/<m>/home cmux-remote init|serve --demo --relay off --no-discovery
  --listen 127.0.0.1, then `enrollment open --host 127.0.0.1 --format json > /tmp/cmuxe2e/<m>/bootstrap.json`.
Run this script, then the UI test with CMUX_REMOTE_E2E_ROOT=/tmp/cmuxe2e in the xctestrun environment. It approves
the phone on both Macs; on the test's `kill-b` marker it stops Mac B and logs every dial to B's port in host.log.
"""
import json, os, socket, subprocess, time, threading
root = '/tmp/cmuxe2e'; cli = str(__import__('pathlib').Path(__file__).resolve().parents[1] / '.build/debug/cmux-remote')
macs = {'a': 7801, 'b': 7802}
def run(h, *args):
    env = dict(os.environ, CFFIXED_USER_HOME=f'{root}/{h}/home', HOME=f'{root}/{h}/home')
    return subprocess.run([cli, *args, '--state', f'{root}/{h}/state', '--port', str(macs[h])], env=env, capture_output=True, text=True, timeout=20)
def log(line):
    with open(f'{root}/host.log', 'a') as f: f.write(f'{time.time():.1f} {line}\n')
def count_dials():
    s = socket.socket(); s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    s.bind(('127.0.0.1', macs['b'])); s.listen(16)
    while True:
        c, _ = s.accept(); log('dial-b'); c.close()
killed = False
deadline = time.time() + 1800
while time.time() < deadline:
    for h in macs:
        if killed and h == 'b': continue
        out = run(h, 'enrollment', 'pending', '--format', 'json').stdout
        try: pending = json.loads(out or '[]')
        except Exception: pending = []
        items = pending if isinstance(pending, list) else pending.get('requests', pending.get('result', []))
        for item in items if isinstance(items, list) else []:
            rid = item.get('requestID') or item.get('request_id')
            if rid and item.get('state', 'pending') == 'pending':
                spaces = [a for w in item.get('scope', {}).get('workspaces', []) for a in ('--workspace', w)]
                r = run(h, 'enrollment', 'approve', rid, '--control', *spaces); log(f'approve {h} {rid[:8]} rc={r.returncode} {r.stderr.strip()[:120]}')
    if not killed and os.path.exists(f'{root}/kill-b'):
        pids = subprocess.run(['lsof', '-t', f'-iTCP:{macs["b"]}', '-sTCP:LISTEN'], capture_output=True, text=True).stdout.split()
        for pid in pids: subprocess.run(['kill', pid])
        time.sleep(1.5)
        killed = True; log('killed b'); threading.Thread(target=count_dials, daemon=True).start()
    time.sleep(1)
