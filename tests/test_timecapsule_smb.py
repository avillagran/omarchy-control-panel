"""Isolated tests for the direct legacy Time Capsule SMB helper."""
import importlib.machinery
import importlib.util
import io
import json
import os
from pathlib import Path
import stat
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

SCRIPT = Path(__file__).resolve().parents[1] / "bin" / "timecapsule-smb"
TARGET = {
    "host": "capsule.local",
    "address": "192.168.50.15",
    "mac": "5C:96:9D:6D:B2:4A",
}
AUTH = {**TARGET, "user": "alice"}


def load_helper():
    loader = importlib.machinery.SourceFileLoader("timecapsule_smb", str(SCRIPT))
    spec = importlib.util.spec_from_loader(loader.name, loader)
    assert spec is not None
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    return module


class CapabilityTests(unittest.TestCase):
    def test_capabilities_report_tools_and_current_limitations(self):
        self.assertTrue(SCRIPT.exists(), "timecapsule-smb helper is not implemented")
        helper = load_helper()
        with patch.object(helper.shutil, "which", side_effect=lambda name: "/mock/" + name if name == "smbclient" else None):
            result = helper.main("capabilities", {})
        self.assertTrue(result["smbclient"])
        self.assertFalse(result["secretService"])
        self.assertFalse(result["mountSupported"])
        self.assertTrue(result["uploadSupported"])
        self.assertTrue(result["downloadSupported"])
        self.assertTrue(result["historySupported"])
        self.assertEqual(result["connectedMeaning"], "authenticated_protocol_and_share_accessible")


class TargetValidationTests(unittest.TestCase):
    def setUp(self):
        self.h = load_helper()

    @staticmethod
    def network_json(argv):
        if argv == ["ip", "-j", "route", "show"]:
            return [{"dst": "192.168.50.0/24", "dev": "eth0", "scope": "link", "protocol": "kernel"}]
        if argv == ["ip", "-j", "address", "show"]:
            return [{"ifname": "eth0", "addr_info": [{"family": "inet", "local": "192.168.50.2", "prefixlen": 24, "scope": "global"}]}]
        if argv == ["ip", "-j", "neigh", "show", "192.168.50.15"]:
            return [{"dst": "192.168.50.15", "dev": "eth0", "lladdr": "5c:96:9d:6d:b2:4a", "state": ["REACHABLE"]}]
        raise AssertionError(argv)

    def test_target_must_be_current_direct_private_neighbor_with_expected_mac(self):
        with patch.object(self.h, "system_json", side_effect=self.network_json):
            self.assertEqual(self.h.validate_target(TARGET), TARGET)
            for changed, reason in (({"address": "8.8.8.8"}, "unsafe_address"),
                                    ({"address": "127.0.0.1"}, "unsafe_address"),
                                    ({"mac": "00:11:22:33:44:55"}, "mac_mismatch"),
                                    ({"host": "capsule.-local"}, "invalid_host"),
                                    ({"host": "u:secret@capsule.local"}, "invalid_host")):
                with self.subTest(changed=changed), self.assertRaisesRegex(self.h.HelperError, "^" + reason + "$"), patch.object(self.h, "system_json", side_effect=self.network_json):
                    self.h.validate_target({**TARGET, **changed})

    def test_link_local_requires_a_current_direct_link_local_route(self):
        target = {**TARGET, "address": "169.254.20.5"}
        def network(argv):
            if argv == ["ip", "-j", "route", "show"]:
                return [{"dst": "169.254.0.0/16", "dev": "eth0", "scope": "link"}]
            if argv == ["ip", "-j", "address", "show"]:
                return [{"ifname": "eth0", "addr_info": [{"family": "inet", "local": "169.254.20.2", "prefixlen": 16, "scope": "link"}]}]
            return [{"dst": target["address"], "dev": "eth0", "lladdr": target["mac"]}]
        with patch.object(self.h, "system_json", side_effect=network):
            self.assertEqual(self.h.validate_target(target), target)
        with patch.object(self.h, "system_json", return_value=[]), self.assertRaisesRegex(self.h.HelperError, "^not_directly_connected$"):
            self.h.validate_target(target)

    def test_requests_reject_unknown_fields_json_secrets_and_unsafe_share(self):
        with patch.object(self.h, "validate_target", return_value=TARGET):
            for request in ({**AUTH, "password": "secret"}, {**AUTH, "extra": True}, {**AUTH, "share": "../Data"}):
                with self.subTest(request=request), self.assertRaises(self.h.HelperError):
                    self.h.main("verify", request, b"pw")


class FakeSmbPopen:
    calls = []
    stdout_text = "Disk|Data|Backup disk\nIPC|IPC$|IPC service\nDisk|Family Disk|Family backups\n"
    return_code = 0

    def __init__(self, argv, **kwargs):
        self.argv = argv
        self.kwargs = kwargs
        self.returncode = self.return_code
        self.password = b""
        fd_text = kwargs["env"].get("PASSWD_FD")
        if fd_text:
            self.password = os.read(int(fd_text), 4096)
        config = Path(kwargs["env"]["SMB_CONF_PATH"])
        self.config_path = config
        self.config_mode = stat.S_IMODE(config.stat().st_mode)
        self.config_text = config.read_text()
        type(self).calls.append(self)

    def communicate(self, timeout=None):
        self.timeout = timeout
        return self.stdout_text.encode(), b"diagnostic that must not escape"

    def kill(self):
        self.returncode = -9


class SmbExecutionTests(unittest.TestCase):
    def setUp(self):
        self.h = load_helper()
        FakeSmbPopen.calls = []
        FakeSmbPopen.stdout_text = "Disk|Data|Backup disk\nIPC|IPC$|IPC service\nDisk|Family Disk|Family backups\n"
        FakeSmbPopen.return_code = 0

    def test_shares_uses_private_nt1_config_and_password_fd_only(self):
        secret = b"correct horse battery staple"
        with patch.object(self.h, "validate_target", return_value=TARGET), \
             patch.object(self.h.shutil, "which", return_value="/mock/smbclient"), \
             patch.object(self.h.subprocess, "Popen", FakeSmbPopen):
            result = self.h.main("shares", AUTH, secret)
        self.assertEqual(result["shares"], [
            {"name": "Data", "comment": "Backup disk"},
            {"name": "Family Disk", "comment": "Family backups"},
        ])
        call = FakeSmbPopen.calls[0]
        self.assertEqual(call.password, secret + b"\n")
        self.assertEqual(call.config_mode, 0o600)
        for setting in ("client min protocol = NT1", "client max protocol = NT1",
                        "client ipc min protocol = NT1", "client ipc max protocol = NT1",
                        "client use spnego = no", "client ntlmv2 auth = no"):
            self.assertIn(setting, call.config_text)
        self.assertFalse(call.config_path.exists())
        self.assertIn("-s", call.argv)
        self.assertIn("-g", call.argv)
        self.assertIn("-d0", call.argv)
        self.assertIn("--use-kerberos=off", call.argv)
        self.assertEqual(call.argv[-4:], ["-U", "alice", "-L", "//capsule.local"])
        self.assertIn("-I", call.argv)
        self.assertEqual(call.argv[call.argv.index("-I") + 1], TARGET["address"])
        joined = json.dumps({"argv": call.argv, "env": call.kwargs["env"]})
        self.assertNotIn(secret.decode(), joined)
        self.assertNotIn("PASSWD", call.kwargs["env"])
        self.assertNotIn("PASSWD_FILE", call.kwargs["env"])

    def test_verify_executes_only_literal_ls_for_validated_share(self):
        with patch.object(self.h, "validate_target", return_value=TARGET), patch.object(self.h.shutil, "which", return_value="/mock/smbclient"), patch.object(self.h.subprocess, "Popen", FakeSmbPopen):
            result = self.h.main("verify", {**AUTH, "share": "Family Disk"}, b"pw")
        self.assertEqual(result, {"connected": True, "mounted": False, "share": "Family Disk"})
        call = FakeSmbPopen.calls[0]
        self.assertIn("//capsule.local/Family Disk", call.argv)
        self.assertEqual(call.argv[-2:], ["-c", "ls"])

    def test_smb_failure_is_redacted(self):
        FakeSmbPopen.return_code = 1
        FakeSmbPopen.stdout_text = "secret-looking remote diagnostics"
        with patch.object(self.h, "validate_target", return_value=TARGET), patch.object(self.h.shutil, "which", return_value="/mock/smbclient"), patch.object(self.h.subprocess, "Popen", FakeSmbPopen), self.assertRaisesRegex(self.h.HelperError, "^authentication_or_access_failed$"):
            self.h.main("shares", AUTH, b"do-not-echo")


class TransferTests(unittest.TestCase):
    def setUp(self):
        self.h = load_helper()
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.snapshot = "20260910T120000000000Z-0123456789ab"
        self.payload = self.root / "payload source.age"
        self.payload.write_bytes(b"encrypted payload")
        import hashlib
        digest = hashlib.sha256(self.payload.read_bytes()).hexdigest()
        self.manifest = self.root / "manifest source.json"
        self.manifest.write_text(json.dumps({
            "id": self.snapshot, "created": "2026-09-10T12:00:00+00:00",
            "configurations": True, "files": True, "encrypted": True,
            "format": 1, "payloadSha256": digest,
            "payloadSize": self.payload.stat().st_size,
        }))
        self.base = {**AUTH, "share": "Data", "savedCredential": True, "snapshot": self.snapshot}

    def test_upload_stages_local_names_and_publishes_manifest_last(self):
        calls = []
        def run_smb(req, **kwargs):
            calls.append({**kwargs,
                          "payload": (kwargs["cwd"] / "payload.tar.age").read_bytes(),
                          "manifest": json.loads((kwargs["cwd"] / "manifest.json").read_text())})
            return 0, b"", b"", ["smbclient"]
        request = {**self.base, "payloadFile": str(self.payload), "manifestFile": str(self.manifest)}
        with patch.object(self.h, "validate_target", return_value=TARGET), patch.object(self.h, "run_smb", side_effect=run_smb):
            result = self.h.main("upload", request)
        self.assertEqual(result, {"uploaded": True, "snapshot": self.snapshot})
        command = calls[0]["command"]
        self.assertEqual(command.split("; ")[-2:], [
            f"put manifest.json OmarchyControlPanel/{self.snapshot}.manifest.json.part",
            f"rename OmarchyControlPanel/{self.snapshot}.manifest.json.part OmarchyControlPanel/{self.snapshot}.manifest.json",
        ])
        self.assertNotIn(str(self.payload), command)
        self.assertNotIn(str(self.manifest), command)
        self.assertEqual(calls[0]["payload"], self.payload.read_bytes())
        self.assertEqual(calls[0]["manifest"]["id"], self.snapshot)
        self.assertGreaterEqual(calls[0]["timeout"], 3600)

    def test_remote_names_are_closed_and_json_secrets_are_rejected(self):
        with patch.object(self.h, "validate_target", return_value=TARGET):
            for changed in ({"snapshot": "../../etc"}, {"remoteName": "x;del *"}, {"password": "secret"}):
                with self.subTest(changed=changed), self.assertRaises(self.h.HelperError):
                    self.h.main("upload", {**self.base, "payloadFile": str(self.payload), "manifestFile": str(self.manifest), **changed})

    def test_download_verifies_manifest_hash_before_publishing_local_files(self):
        destination = self.root / "download"
        destination.mkdir()
        def run_smb(req, **kwargs):
            (kwargs["cwd"] / "payload.tar.age").write_bytes(self.payload.read_bytes())
            (kwargs["cwd"] / "manifest.json").write_bytes(self.manifest.read_bytes())
            return 0, b"", b"", ["smbclient"]
        with patch.object(self.h, "validate_target", return_value=TARGET), patch.object(self.h, "run_smb", side_effect=run_smb):
            result = self.h.main("download", {**self.base, "destination": str(destination)})
        self.assertEqual(result["snapshot"], self.snapshot)
        self.assertEqual((destination / "payload.tar.age").read_bytes(), self.payload.read_bytes())
        self.assertEqual(json.loads((destination / "manifest.json").read_text())["id"], self.snapshot)

        bad = self.root / "bad-download"
        bad.mkdir()
        def corrupt(req, **kwargs):
            (kwargs["cwd"] / "payload.tar.age").write_bytes(b"corrupt")
            (kwargs["cwd"] / "manifest.json").write_bytes(self.manifest.read_bytes())
            return 0, b"", b"", ["smbclient"]
        with patch.object(self.h, "validate_target", return_value=TARGET), patch.object(self.h, "run_smb", side_effect=corrupt), self.assertRaisesRegex(self.h.HelperError, "^payload_integrity_failed$"):
            self.h.main("download", {**self.base, "destination": str(bad)})
        self.assertEqual(list(bad.iterdir()), [])

    def test_list_returns_only_valid_complete_manifests_and_remove_only_partials(self):
        other = "20260910T130000000000Z-abcdef012345"
        other_manifest = json.loads(self.manifest.read_text()) | {"id": other}
        calls = []
        def run_smb(req, **kwargs):
            calls.append(kwargs["command"])
            if kwargs["command"] == "ls OmarchyControlPanel":
                listing = (f"  {self.snapshot}.manifest.json A 1\n"
                           f"  {other}.manifest.json A 1\n"
                           f"  {other}.payload.tar.age.part A 1\n"
                           "  ../../unsafe.manifest.json A 1\n")
                return 0, listing.encode(), b"", ["smbclient"]
            if kwargs["command"].startswith("del "):
                return 0, b"", b"", ["smbclient"]
            ident = other if other in kwargs["command"] else self.snapshot
            value = other_manifest if ident == other else json.loads(self.manifest.read_text())
            (kwargs["cwd"] / "manifest.json").write_text(json.dumps(value))
            return 0, b"", b"", ["smbclient"]
        auth = {**AUTH, "share": "Data", "savedCredential": True}
        with patch.object(self.h, "validate_target", return_value=TARGET), patch.object(self.h, "run_smb", side_effect=run_smb):
            listed = self.h.main("list", auth)
            removed = self.h.main("remove-partials", auth)
        self.assertEqual([item["id"] for item in listed["snapshots"]], [self.snapshot, other])
        self.assertEqual(removed, {"removed": 1})
        self.assertEqual(calls[-1], f"del OmarchyControlPanel/{other}.payload.tar.age.part")


class CredentialTests(unittest.TestCase):
    def setUp(self):
        self.h = load_helper()

    def test_save_verifies_first_then_stores_secret_on_stdin_with_safe_attributes(self):
        events = []
        with patch.object(self.h, "verify", side_effect=lambda req, password, saved=False: events.append(("verify", password)) or {"connected": True, "mounted": False, "share": req["share"]}), \
             patch.object(self.h, "store_credential", side_effect=lambda req, password: events.append(("store", password))), \
             patch.object(self.h, "validate_auth_request", side_effect=lambda req, **_kwargs: dict(req)):
            result = self.h.main("save-credential", {**AUTH, "share": "Data"}, b"vault-secret")
        self.assertEqual(events, [("verify", b"vault-secret"), ("store", b"vault-secret")])
        self.assertEqual(result, {"saved": True, "connected": True, "mounted": False, "share": "Data"})

    def test_secret_tool_attributes_are_exact_and_never_contain_secret(self):
        seen = {}
        class StoreProcess:
            returncode = 0
            def __init__(self, argv, **kwargs):
                seen.update(argv=argv, kwargs=kwargs)
            def communicate(self, data, timeout=None):
                seen.update(data=data, timeout=timeout)
                return b"", b""
            def kill(self):
                pass
        with patch.object(self.h.shutil, "which", return_value="/mock/secret-tool"), patch.object(self.h.subprocess, "Popen", StoreProcess):
            self.h.store_credential(AUTH, b"vault-secret")
        self.assertEqual(seen["argv"], ["secret-tool", "store", "--label=Omarchy Control Panel Time Capsule", "app", "omarchy-control-panel", "protocol", "smb1", "mac", TARGET["mac"], "host", TARGET["host"], "user", "alice"])
        self.assertEqual(seen["data"], b"vault-secret")
        self.assertNotIn("vault-secret", json.dumps({"argv": seen["argv"], "env": seen["kwargs"]["env"]}))

    def test_saved_credential_flows_from_secret_tool_pipe_to_smbclient(self):
        secret = b"pipe-only-secret\n"
        smb_calls = []

        class LookupProcess:
            returncode = 0
            def __init__(self):
                read_fd, write_fd = os.pipe()
                os.write(write_fd, secret)
                os.close(write_fd)
                self.stdout = os.fdopen(read_fd, "rb", buffering=0)
            def wait(self, timeout=None):
                return 0
            def kill(self):
                self.returncode = -9

        def popen(argv, **kwargs):
            if argv[:2] == ["secret-tool", "lookup"]:
                return LookupProcess()
            process = FakeSmbPopen(argv, **kwargs)
            smb_calls.append(process)
            return process

        with patch.object(self.h, "validate_target", return_value=TARGET), \
             patch.object(self.h.shutil, "which", side_effect=lambda name: "/mock/" + name), \
             patch.object(self.h.subprocess, "Popen", side_effect=popen) as mocked_popen:
            result = self.h.main("shares", {**AUTH, "savedCredential": True})
        self.assertTrue(result["connected"])
        self.assertEqual(smb_calls[0].password, secret)
        lookup_argv = next(call.args[0] for call in mocked_popen.call_args_list if call.args[0][:2] == ["secret-tool", "lookup"])
        self.assertEqual(lookup_argv, ["secret-tool", "lookup", "app", "omarchy-control-panel", "protocol", "smb1", "mac", TARGET["mac"], "host", TARGET["host"], "user", "alice"])

    def test_forget_is_explicit_exact_clear_without_password(self):
        completed = subprocess.CompletedProcess([], 0, b"", b"")
        with patch.object(self.h, "validate_auth_request", return_value=AUTH), patch.object(self.h.shutil, "which", return_value="/mock/secret-tool"), patch.object(self.h.subprocess, "run", return_value=completed) as run:
            result = self.h.main("forget-credential", AUTH)
        self.assertEqual(result, {"forgotten": True})
        self.assertEqual(run.call_args.args[0], ["secret-tool", "clear", "app", "omarchy-control-panel", "protocol", "smb1", "mac", TARGET["mac"], "host", TARGET["host"], "user", "alice"])
        self.assertIs(run.call_args.kwargs["stdin"], subprocess.DEVNULL)


class ProbeTests(unittest.TestCase):
    def test_probe_is_passwordless_and_reports_smb1_and_afp_reachability(self):
        h = load_helper()
        class ProbeProcess(FakeSmbPopen):
            calls = []
            def __init__(self, argv, **kwargs):
                super().__init__(argv, **kwargs)
                self.returncode = 1
            def communicate(self, timeout=None):
                return b"", b"NT_STATUS_LOGON_FAILURE"
        with patch.object(h, "validate_target", return_value=TARGET), patch.object(h.shutil, "which", return_value="/mock/smbclient"), patch.object(h.subprocess, "Popen", ProbeProcess), patch.object(h, "tcp_reachable", return_value=True):
            result = h.main("probe", TARGET)
        self.assertTrue(result["legacySmb"])
        self.assertTrue(result["afpReachable"])
        self.assertTrue(result["authenticationRequired"])
        self.assertNotIn("PASSWD_FD", ProbeProcess.calls[0].kwargs["env"])
        self.assertIn("-N", ProbeProcess.calls[0].argv)


class CliTests(unittest.TestCase):
    def test_cli_password_never_appears_in_argv_env_or_output_and_trailing_lines_are_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            log = root / "smb-log.json"
            ip = root / "ip"
            ip.write_text("#!" + sys.executable + "\nimport json,sys\na=sys.argv[1:]\nif a==['-j','route','show']: x=[{'dst':'192.168.50.0/24','dev':'eth0','scope':'link','protocol':'kernel'}]\nelif a==['-j','address','show']: x=[{'ifname':'eth0','addr_info':[{'family':'inet','local':'192.168.50.2','prefixlen':24,'scope':'global'}]}]\nelse: x=[{'dst':'192.168.50.15','dev':'eth0','lladdr':'5c:96:9d:6d:b2:4a','state':['REACHABLE']}]\nprint(json.dumps(x))\n")
            smb = root / "smbclient"
            smb.write_text("#!" + sys.executable + "\nimport json,os,sys\nfd=int(os.environ['PASSWD_FD']); secret=os.read(fd,2048)\nassert secret==b'cli-secret\\n'\nrecord={'argv':sys.argv[1:],'env':dict(os.environ)}\nopen(os.environ['CALL_LOG'],'w').write(json.dumps(record))\nprint('Disk|Data|Backups')\n")
            for path in (ip, smb):
                path.chmod(0o700)
            env = {"PATH": tmp, "HOME": tmp, "LC_ALL": "C", "CALL_LOG": str(log), "PASSWD": "must-be-scrubbed", "PASSWD_FILE": "must-be-scrubbed"}
            control = json.dumps(AUTH)
            result = subprocess.run([sys.executable, str(SCRIPT), "shares"], input=control + "\ncli-secret\n", text=True, capture_output=True, env=env, timeout=5)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertEqual(json.loads(result.stdout)["shares"][0]["name"], "Data")
            recorded = log.read_text()
            self.assertNotIn("cli-secret", recorded + result.stdout + result.stderr)
            parsed = json.loads(recorded)
            self.assertNotIn("PASSWD", parsed["env"])
            self.assertNotIn("PASSWD_FILE", parsed["env"])
            rejected = subprocess.run([sys.executable, str(SCRIPT), "shares"], input=control + "\ncli-secret\ntrailing\n", text=True, capture_output=True, env=env, timeout=5)
            self.assertEqual(rejected.returncode, 1)
            self.assertEqual(json.loads(rejected.stdout)["error"], "invalid_input")
            self.assertNotIn("cli-secret", rejected.stdout + rejected.stderr)

    def test_cli_enforces_line_limits_and_probe_rejects_password(self):
        env = {"PATH": "", "HOME": "/nonexistent", "LC_ALL": "C"}
        too_large = "{" + "x" * 16384 + "}\n"
        result = subprocess.run([sys.executable, str(SCRIPT), "capabilities"], input=too_large, text=True, capture_output=True, env=env, timeout=5)
        self.assertEqual(json.loads(result.stdout)["error"], "invalid_input")
        result = subprocess.run([sys.executable, str(SCRIPT), "probe"], input=json.dumps(TARGET) + "\nnot-allowed\n", text=True, capture_output=True, env=env, timeout=5)
        self.assertEqual(json.loads(result.stdout)["error"], "password_not_allowed")
        self.assertNotIn("not-allowed", result.stdout + result.stderr)
        blank_probe = subprocess.run([sys.executable, str(SCRIPT), "probe"], input=json.dumps(TARGET) + "\n\n", text=True, capture_output=True, env=env, timeout=5)
        self.assertEqual(json.loads(blank_probe.stdout)["error"], "password_not_allowed")
        missing_password = subprocess.run([sys.executable, str(SCRIPT), "shares"], input=json.dumps(AUTH) + "\n", text=True, capture_output=True, env=env, timeout=5)
        self.assertEqual(json.loads(missing_password.stdout)["error"], "credential_required")


if __name__ == "__main__":
    unittest.main()
