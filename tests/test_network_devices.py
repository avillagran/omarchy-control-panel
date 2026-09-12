"""Fixture-only tests for the generic network-devices helper."""
import importlib.machinery
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

SCRIPT = Path(__file__).resolve().parents[1] / "bin" / "network-devices"


def load_helper():
    loader = importlib.machinery.SourceFileLoader("network_devices", str(SCRIPT))
    spec = importlib.util.spec_from_loader(loader.name, loader)
    assert spec is not None
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    return module


AVAHI = "\n".join([
    r'=;enp1s0;IPv4;VQ TimeCapsule;Microsoft Windows Network;local;VQ-TimeCapsule.local;169.254.194.141;445;"waMA=5C-96-9D-6D-B2-4A"',
    r'=;enp1s0;IPv4;VQ TimeCapsule;Apple File Sharing;local;VQ-TimeCapsule.local;169.254.194.141;548;"mac=5c-96-9d-6d-b2-4a"',
    r'=;enp1s0;IPv4;VQ Backup;Apple TimeMachine;local;VQ-TimeCapsule.local;169.254.194.141;9;"sys=waMA=5C:96:9D:6D:B2:4A"',
    r'=;enp1s0;IPv4;VQ TimeCapsule;Apple AirPort;local;VQ-TimeCapsule.local;169.254.194.141;5009;"waMA=5C-96-9D-6D-B2-4A"',
    r'=;enp1s0;IPv4;Living\032Room;_googlecast._tcp;local;cast.local;192.168.1.40;8009;"id=not-a-secret"',
    r'=;enp1s0;IPv4;Dev\059Box;_sftp-ssh._tcp;local;dev.local;192.168.1.30;22;',
    r'=;enp1s0;IPv4;Sensor;_example-sensor._udp;local;sensor.local;192.168.1.50;7777;',
])
NEIGH = [
    {"dst": "192.168.1.15", "dev": "enp1s0", "lladdr": "5c:96:9d:6d:b2:4a", "state": ["REACHABLE"]},
    {"dst": "192.168.1.20", "dev": "enp1s0", "lladdr": "AA:BB:CC:DD:EE:FF", "state": ["STALE"]},
    {"dst": "203.0.113.9", "dev": "tun0", "lladdr": "00:11:22:33:44:55", "state": ["REACHABLE"]},
]
ROUTES = [
    {"dst": "192.168.1.0/24", "dev": "enp1s0", "protocol": "kernel", "scope": "link", "prefsrc": "192.168.1.10"},
    {"dst": "203.0.113.0/24", "dev": "tun0", "protocol": "static", "gateway": "10.0.0.1"},
    {"dst": "default", "dev": "enp1s0", "gateway": "192.168.1.1"},
]
ADDRESSES = [{"ifname": "enp1s0", "addr_info": [{"family": "inet", "local": "192.168.1.10", "prefixlen": 24, "scope": "global"}]}]


class NetworkDeviceTests(unittest.TestCase):
    def setUp(self):
        self.assertTrue(SCRIPT.exists(), "network-devices helper is not implemented")
        self.h = load_helper()

    def fixture_command(self, argv, **_kwargs):
        if argv[:2] == ["avahi-browse", "-artp"]:
            return subprocess.CompletedProcess(argv, 0, AVAHI, "")
        if argv == ["ip", "-j", "neigh"]:
            return subprocess.CompletedProcess(argv, 0, json.dumps(NEIGH), "")
        if argv == ["ip", "-j", "route", "show"]:
            return subprocess.CompletedProcess(argv, 0, json.dumps(ROUTES), "")
        if argv == ["ip", "-j", "address", "show"]:
            return subprocess.CompletedProcess(argv, 0, json.dumps(ADDRESSES), "")
        raise AssertionError(f"unexpected command: {argv}")

    def scan(self, request=None):
        with patch.object(self.h.subprocess, "run", side_effect=self.fixture_command), \
             patch.object(self.h, "resolve_hostnames", return_value={"192.168.1.20": "printer.local"}):
            return self.h.main("scan", request or {})

    def test_scan_reconciles_time_capsule_link_local_address_by_txt_mac(self):
        result = self.scan()
        capsule = next(d for d in result["devices"] if d["mac"] == "5C:96:9D:6D:B2:4A")
        self.assertEqual(capsule["host"], "vq-timecapsule.local")
        self.assertEqual(capsule["addresses"][0], "192.168.1.15")
        self.assertIn("169.254.194.141", capsule["addresses"])
        self.assertEqual(capsule["kind"], "timeCapsule")
        self.assertEqual(
            capsule["services"],
            [
                {"protocol": "afp", "port": 548, "name": "Apple File Sharing"},
                {"protocol": "airport", "port": 5009, "name": "Apple AirPort"},
                {"protocol": "smb", "port": 445, "name": "Microsoft Windows Network"},
                {"protocol": "timemachine", "port": 9, "name": "Apple TimeMachine"},
            ],
        )
        self.assertEqual(capsule["connection"]["preferredAddress"], "192.168.1.15")
        self.assertFalse(capsule["connection"]["probed"])

    def test_scan_includes_common_services_and_unnamed_neighbors_deterministically(self):
        first = self.scan()["devices"]
        second = self.scan()["devices"]
        self.assertEqual(first, second)
        self.assertEqual(len({d["id"] for d in first}), len(first))
        printer = next(d for d in first if d["mac"] == "AA:BB:CC:DD:EE:FF")
        self.assertEqual((printer["name"], printer["host"], printer["addresses"]),
                         ("printer", "printer.local", ["192.168.1.20"]))
        self.assertEqual(next(d for d in first if d["host"] == "dev.local")["services"][0]["protocol"], "sftp")
        cast = next(d for d in first if d["host"] == "cast.local")
        self.assertEqual(cast["kind"], "chromecast")
        sensor = next(d for d in first if d["host"] == "sensor.local")
        self.assertEqual(sensor["services"], [{"protocol": "example-sensor", "port": 7777, "name": "_example-sensor._udp"}])
        self.assertNotIn("txt", json.dumps(first).lower())
        self.assertNotIn("not-a-secret", json.dumps(first))

    def test_deep_scan_only_probes_direct_private_subnet_and_detects_legacy_smb(self):
        seen = []
        def probe(address, port, timeout=0):
            seen.append((address, port, timeout))
            return address == "192.168.1.15" and port == 445
        with patch.object(self.h.subprocess, "run", side_effect=self.fixture_command), \
             patch.object(self.h, "resolve_hostnames", return_value={}), \
             patch.object(self.h, "tcp_probe", side_effect=probe), \
             patch.object(self.h, "probe_smb", return_value={"available": True, "legacySmb": True, "authenticationRequired": True}) as smb:
            result = self.h.main("scan", {"deep": True})
        self.assertTrue(seen)
        self.assertTrue(all(address.startswith("192.168.1.") for address, _port, _timeout in seen))
        self.assertNotIn("203.0.113.9", [address for address, _port, _timeout in seen])
        capsule = next(d for d in result["devices"] if d["kind"] == "timeCapsule")
        self.assertTrue(capsule["connection"]["legacySmb"])
        self.assertTrue(capsule["connection"]["probed"])
        smb.assert_called_once_with("192.168.1.15")

    def test_smb_probe_uses_process_scoped_nt1_config_only(self):
        calls = []
        def run(argv, **kwargs):
            calls.append((argv, kwargs))
            if len(calls) == 1:
                return subprocess.CompletedProcess(argv, 1, "", "NT_STATUS_INVALID_NETWORK_RESPONSE")
            config = Path(kwargs["env"]["SMB_CONF_PATH"])
            self.assertIn("client min protocol = NT1", config.read_text())
            self.assertIn("client max protocol = NT1", config.read_text())
            self.assertIn("client use spnego = no", config.read_text())
            self.assertIn("client ntlmv2 auth = no", config.read_text())
            return subprocess.CompletedProcess(argv, 0, "IPC$ Disk IPC Service\n", "")
        with patch.object(self.h.shutil, "which", return_value="/mock/smbclient"), \
             patch.object(self.h.subprocess, "run", side_effect=run):
            status = self.h.probe_smb("192.168.1.15")
        self.assertTrue(status["legacySmb"])
        self.assertEqual(calls[0][0], ["smbclient", "-L", "//192.168.1.15", "-N"])
        self.assertEqual(calls[1][0], ["smbclient", "-L", "//192.168.1.15", "-N"])
        self.assertIn("SMB_CONF_PATH", calls[1][1]["env"])
        self.assertNotIn("smb.conf", json.dumps(calls))
        self.assertTrue(all(call[1]["timeout"] <= 5 for call in calls))

    def test_nmblookup_is_bounded_fallback_for_neighbor_name_and_mac(self):
        output = "Looking up status of 192.168.1.15\n VQ-TIMECAPSULE <00> - B <ACTIVE>\n MAC Address = 5C-96-9D-6D-B2-4A\n"
        with patch.object(self.h.subprocess, "run", return_value=subprocess.CompletedProcess([], 0, output, "")) as run:
            self.assertEqual(self.h.nmblookup("192.168.1.15"), ("VQ-TIMECAPSULE", "5C:96:9D:6D:B2:4A"))
        self.assertEqual(run.call_args.args[0], ["nmblookup", "-A", "192.168.1.15"])
        self.assertLessEqual(run.call_args.kwargs["timeout"], 3)

    def test_connect_opens_credential_free_uris_but_blocks_afp_and_legacy_time_capsule(self):
        device = {"host": "nas.local", "addresses": ["192.168.1.5"], "kind": "nas", "connection": {}}
        with patch.object(self.h.subprocess, "run", return_value=subprocess.CompletedProcess([], 0)) as run:
            result = self.h.main("connect", {"device": device, "protocol": "smb", "share": "Family Disk"})
            self.assertEqual(result, {"uri": "smb://nas.local/Family%20Disk", "opened": True, "connected": False})
            self.assertEqual(run.call_args.args[0], ["gio", "open", "smb://nas.local/Family%20Disk"])
        afp = self.h.main("connect", {"device": device, "protocol": "afp"})
        self.assertEqual(afp["reason"], "afp_connector_unavailable")
        self.assertFalse(afp["supported"])
        legacy = dict(device, kind="timeCapsule", connection={"legacySmb": True})
        blocked = self.h.main("connect", {"device": legacy, "protocol": "smb"})
        self.assertEqual(blocked["reason"], "legacy_smb_requires_adapter")
        self.assertFalse(blocked["opened"])

    def test_connect_brackets_ipv6_and_cli_scan_is_json_without_network_tools(self):
        device = {"host": "2001:db8::15", "addresses": ["2001:db8::15"], "kind": "computer", "connection": {}}
        with patch.object(self.h.subprocess, "run", return_value=subprocess.CompletedProcess([], 0)) as run:
            result = self.h.main("connect", {"device": device, "protocol": "sftp", "user": "alice"})
        self.assertEqual(result["uri"], "sftp://alice@[2001:db8::15]:22/")
        self.assertEqual(run.call_args.args[0], ["gio", "open", "sftp://alice@[2001:db8::15]:22/"])
        with tempfile.TemporaryDirectory() as tmp:
            env = {"PATH": tmp, "HOME": tmp, "XDG_RUNTIME_DIR": tmp, "LC_ALL": "C"}
            cli = subprocess.run([sys.executable, str(SCRIPT), "scan"], input="{}", text=True,
                                 capture_output=True, env=env, timeout=5)
        self.assertEqual(cli.returncode, 0, cli.stderr)
        self.assertEqual(json.loads(cli.stdout)["devices"], [])

    def test_mounts_require_kernel_and_gio_evidence_and_disconnect_exact_live_uri(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp) / "gvfs"
            root.mkdir()
            folder = root / "smb-share:server=nas.local,share=Data"
            folder.mkdir()
            mountinfo = f"40 1 0:70 / {root} rw - fuse.gvfsd-fuse gvfsd-fuse rw\n"
            gio_listing = "Mount(0): Data -> smb://nas.local/Data/\n"
            def run(argv, **_kwargs):
                if argv == ["gio", "mount", "-li"]:
                    return subprocess.CompletedProcess(argv, 0, gio_listing, "")
                if argv == ["gio", "mount", "-u", "smb://nas.local/Data/"]:
                    return subprocess.CompletedProcess(argv, 0, "", "")
                raise AssertionError(argv)
            with patch.object(self.h, "gvfs_root", return_value=root), \
                 patch.object(self.h, "read_mountinfo", return_value=mountinfo), \
                 patch.object(self.h.subprocess, "run", side_effect=run):
                mounts = self.h.main("mounts", {})["mounts"]
                self.assertEqual(mounts, [{"uri": "smb://nas.local/Data/", "protocol": "smb", "host": "nas.local", "share": "Data", "path": str(folder)}])
                self.assertEqual(self.h.main("disconnect", {"uri": mounts[0]["uri"]}), {"disconnected": True, "uri": mounts[0]["uri"]})
                with self.assertRaisesRegex(self.h.DeviceError, "not_mounted"):
                    self.h.main("disconnect", {"uri": "smb://other.local/Data/"})

    def test_validation_rejects_secrets_and_cli_never_echoes_them(self):
        h = self.h
        for request in ({"password": "secret"}, {"device": {"host": "user:secret@nas.local"}, "protocol": "smb"}, {"device": {"host": "nas.local"}, "protocol": "ftp"}, {"deep": "yes"}):
            with self.subTest(request=request), self.assertRaises(h.DeviceError):
                h.main("connect" if "device" in request else "scan", request)
        result = subprocess.run([sys.executable, str(SCRIPT), "connect"], input='{"password":"do-not-echo"}', text=True, capture_output=True, timeout=5)
        self.assertEqual(result.returncode, 1)
        self.assertNotIn("do-not-echo", result.stdout + result.stderr)
        self.assertFalse(json.loads(result.stdout)["ok"])


if __name__ == "__main__":
    unittest.main()
