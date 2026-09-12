"""Isolated helper tests: no real discovery, mounts, or desktop launches."""
import importlib.machinery
import importlib.util
from pathlib import Path
import subprocess
import unittest
from unittest.mock import patch
import json

SCRIPT = Path(__file__).resolve().parents[1] / 'bin' / 'backup-connection'


def load_helper():
    loader = importlib.machinery.SourceFileLoader('backup_connection', str(SCRIPT))
    spec = importlib.util.spec_from_loader(loader.name, loader)
    assert spec is not None
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    return module


class ConnectionTests(unittest.TestCase):
    def test_timecapsule_opens_native_auth_without_claiming_mount(self):
        self.assertTrue(SCRIPT.exists(), 'Connection helper is not implemented')
        helper = load_helper()
        with patch.object(helper.shutil, 'which', return_value='/mock/gio'), patch.object(helper.subprocess, 'run', return_value=subprocess.CompletedProcess([], 0)) as run:
            result = helper.main('connect', {'transport': 'timecapsule', 'host': 'capsule.local', 'share': 'Family Disk'})
        self.assertEqual(result, {'uri': 'smb://capsule.local/Family%20Disk', 'opened': True, 'connected': False})
        self.assertEqual(run.call_args.args[0], ['gio', 'open', 'smb://capsule.local/Family%20Disk'])
        self.assertLessEqual(run.call_args.kwargs['timeout'], 15)
        self.assertFalse(run.call_args.kwargs.get('shell', False))


class ValidationTests(unittest.TestCase):
    def test_validation_and_sftp_uri(self):
        h = load_helper()
        with patch.object(h.subprocess, 'run', return_value=subprocess.CompletedProcess([], 0)) as run:
            result = h.main('connect', {'transport': 'sftp', 'host': 'server.local', 'user': 'alice', 'port': 2222})
            self.assertEqual(result['uri'], 'sftp://alice@server.local:2222/')
            self.assertFalse(result['connected'])
            run.reset_mock()
            for fields in ({'host': 'smb://u:secret@host'}, {'host': 'u@host'}, {'host': '-bad'}, {'host': 'bad\nname'}, {'host': 'host/path'}, {'user': 'u:secret'}, {'password': 'secret'}, {'share': '../x'}, {'port': True}, {'port': 0}, {'port': '22'}, {'transport': 'ftp'}, {'uri': 'smb://host'}):
                with self.subTest(fields=fields), self.assertRaises(h.ConnectionError):
                    h.main('connect', {'transport': 'smb', 'host': 'valid.local', **fields})
            with self.assertRaisesRegex(h.ConnectionError, 'host_required'):
                h.main('connect', {'transport': 'smb'})
            run.assert_not_called()

    def test_cli_rejects_secrets_without_echoing_them(self):
        result = subprocess.run([str(SCRIPT), 'connect'], input='{"transport":"smb","password":"do-not-echo"}', text=True, capture_output=True)
        self.assertEqual(result.returncode, 1)
        self.assertNotIn('do-not-echo', result.stdout + result.stderr)
        import json
        self.assertFalse(json.loads(result.stdout)['ok'])


class DiscoveryTests(unittest.TestCase):
    def test_discovery_decodes_deduplicates_filters(self):
        h = load_helper()
        listing = '\n'.join([r'=;eth0;IPv4;Family\032Capsule;_smb._tcp;local;capsule.local;192.0.2.1;445;', r'=;eth0;IPv6;Family\032Capsule;_smb._tcp;local;capsule.local;::1;445;', r'=;eth0;IPv4;Dev\059box;_sftp-ssh._tcp;local;dev.local;192.0.2.2;22;', '=;eth0;IPv4;Web;_http._tcp;local;web.local;192.0.2.3;80;'])
        with patch.object(h.subprocess, 'run', return_value=subprocess.CompletedProcess([], 0, listing)) as run:
            result = h.main('discover', {'transport': 'timecapsule'})
        self.assertEqual(result['devices'], [{'name': 'Family Capsule', 'host': 'capsule.local', 'port': 445, 'transport': 'smb'}])
        self.assertEqual(run.call_args.args[0], ['avahi-browse', '-artp'])
        self.assertLessEqual(run.call_args.kwargs['timeout'], 10)
        with patch.object(h.subprocess, 'run', return_value=subprocess.CompletedProcess([], 0, listing)):
            self.assertIn('Dev;box', [d['name'] for d in h.main('discover', {})['devices']])

    def test_missing_capabilities_and_timeout_codes(self):
        h = load_helper()
        with patch.object(h.shutil, 'which', return_value=None), patch.object(h.Path, 'is_file', return_value=False):
            caps = h.main('capabilities', {'transport': 'smb'})
        self.assertIn('gio', caps['missing'])
        self.assertIn('gvfs-smb', caps['missingPackages'])
        with patch.object(h.subprocess, 'run', side_effect=subprocess.TimeoutExpired('avahi-browse', 8)):
            with self.assertRaisesRegex(h.ConnectionError, '^timeout$'):
                h.main('discover', {})


class FolderTests(unittest.TestCase):
    def setUp(self):
        import tempfile
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.base = Path(self.tmp.name)
        self.home = self.base / 'home'
        self.home.mkdir()
        self.root = self.base / 'run space' / 'gvfs'
        self.root.mkdir(parents=True)
        self.smb = self.root / 'smb-share:server=capsule.local,share=Family Disk'
        self.smb.mkdir()
        self.sftp = self.root / 'sftp:host=dev.local,user=alice'
        self.sftp.mkdir()
        self.stale = self.root / 'smb-share:server=gone.local,share=Lost'
        self.stale.mkdir()
        self.mountinfo = self.base / 'mountinfo'
        self.mountinfo.write_text('42 1 0:80 / ' + str(self.root).replace(' ', r'\040') + ' rw - fuse.gvfsd-fuse gvfsd-fuse rw\n')
        self.h = load_helper()
        self.addCleanup(patch.stopall)
        patch.object(self.h, 'gvfs_root', return_value=self.root).start()
        patch.object(self.h, 'read_mountinfo', side_effect=lambda: self.mountinfo.read_text()).start()
        patch.object(self.h.Path, 'home', return_value=self.home).start()
        self.command_mock = patch.object(self.h.subprocess, 'run', return_value=subprocess.CompletedProcess([], 0, 'Mount(0): Family Disk -> smb://capsule.local/Family%20Disk/\nMount(1): Dev -> sftp://alice@dev.local/\n')).start()

    def test_folders_require_kernel_mount_and_gio_authority(self):
        result = self.h.main('folders', {'transport': 'timecapsule', 'host': 'capsule.local'})
        self.assertEqual(result, {'folders': [{'name': 'Family Disk', 'path': str(self.smb), 'host': 'capsule.local', 'transport': 'smb'}]})
        self.assertEqual(self.command_mock.call_args.args[0], ['gio', 'mount', '-li'])
        self.assertEqual(len(self.h.main('folders', {})['folders']), 2)
        self.mountinfo.write_text('')
        self.assertEqual(self.h.main('folders', {})['folders'], [])

    def test_verify_matches_transport_host_and_rejects_stale(self):
        sub = self.smb / 'Backups'
        sub.mkdir()
        self.assertEqual(self.h.main('verify', {'transport': 'timecapsule', 'host': 'capsule.local', 'path': str(sub)}), {'destination': str(sub), 'transport': 'local'})
        for fields in ({'transport': 'sftp', 'path': str(sub)}, {'transport': 'smb', 'host': 'other.local', 'path': str(sub)}, {'transport': 'smb', 'path': str(self.stale)}, {'transport': 'smb', 'path': str(self.base)}):
            with self.subTest(fields=fields), self.assertRaises(self.h.ConnectionError):
                self.h.main('verify', fields)
        self.mountinfo.write_text('')
        with self.assertRaisesRegex(self.h.ConnectionError, 'not_connected'):
            self.h.main('verify', {'path': str(sub)})

    def test_verify_local_read_only_home_symlink_and_missing(self):
        local = self.base / 'external'
        local.mkdir()
        before = list(local.iterdir())
        self.assertEqual(self.h.main('verify', {'path': str(local)}), {'destination': str(local), 'transport': 'local'})
        self.assertEqual(list(local.iterdir()), before)
        self.command_mock.assert_not_called()
        link = self.base / 'link'
        link.symlink_to(local, target_is_directory=True)
        for path, reason in ((self.home, 'destination_inside_home'), (self.base, 'destination_contains_home'), (link, 'symlink_path'), (local / 'missing', 'directory_missing'), ('relative', 'invalid_path'), ('/' + str(self.home), 'invalid_path'), (str(local) + '/../external', 'invalid_path')):
            with self.subTest(path=path), self.assertRaisesRegex(self.h.ConnectionError, '^' + reason + '$'):
                self.h.main('verify', {'path': str(path)})

    def test_native_picker_uri_resolves_only_to_verified_mount(self):
        sub = self.smb / 'My Backups'
        sub.mkdir()
        result = self.h.main('verify', {'transport': 'timecapsule', 'host': 'capsule.local', 'path': 'smb://capsule.local/Family%20Disk/My%20Backups'})
        self.assertEqual(result, {'destination': str(sub), 'transport': 'local'})
        self.assertEqual(self.h.main('verify', {'transport': 'sftp', 'path': 'sftp://alice@dev.local/'}), {'destination': str(self.sftp), 'transport': 'local'})
        for uri in ('smb://capsule.local/Family%20Disk/%2e%2e', 'smb://gone.local/Lost', 'sftp://alice:secret@dev.local/'):
            with self.assertRaises(self.h.ConnectionError):
                self.h.main('verify', {'path': uri})


class LocalDeviceTests(unittest.TestCase):
    def test_lists_only_mountable_external_filesystems(self):
        h = load_helper()
        listing = {'blockdevices': [
            {'name': 'nvme0n1', 'path': '/dev/nvme0n1', 'type': 'disk', 'rm': False,
             'hotplug': False, 'tran': 'nvme', 'children': [
                 {'name': 'nvme0n1p1', 'path': '/dev/nvme0n1p1', 'type': 'part',
                  'fstype': 'btrfs', 'label': 'system', 'size': '100G', 'mountpoints': ['/']} ]},
            {'name': 'sda', 'path': '/dev/sda', 'type': 'disk', 'rm': True,
             'hotplug': True, 'tran': 'usb', 'children': [
                 {'name': 'sda1', 'path': '/dev/sda1', 'type': 'part', 'fstype': 'exfat',
                  'label': 'BACKUP', 'uuid': 'A1', 'size': '64G', 'mountpoints': [None]} ]},
            {'name': 'sdb', 'path': '/dev/sdb', 'type': 'disk', 'rm': False,
             'hotplug': True, 'tran': 'usb', 'children': [
                 {'name': 'sdb1', 'path': '/dev/sdb1', 'type': 'part', 'fstype': 'ext4',
                  'label': '', 'uuid': 'B2', 'size': '1T', 'mountpoints': ['/run/media/a/disk']} ]}
        ]}
        with patch.object(h, 'command', return_value=json.dumps(listing)) as command:
            result = h.main('local-devices', {})
        self.assertEqual(result['devices'], [
            {'device': '/dev/sda1', 'name': 'BACKUP', 'filesystem': 'exfat', 'size': '64G', 'uuid': 'A1', 'mounted': False, 'mountpoint': ''},
            {'device': '/dev/sdb1', 'name': 'sdb1', 'filesystem': 'ext4', 'size': '1T', 'uuid': 'B2', 'mounted': True, 'mountpoint': '/run/media/a/disk'}
        ])
        self.assertEqual(command.call_args.args[0][0:2], ['lsblk', '-J'])

    def test_mount_revalidates_device_and_returns_authoritative_mountpoint(self):
        h = load_helper()
        import tempfile
        mounted_at = tempfile.TemporaryDirectory()
        self.addCleanup(mounted_at.cleanup)
        before = {'devices': [{'device': '/dev/sda1', 'name': 'BACKUP', 'filesystem': 'exfat',
                               'size': '64G', 'uuid': 'A1', 'mounted': False, 'mountpoint': ''}]}
        after = {'devices': [{**before['devices'][0], 'mounted': True,
                              'mountpoint': mounted_at.name}]}
        with patch.object(h, 'local_devices', side_effect=[before, after]), \
             patch.object(h, 'command', return_value='') as command:
            result = h.main('mount', {'device': '/dev/sda1'})
        self.assertEqual(result, {'device': '/dev/sda1', 'destination': mounted_at.name, 'mounted': True})
        self.assertEqual(command.call_args.args[0], ['udisksctl', 'mount', '--block-device', '/dev/sda1', '--no-user-interaction'])

    def test_mount_rejects_internal_or_unknown_device(self):
        h = load_helper()
        with patch.object(h, 'local_devices', return_value={'devices': []}), \
             patch.object(h, 'command') as command, self.assertRaisesRegex(h.ConnectionError, '^invalid_device$'):
            h.main('mount', {'device': '/dev/nvme0n1p2'})
        command.assert_not_called()


class HardeningTests(unittest.TestCase):
    def test_ipv6_scope_cannot_inject_uri_credentials(self):
        h = load_helper()
        with patch.object(h.subprocess, 'run') as run:
            with self.assertRaisesRegex(h.ConnectionError, 'invalid_host'):
                h.main('connect', {'transport': 'sftp', 'host': 'fe80::1%bad@evil'})
            run.assert_not_called()

    def test_credential_url_in_unused_path_is_rejected(self):
        h = load_helper()
        with patch.object(h.subprocess, 'run', return_value=subprocess.CompletedProcess([], 0)) as run:
            with self.assertRaisesRegex(h.ConnectionError, 'invalid_path'):
                h.main('connect', {'transport': 'smb', 'host': 'nas.local', 'path': 'smb://u:secret@host/share'})
            run.assert_not_called()

    def test_cli_uses_only_mock_gio_executable(self):
        import json
        import tempfile
        import sys
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            gio = root / 'gio'
            gio.write_text('#!' + sys.executable + '\nimport json, os, sys\nfrom pathlib import Path\nPath(os.environ["CALL_LOG"]).write_text(json.dumps(sys.argv[1:]))\n')
            gio.chmod(0o700)
            env = {'PATH': tmp, 'HOME': tmp, 'XDG_RUNTIME_DIR': tmp, 'CALL_LOG': str(root / 'calls'), 'LC_ALL': 'C'}
            result = subprocess.run([sys.executable, str(SCRIPT), 'connect'], input=json.dumps({'transport': 'sftp', 'host': '2001:db8::1', 'user': 'alice', 'port': 2222}), text=True, capture_output=True, env=env, timeout=5)
            self.assertEqual(result.returncode, 0, result.stdout)
            response = json.loads(result.stdout)
            self.assertTrue(response['ok'])
            self.assertFalse(response['connected'])
            self.assertEqual(json.loads((root / 'calls').read_text()), ['open', 'sftp://alice@[2001:db8::1]:2222/'])
            self.assertEqual(result.stderr, '')

    def test_gio_machine_output_uses_c_locale(self):
        h = load_helper()
        with patch.object(h.subprocess, 'run', return_value=subprocess.CompletedProcess([], 0, '')) as run:
            h.live_mounts()
        self.assertEqual(run.call_args.kwargs.get('env', {}).get('LC_ALL'), 'C')

    def test_avahi_unicode_and_malformed_records(self):
        h = load_helper()
        listing = '\n'.join([r'=;e;IPv4;Caf\195\169;_smb._tcp;local;nas\046local;192.0.2.1;445;', r'=;e;IPv4;bad\999;_smb._tcp;local;bad.local;192.0.2.2;445;', r'=;e;IPv4;bad\010name;_smb._tcp;local;bad.local;192.0.2.2;445;', '=;e;IPv4;bad;_smb._tcp;local;u:secret@bad;192.0.2.2;445;'])
        with patch.object(h.subprocess, 'run', return_value=subprocess.CompletedProcess([], 0, listing)):
            self.assertEqual(h.main('discover', {})['devices'], [{'name': 'Café', 'host': 'nas.local', 'port': 445, 'transport': 'smb'}])

    def test_command_errors_are_redacted(self):
        h = load_helper()
        for failure, reason in ((FileNotFoundError('secret'), 'missing_tool'), (subprocess.TimeoutExpired('secret', 10), 'timeout'), (OSError('secret'), 'command_failed')):
            with self.subTest(reason=reason), patch.object(h.subprocess, 'run', side_effect=failure), self.assertRaisesRegex(h.ConnectionError, '^' + reason + '$'):
                h.main('connect', {'transport': 'smb', 'host': 'nas.local'})
        with patch.object(h.subprocess, 'run', return_value=subprocess.CompletedProcess([], 1, 'secret')), self.assertRaisesRegex(h.ConnectionError, '^command_failed$'):
            h.main('connect', {'transport': 'smb', 'host': 'nas.local'})


if __name__ == '__main__':
    unittest.main()
