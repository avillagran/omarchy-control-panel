import json
import importlib.machinery
import importlib.util
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

SCRIPT = Path(__file__).resolve().parents[1] / 'bin/control-panel-backup'


def load_backend():
    loader = importlib.machinery.SourceFileLoader('control_panel_backup', str(SCRIPT))
    spec = importlib.util.spec_from_loader(loader.name, loader)
    assert spec is not None
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    return module


class BackupTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.home = self.root / 'home'
        self.dest = self.root / 'backups'
        self.home.mkdir()
        self.dest.mkdir()
        self.req = dict(home=str(self.home), destination=str(self.dest), configurations=True, files=True)
        self.put('.config/hypr/hyprland.conf', 'theme=v1')
        self.put('Documents/note.txt', 'version one')

    def put(self, rel, value):
        path = self.home / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(value)

    def call(self, action, **kwargs):
        env = dict(os.environ, HOME=str(self.home), XDG_CONFIG_HOME=str(self.home / '.config'))
        env.update(getattr(self, 'extra_env', {}))
        result = subprocess.run([sys.executable, str(SCRIPT), action], input=json.dumps(self.req | kwargs), text=True, capture_output=True, env=env)
        self.assertTrue(result.stdout.strip(), result.stderr)
        data = json.loads(result.stdout)
        self.assertEqual(result.returncode, 0 if data['ok'] else 1, result.stderr)
        return data

    def test_safety_and_independent_streams(self):
        self.put('.ssh/id_rsa', 'NEVER COPY')
        self.put('.hermes/.env', 'NEVER COPY')
        self.put('.hermes/profiles/work/config.yaml', 'NEVER COPY')
        self.put('.hermes/profiles/work/skills/safe/SKILL.md', 'safe skill')
        self.put('Documents/unchanged.txt', 'unchanged')
        (self.home / 'Documents/link').symlink_to(self.home / '.ssh', target_is_directory=True)
        first = self.call('backup', configurations=False)
        second = self.call('backup', configurations=False)
        self.assertTrue(second['ok'], second)
        a = self.dest / first['snapshot'] / 'payload/files/Documents/unchanged.txt'
        b = self.dest / second['snapshot'] / 'payload/files/Documents/unchanged.txt'
        self.assertEqual(a.stat().st_ino, b.stat().st_ino)
        self.assertFalse((b.parent / 'link').exists())
        self.assertFalse((self.dest / first['snapshot'] / 'payload/files/.ssh').exists())
        self.assertFalse((self.dest / first['snapshot'] / 'payload/files/.hermes/.env').exists())
        conf = self.call('backup', files=False)
        self.assertTrue(conf['ok'], conf)
        target = self.root / 'configs'
        target.mkdir()
        self.assertTrue(self.call('restore', snapshot=conf['snapshot'], target=str(target))['ok'])
        self.assertFalse((target / 'home/Documents').exists())
        self.assertEqual((target / 'home/.hermes/profiles/work/skills/safe/SKILL.md').read_text(), 'safe skill')
        self.assertFalse(self.call('restore', snapshot=conf['snapshot'], target=str(target))['ok'])
        self.assertFalse(self.call('restore', snapshot=conf['snapshot'], target=str(self.home))['ok'])
        self.assertFalse(self.call('plan', paths=['../outside'])['ok'])
        self.assertFalse(self.call('plan', destination=str(self.home / 'backups'))['ok'])
        self.assertFalse(self.call('backup', configurations=False, files=False)['ok'])

    def test_reject_nested_symlink_restore_payload(self):
        result = self.call('backup')
        payload = self.dest / result['snapshot'] / 'payload'
        import shutil
        shutil.rmtree(payload / 'files')
        outside = self.root / 'outside'
        outside.mkdir()
        (outside / 'private').write_text('do not read')
        (payload / 'files').symlink_to(outside, target_is_directory=True)
        target = self.root / 'staging'
        target.mkdir()
        result = self.call('restore', snapshot=result['snapshot'], target=str(target))
        self.assertFalse(result['ok'], result)
        self.assertEqual(list(target.iterdir()), [])

    @unittest.skipUnless(__import__('shutil').which('age-keygen'), 'age-keygen not installed')
    def test_create_recovery_key_without_disclosing_or_overwriting_it(self):
        identity = self.root / 'recovery.key'
        result = self.call('create-key', identityFile=str(identity))
        self.assertTrue(result['ok'], result)
        self.assertRegex(result['ageRecipient'], '^age1[0-9a-z]{58}$')
        self.assertNotIn('AGE-SECRET-KEY', json.dumps(result))
        self.assertEqual(identity.stat().st_mode & 0o777, 0o600)
        original = identity.read_bytes()
        self.assertFalse(self.call('create-key', identityFile=str(identity))['ok'])
        self.assertEqual(identity.read_bytes(), original)
        self.assertFalse(self.call('create-key', identityFile=str(self.root / 'unsafe.txt'))['ok'])
        self.assertFalse((self.root / 'unsafe.txt').exists())

    @unittest.skipUnless(__import__('shutil').which('age-keygen'), 'age-keygen not installed')
    def test_encrypted_roundtrip_and_wrong_key(self):
        key = self.root / 'identity.txt'
        subprocess.run(['age-keygen', '-o', str(key)], check=True, capture_output=True)
        recipient = subprocess.run(['age-keygen', '-y', str(key)], check=True, capture_output=True, text=True).stdout.strip()
        result = self.call('backup', encrypted=True, ageRecipient=recipient)
        self.assertTrue(result['ok'], result)
        snapshot = self.dest / result['snapshot']
        self.assertFalse((snapshot / 'payload').exists())
        self.assertTrue((snapshot / 'payload.tar.age').is_file())
        target = self.root / 'decrypted'
        target.mkdir()
        restored = self.call('restore', snapshot=result['snapshot'], encrypted=True, identityFile=str(key), target=str(target))
        self.assertTrue(restored['ok'], restored)
        self.assertEqual((target / 'home/Documents/note.txt').read_text(), 'version one')
        wrong = self.root / 'wrong.txt'
        subprocess.run(['age-keygen', '-o', str(wrong)], check=True, capture_output=True)
        empty = self.root / 'wrong-restore'
        empty.mkdir()
        failed = self.call('restore', snapshot=result['snapshot'], identityFile=str(wrong), target=str(empty))
        self.assertFalse(failed['ok'], failed)
        self.assertEqual(list(empty.iterdir()), [])

    @unittest.skipUnless(__import__('shutil').which('rclone'), 'rclone not installed')
    def test_sftp_loopback_roundtrip(self):
        import socket
        import time
        import uuid
        with socket.socket() as sock:
            sock.bind(('127.0.0.1', 0))
            port = sock.getsockname()[1]
        config = self.root / 'rclone.conf'
        password = uuid.uuid4().hex
        env = dict(os.environ, HOME=str(self.home), XDG_CONFIG_HOME=str(self.home / '.config'), RCLONE_CONFIG=str(config))
        obscured = subprocess.run(['rclone', 'obscure', '-'], input=password, text=True, capture_output=True, env=env, check=True).stdout.strip()
        config.write_text(f'[fixture]\ntype = sftp\nhost = 127.0.0.1\nport = {port}\nuser = fixture\npass = {obscured}\ndisable_hashcheck = true\n')
        server = subprocess.Popen(['rclone', 'serve', 'sftp', str(self.dest), '--addr', f'127.0.0.1:{port}', '--user', 'fixture', '--pass', password, '--cache-dir', str(self.root / 'cache'), '--authorized-keys', str(self.root / 'unused')], env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        def stop():
            server.terminate()
            server.wait(timeout=10)
        self.addCleanup(stop)
        deadline = time.monotonic() + 10
        while True:
            try:
                with socket.create_connection(('127.0.0.1', port), timeout=0.1):
                    break
            except OSError:
                if time.monotonic() > deadline or server.poll() is not None:
                    self.fail('Fixture SFTP server did not start')
                time.sleep(0.05)
        self.extra_env = {'RCLONE_CONFIG': str(config)}
        self.req.update(transport='sftp', destination='fixture:repository')
        result = self.call('backup')
        self.assertTrue(result['ok'], result)
        history = self.call('history')
        self.assertEqual(history['snapshots'][0]['id'], result['snapshot'])
        target = self.root / 'sftp-restored'
        target.mkdir()
        restored = self.call('restore', snapshot=result['snapshot'], target=str(target))
        self.assertTrue(restored['ok'], restored)
        self.assertEqual((target / 'home/Documents/note.txt').read_text(), 'version one')

    def test_plan_capabilities_validation_and_mounted_transports(self):
        caps = self.call('capabilities')
        self.assertTrue(caps['tools']['git'])
        self.assertTrue(caps['plaintext'])
        before = list(self.dest.iterdir())
        plan = self.call('plan', transport='timecapsule')
        self.assertTrue(plan['ok'], plan)
        self.assertEqual(list(self.dest.iterdir()), before)
        self.assertIn('git', plan['required'])
        for changes in ({'paths': ['/etc']}, {'paths': []}, {'files': 'true'}, {'passwordFile': '/tmp/key'}, {'encrypted': True}, {'transport': 'sftp', 'destination': ':sftp:/etc'}, {'transport': 'sftp', 'destination': 'remote:../x'}):
            self.assertFalse(self.call('plan', **changes)['ok'], changes)
        for transport in ('smb', 'timecapsule'):
            result = self.call('backup', transport=transport)
            self.assertTrue(result['ok'], result)
        link = self.root / 'linkdest'
        link.symlink_to(self.dest, target_is_directory=True)
        self.assertFalse(self.call('backup', destination=str(link))['ok'])
        self.assertFalse(self.call('restore', snapshot='../../etc', target=str(self.root))['ok'])

    def test_reject_corrupt_snapshot_before_restore(self):
        result = self.call('backup')
        note = self.dest / result['snapshot'] / 'payload/files/Documents/note.txt'
        note.write_text('CORRUPT')
        target = self.root / 'corrupt-staging'
        target.mkdir()
        restored = self.call('restore', snapshot=result['snapshot'], target=str(target))
        self.assertFalse(restored['ok'], restored)
        self.assertEqual(list(target.iterdir()), [])

    def test_plain_roundtrip_versions(self):
        self.put('.local/state/omarchy/control-panel-profiles.json', '{"profiles": []}')
        first = self.call('backup')
        self.assertTrue(first['ok'], first)
        self.put('Documents/note.txt', 'version two')
        self.put('.config/hypr/hyprland.conf', 'theme=v2')
        second = self.call('backup')
        self.assertTrue(second['ok'], second)
        history = self.call('history')
        self.assertEqual([x['id'] for x in history['snapshots']], sorted([first['snapshot'], second['snapshot']]))
        target = self.root / 'restore'
        target.mkdir()
        restored = self.call('restore', snapshot=first['snapshot'], target=str(target))
        self.assertTrue(restored['ok'], restored)
        self.assertEqual((target / 'home/Documents/note.txt').read_text(), 'version one')
        self.assertEqual((target / 'home/.config/hypr/hyprland.conf').read_text(), 'theme=v1')
        self.assertIn('packages', json.loads((target / 'packages.json').read_text()))

    def test_configuration_backup_includes_control_panel_profiles(self):
        self.put('.local/state/omarchy/control-panel-profiles.json', '{"profiles": []}')
        result = self.call('backup', files=False)
        self.assertTrue(result['ok'], result)
        target = self.root / 'profiles-restore'
        target.mkdir()
        self.assertTrue(self.call('restore', snapshot=result['snapshot'], target=str(target))['ok'])
        self.assertTrue((target / 'home/.local/state/omarchy/control-panel-profiles.json').exists())

    def test_corrupt_previous_snapshot_is_not_used_for_new_backup(self):
        result = self.call('backup')
        config = self.dest / result['snapshot'] / 'payload/config/.git/config'
        config.write_text('[core]\nrepositoryformatversion = 999\n')
        result = self.call('backup')
        self.assertFalse(result['ok'], result)
        self.assertIn('integrity', result['error'].lower())


class DirectTimeCapsuleTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.home = self.root / 'home'
        self.home.mkdir()
        note = self.home / 'Documents/note.txt'
        note.parent.mkdir()
        note.write_text('direct smb payload')
        self.remote = self.root / 'remote'
        self.remote.mkdir()
        self.backend = load_backend()
        self.target = {
            'host': 'capsule.local', 'address': '192.168.50.15',
            'mac': '5C:96:9D:6D:B2:4A', 'user': 'alice', 'share': 'Data',
            'savedCredential': True,
        }

    def remote_call(self, action, request):
        self.assertEqual({key: request[key] for key in self.target}, self.target)
        if action == 'capabilities':
            return {'smbclient': True, 'secretService': True}
        if action == 'upload':
            import shutil
            shutil.copy2(request['payloadFile'], self.remote / (request['snapshot'] + '.payload.tar.age'))
            shutil.copy2(request['manifestFile'], self.remote / (request['snapshot'] + '.manifest.json'))
            return {'uploaded': True, 'snapshot': request['snapshot']}
        if action == 'list':
            return {'snapshots': [json.loads(path.read_text()) for path in sorted(self.remote.glob('*.manifest.json'))]}
        if action == 'download':
            import shutil
            destination = Path(request['destination'])
            shutil.copy2(self.remote / (request['snapshot'] + '.payload.tar.age'), destination / 'payload.tar.age')
            shutil.copy2(self.remote / (request['snapshot'] + '.manifest.json'), destination / 'manifest.json')
            return {'downloaded': True, 'snapshot': request['snapshot']}
        self.fail(action)

    def test_encrypted_full_snapshot_backup_history_and_restore_use_direct_transport(self):
        fake_bin = self.root / 'bin'
        fake_bin.mkdir()
        age = fake_bin / 'age'
        age.write_text('#!' + sys.executable + '\nimport shutil,sys\na=sys.argv[1:]; shutil.copyfile(a[-1], a[a.index("-o")+1])\n')
        age.chmod(0o700)
        request = {
            'home': str(self.home), 'destination': self.target,
            'transport': 'timecapsule', 'configurations': False, 'files': True,
            'encrypted': True, 'ageRecipient': 'age1' + 'a' * 58,
        }
        old_path = os.environ.get('PATH', '')
        with patch.dict(os.environ, {'PATH': str(fake_bin) + os.pathsep + old_path}), \
             patch.object(self.backend, 'invoke_timecapsule', side_effect=self.remote_call):
            backed_up = self.backend.main('backup', dict(request))
            manifest = backed_up['manifest']
            self.assertRegex(manifest['payloadSha256'], '^[a-f0-9]{64}$')
            self.assertGreater(manifest['payloadSize'], 0)
            history = self.backend.main('history', dict(request))
            self.assertEqual([item['id'] for item in history['snapshots']], [backed_up['snapshot']])
            destination = self.root / 'restore'
            destination.mkdir()
            identity = self.root / 'identity.key'
            identity.write_text('fixture identity')
            restored = self.backend.main('restore', dict(request, snapshot=backed_up['snapshot'], target=str(destination), identityFile=str(identity)))
        self.assertEqual(restored['snapshot'], backed_up['snapshot'])
        self.assertEqual((destination / 'home/Documents/note.txt').read_text(), 'direct smb payload')

    def test_direct_timecapsule_rejects_plaintext_and_unsaved_or_json_credentials(self):
        base = {'home': str(self.home), 'destination': self.target, 'transport': 'timecapsule', 'configurations': False, 'files': True}
        for destination in (self.target | {'savedCredential': False}, self.target | {'password': 'secret'}):
            with self.subTest(destination=destination), self.assertRaises(ValueError):
                self.backend.main('plan', dict(base, destination=destination, encrypted=True, ageRecipient='age1' + 'a' * 58))
        with self.assertRaisesRegex(ValueError, 'encrypted'):
            self.backend.main('plan', dict(base, encrypted=False))


if __name__ == '__main__':
    unittest.main()
