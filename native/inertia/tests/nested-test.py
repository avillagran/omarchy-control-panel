"""Exercise omarchy-hyprland-inertia in an isolated nested Hyprland. Never touches the parent session.

Usage: python3 -I nested-test.py [ARTIFACT_DIR]
Run inside a Hyprland session. A nested compositor window appears for about a
minute. Touchpad scrolling is simulated with zwlr_virtual_pointer_v1 (axis,
then axis_source=finger, then axis_stop), because a nested Hyprland receives
the parent's real touchpad scroll as a wheel. Build and runtime directories are
left in place on purpose (tests never delete file trees).
"""
import json, os, subprocess, sys, tempfile, time
from pathlib import Path

src = Path(__file__).resolve().parent
plugin_src = src.parent
art = Path(sys.argv[1] if len(sys.argv) > 1 else tempfile.mkdtemp(prefix='omarchy-inertia-test-'))
art.mkdir(parents=True, exist_ok=True)
here = art / 'build'
here.mkdir(exist_ok=True)
lib = here / 'inertia.so'
subprocess.run(['make', '-s', '-C', str(plugin_src), f'OUT={lib}'], check=True)
xdg = Path('/usr/share/wayland-protocols/stable/xdg-shell/xdg-shell.xml')
vp = src / 'wlr-virtual-pointer-unstable-v1.xml'
for xml, stem in ((xdg, 'xdg-shell-protocol'), (vp, 'pointer-protocol')):
  subprocess.run(['wayland-scanner', 'client-header', str(xml), str(here / f'{stem}.h')], check=True)
  subprocess.run(['wayland-scanner', 'private-code', str(xml), str(here / f'{stem}.c')], check=True)
subprocess.run(['cc', str(src / 'probe.c'), str(here / 'xdg-shell-protocol.c'), '-I', str(here), '-lwayland-client', '-o', str(here / 'probe')], check=True)
subprocess.run(['cc', str(src / 'vptr.c'), str(here / 'pointer-protocol.c'), '-I', str(here), '-lwayland-client', '-lm', '-o', str(here / 'vptr')], check=True)
print('artifacts', art, flush=True)

parent = json.loads(subprocess.check_output(['hyprctl', 'instances', '-j'], text=True))
assert len(parent) == 1
parent_sig = parent[0]['instance']
parent_display = str(Path(os.environ['XDG_RUNTIME_DIR']) / parent[0]['wl_socket'])

results = []
def check(name, ok, detail=''):
  results.append((name, ok))
  print(('PASS' if ok else 'FAIL') + f': {name} {detail}', flush=True)

if True:
  # Short path: Hyprland's socket paths must stay under 108 bytes.
  scratch = Path(tempfile.mkdtemp(prefix='c', dir=os.environ['XDG_RUNTIME_DIR']))
  cfg = scratch / 'hyprland.lua'
  flag = scratch / 'inertia-on'
  cfg.write_text('''
local flag = io.open("FLAG", "r")
if flag then flag:close(); hl.plugin.load("LIB") end
hl.monitor({ output = "", mode = "1280x800@60", position = "0x0", scale = 1 })
hl.config({ animations = { enabled = false }, input = { follow_mouse = 1, touchpad = { scroll_factor = 0.4 } },
  misc = { disable_hyprland_logo = true, disable_splash_rendering = true } })
'''.replace('FLAG', str(flag)).replace('LIB', str(lib)))
  env = dict(os.environ, XDG_RUNTIME_DIR=str(scratch), AQ_BACKEND='wayland', WAYLAND_DISPLAY=parent_display,
             HYPRLAND_NO_SD_NOTIFY='1', HYPRLAND_NO_SD_VARS='1')
  env.pop('HYPRLAND_INSTANCE_SIGNATURE', None)
  log = (art / 'compositor.log').open('w')
  comp = subprocess.Popen(['Hyprland', '--config', str(cfg)], env=env, stdout=log, stderr=log)
  probes = []

  def ctl(*a):
    if a[0] == 'plugin':
      sig = env.get('HYPRLAND_INSTANCE_SIGNATURE')
      assert sig and sig != parent_sig and env['XDG_RUNTIME_DIR'] == str(scratch), 'refusing plugin cmd outside nest'
    r = subprocess.run(['hyprctl', *a], env=env, capture_output=True, text=True, timeout=5, check=True)
    return r.stdout

  def probe(app):
    f = (art / f'probe-{app}.log').open('w')
    p = subprocess.Popen([str(here / 'probe'), app], env=env, stdout=f, stderr=subprocess.STDOUT)
    probes.append(p)
    for _ in range(50):
      if any(c['class'] == app for c in json.loads(ctl('clients', '-j'))): break
      time.sleep(.1)
    else: raise RuntimeError('probe did not map')
    time.sleep(.3)
    return art / f'probe-{app}.log'

  def drive(cmds):
    subprocess.run([str(here / 'vptr'), '1280', '800'], input='\n'.join(cmds) + '\n', text=True, env=env, check=True, timeout=15)

  def gesture(app_log, tail, extra_after=()):
    """Move in, finger-scroll 12 frames of 8 units / 8 ms, then `tail`; return axis events after the last real sample."""
    drive(['move 600 380', 'wait 30', 'move 640 400', 'wait 150'])
    mark = len(app_log.read_text().splitlines())
    cmds = []
    for _ in range(12): cmds += ['finger 0 8', 'wait 8']
    cmds += tail
    t0 = time.monotonic()
    drive(cmds + list(extra_after))
    time.sleep(1.2)
    lines = app_log.read_text().splitlines()[mark:]
    axis = [l for l in lines if ' axis 0 ' in l and float(l.split()[3]) != 0]
    real = axis[:12]
    after = axis[12:]
    return real, after, lines

  try:
    for _ in range(100):
      if comp.poll() is not None: raise RuntimeError('nested compositor exited')
      try: inst = json.loads(ctl('instances', '-j'))
      except Exception: inst = []
      if inst:
        env['HYPRLAND_INSTANCE_SIGNATURE'] = inst[0]['instance']; env['WAYLAND_DISPLAY'] = inst[0]['wl_socket']; break
      time.sleep(.1)
    else: raise RuntimeError('nest did not start')
    for _ in range(150):
      try: v = ctl('version'); break
      except subprocess.CalledProcessError: time.sleep(.2)
    else: raise RuntimeError('nested IPC never answered')
    print('nested', v.splitlines()[0], flush=True)

    plog = probe('inertia-probe')
    real, after, _ = gesture(plog, ['stop 0'])
    check('baseline without plugin: finger scroll reaches client', len(real) == 12, f'({len(real)} events)')
    check('baseline without plugin: no coast after axis stop', len(after) == 0, f'({len(after)} extra)')

    out = ctl('plugin', 'load', str(lib))
    print('load:', out.strip(), flush=True)
    loaded = 'omarchy-inertia' in ctl('plugin', 'list')
    check('plugin loads into Hyprland', loaded)
    if not loaded: raise SystemExit

    real, after, lines = gesture(plog, ['stop 0'])
    vals = [float(l.split()[3]) for l in after]
    ts = [float(l.split()[0]) for l in after]
    span = (ts[-1] - ts[0]) if ts else 0
    check('coast after finger lift (axis stop)', len(after) >= 5, f'({len(after)} events, {span:.0f} ms, total {sum(vals):.1f})')
    check('coast decelerates', len(vals) >= 3 and abs(vals[-1]) < abs(vals[0]), f'(first {vals[0] if vals else 0:.2f} last {vals[-1] if vals else 0:.2f})')
    check('coast bounded to ~800 ms', span <= 850, f'({span:.0f} ms)')
    check('coast same direction as gesture', all(v > 0 for v in vals))

    _, after, _ = gesture(plog, ['wait 400'])
    check('no coast when finger stays (no axis stop)', len(after) == 0, f'({len(after)} extra)')

    _, after, _ = gesture(plog, ['stop 0', 'wait 60', 'move 650 410'])
    ts = [float(l.split()[0]) for l in after]
    span = (ts[-1] - ts[0]) if ts else 0
    check('pointer motion cancels coast', len(after) > 0 and span < 120, f'({len(after)} events in {span:.0f} ms)')

    drive(['move 640 400', 'wait 150'])
    mark = len(plog.read_text().splitlines())
    drive(['wheel 1', 'wait 30', 'wheel 1', 'wait 30', 'wheel 1'])
    time.sleep(1)
    axis = [l for l in plog.read_text().splitlines()[mark:] if ' axis 0 ' in l]
    check('mouse wheel unaffected (no coast)', len(axis) == 3, f'({len(axis)} events for 3 clicks)')

    # Terminals have no inertia of their own, so they coast.
    probes[0].terminate(); probes[0].wait()
    time.sleep(.3)
    tlog = probe('Alacritty')
    _, after, _ = gesture(tlog, ['stop 0'])
    check('terminal (Alacritty) coasts', len(after) >= 5, f'({len(after)})')
    probes[-1].terminate(); probes[-1].wait()
    time.sleep(.3)

    # Browsers keep their own touchpad fling, but get wheel coasting.
    blog = probe('google-chrome')
    _, after, _ = gesture(blog, ['stop 0'])
    check('browser (google-chrome) keeps its own touchpad fling', len(after) == 0, f'({len(after)} extra)')
    ctl('eval', 'hl.config({ plugin = { inertia = { mouse = true } } })')
    drive(['move 600 380', 'wait 30', 'move 640 400', 'wait 150'])
    mark = len(blog.read_text().splitlines())
    drive(['wheel 1', 'wait 15'] * 5 + ['wheel 1'])
    time.sleep(1.3)
    axis = [l for l in blog.read_text().splitlines()[mark:] if ' axis 0 ' in l and float(l.split()[3]) != 0]
    check('browser: a fast wheel spin coasts', len(axis) - 6 >= 5, f'({len(axis) - 6} extra)')
    ctl('reload'); time.sleep(.4)
    ctl('eval', 'hl.config({ plugin = { inertia = { all_apps = true } } })')
    _, after, _ = gesture(blog, ['stop 0'])
    check('all_apps: browser touchpad coasts too', len(after) >= 5, f'({len(after)})')
    ctl('reload'); time.sleep(.4)
    probes[-1].terminate(); probes[-1].wait()
    time.sleep(.3)

    plog = probe('inertia-probe2')
    # The window opened under a cursor that has not moved since.
    mark = len(plog.read_text().splitlines())
    drive(['finger 0 8', 'wait 8'] * 12 + ['stop 0'])
    time.sleep(1.2)
    after = [l for l in plog.read_text().splitlines()[mark:] if ' axis 0 ' in l and float(l.split()[3]) != 0][12:]
    check('coasts in a window that opened under a still cursor', len(after) >= 5, f'({len(after)})')
    _, after, _ = gesture(plog, ['stop 0'])
    check('coasts in a newly opened window (no reload)', len(after) >= 5, f'({len(after)})')
    ctl('reload'); time.sleep(.3)
    _, after, _ = gesture(plog, ['stop 0'])
    check('coasts after 1x hyprctl reload', len(after) >= 5, f'({len(after)})')
    for i in range(3):
      ctl('reload'); time.sleep(.2)
    _, after, _ = gesture(plog, ['stop 0'])
    check('still coasts after 3x hyprctl reload', len(after) >= 5, f'({len(after)})')

    # Unload mid-coast must not crash.
    drive(['move 640 400', 'wait 150'] + ['finger 0 8', 'wait 8'] * 12 + ['stop 0'])
    time.sleep(.05)
    ctl('plugin', 'unload', str(lib))
    time.sleep(.5)
    check('unload during coast keeps compositor alive', comp.poll() is None and 'omarchy-inertia' not in ctl('plugin', 'list'))
    _, after, _ = gesture(plog, ['stop 0'])
    check('after unload: back to no coast', len(after) == 0, f'({len(after)})')
    ctl('plugin', 'load', str(lib)); time.sleep(.2)
    _, after, _ = gesture(plog, ['stop 0'])
    check('reload of plugin works again', len(after) >= 5, f'({len(after)})')
    def spin(app_log, notches, gap, tail=()):
      """Wheel notches `gap` ms apart; returns (real, coast) axis events."""
      drive(['move 600 380', 'wait 30', 'move 640 400', 'wait 150'])
      mark = len(app_log.read_text().splitlines())
      cmds = []
      for n in range(notches):
        cmds.append('wheel 1')
        if n < notches - 1: cmds.append(f'wait {gap}')
      drive(cmds + list(tail))
      time.sleep(1.3)
      lines = app_log.read_text().splitlines()[mark:]
      axis = [l for l in lines if ' axis 0 ' in l and float(l.split()[3]) != 0]
      return axis[:notches], axis[notches:], lines

    real, coast, _ = spin(plog, 6, 15)
    check('mouse wheel: no coast while the mouse option is off (default)', len(real) == 6 and len(coast) == 0, f'({len(real)} notches, {len(coast)} extra)')
    ctl('eval', 'hl.config({ plugin = { inertia = { mouse = true } } })')
    real, coast, lines = spin(plog, 6, 15)
    vals = [float(l.split()[3]) for l in coast]
    check('mouse wheel: a fast spin coasts', len(coast) >= 5, f'({len(coast)} events, total {sum(vals):.0f})')
    check('mouse wheel: coast slows down and keeps direction', len(vals) >= 3 and all(v > 0 for v in vals) and vals[-1] < vals[0])
    check('mouse wheel: coast is sent as continuous scrolling', 'source 2' in '\n'.join(lines))
    _, coast, _ = spin(plog, 6, 120)
    check('mouse wheel: a slow spin just stops', len(coast) == 0, f'({len(coast)} extra)')
    _, coast, _ = spin(plog, 1, 0)
    check('mouse wheel: a single notch does not coast', len(coast) == 0, f'({len(coast)} extra)')
    _, coast, _ = spin(plog, 6, 15, ['wait 90', 'move 660 420', 'wait 20', 'move 670 430'])
    ts = [float(l.split()[0]) for l in coast]
    check('mouse wheel: moving the mouse does not cut the coast', len(coast) >= 5 and (ts[-1] - ts[0]) > 150, f'({len(coast)} events, {(ts[-1]-ts[0]) if ts else 0:.0f} ms)')
    real, coast, _ = spin(plog, 6, 15, ['wait 90', 'wheel -1'])
    check('mouse wheel: turning back cancels the coast', len(coast) <= 6, f'({len(coast)} extra)')
    ctl('eval', 'hl.config({ plugin = { inertia = { touchpad = false } } })')
    _, after, _ = gesture(plog, ['stop 0'])
    check('touchpad option off: no touchpad coast', len(after) == 0, f'({len(after)})')
    ctl('reload'); time.sleep(.4)
    ctl('eval', 'hl.config({ plugin = { inertia = { coast = 0 } } })')
    _, after, _ = gesture(plog, ['stop 0'])
    check('coast 0: no touchpad coast', len(after) == 0, f'({len(after)})')
    ctl('eval', 'hl.config({ plugin = { inertia = { coast = 1600 } } })')
    _, after, _ = gesture(plog, ['stop 0'], extra_after=('wait 900',))
    ts = [float(l.split()[0]) for l in after]
    span = (ts[-1] - ts[0]) if ts else 0
    check('coast 1600: coasts longer than the 800 ms default', span > 900 and span <= 1650, f'({span:.0f} ms)')
    ctl('reload'); time.sleep(.4)
    _, after, _ = gesture(plog, ['stop 0'])
    check('options return to defaults on reload: touchpad coasts again', len(after) >= 5, f'({len(after)})')
    _, coast, _ = spin(plog, 6, 15)
    check('options return to defaults on reload: mouse off again', len(coast) == 0, f'({len(coast)})')

    ctl('plugin', 'unload', str(lib))

    # Omarchy's toggle: the config asks for the plugin while a flag file exists.
    flag.write_text('')
    ctl('reload'); time.sleep(.5)
    check('config toggle on loads the plugin', 'omarchy-inertia' in ctl('plugin', 'list'))
    _, after, _ = gesture(plog, ['stop 0'])
    check('config toggle on: coasts', len(after) >= 5, f'({len(after)})')
    flag.unlink()
    ctl('reload'); time.sleep(.5)
    check('config toggle off unloads the plugin on reload', 'omarchy-inertia' not in ctl('plugin', 'list'))
    _, after, _ = gesture(plog, ['stop 0'])
    check('config toggle off: no coast', len(after) == 0, f'({len(after)})')
    check('compositor alive at the end', comp.poll() is None)
  finally:
    for p in probes:
      if p.poll() is None: p.terminate()
    if comp.poll() is None:
      comp.terminate()
      try: comp.wait(5)
      except subprocess.TimeoutExpired: comp.kill()
    else:
      print('compositor exit code', comp.returncode)
    log.close()

failed = [n for n, ok in results if not ok]
print(f'\n{len(results) - len(failed)}/{len(results)} passed')
sys.exit(1 if failed else 0)
