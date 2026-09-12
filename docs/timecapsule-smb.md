# Direct legacy Time Capsule SMB helper

`bin/timecapsule-smb` is a narrow `smbclient` adapter for old Apple Time Capsules that require SMB1/NT1. It does not modify `/etc/samba/smb.conf`, mount a filesystem, or accept arbitrary remote names or commands. Besides discovery/authentication, it transfers the backup backend's fixed age-encrypted snapshot format.

## Security boundary

Every request must identify the already-selected device with all three fields:

```json
{
  "host": "capsule.local",
  "address": "192.168.50.15",
  "mac": "5C:96:9D:6D:B2:4A"
}
```

Before invoking `smbclient`, the helper verifies that:

- `address` is IPv4 in RFC 1918 space or `169.254.0.0/16`;
- the address is on a current, directly connected kernel/link route or local interface subnet;
- the current neighbor-table entry is on that direct interface and matches the expected MAC;
- `host`, username, and share use restricted syntax.

This is intentionally strict. A stale/missing neighbor entry, routed/VPN address, public address, malformed hostname, or changed MAC is rejected. Rediscover the device and retry rather than weakening validation.

All SMB1 settings live in a new temporary directory and mode-0600 config file. The helper passes that file through both `SMB_CONF_PATH` and `smbclient -s`, and deletes it after the subprocess exits. The isolated config pins client and IPC min/max protocol to `NT1`, disables SPNEGO, and disables NTLMv2 authentication. No global or user Samba config is changed.

Authenticated `smbclient` calls always use `-g -d0 --use-kerberos=off`, `-U <username>`, and `-I <selected-address>`. A supplied password travels through an anonymous pipe named only by numeric `PASSWD_FD`; `PASSWD` and `PASSWD_FILE` are removed from the child environment. A saved password is read with `secret-tool lookup` directly from its stdout pipe into `smbclient` where feasible. Passwords are never accepted in JSON, argv, ordinary environment values, output, diagnostics, log files, or the temporary Samba config.

## CLI protocol

Invoke exactly one action in argv:

```text
bin/timecapsule-smb ACTION
```

Send newline-delimited binary stdin:

1. one JSON object, maximum 16 KiB;
2. for password-authenticated actions, one password line, maximum 1 KiB.

No third/trailing line is accepted. `probe`, `capabilities`, and `forget-credential` reject a second line. Responses are a single JSON line. Failures expose only stable redacted codes:

```json
{"ok":false,"error":"authentication_or_access_failed"}
```

### `capabilities`

Request: `{}` with no second line.

Reports whether `smbclient` and Secret Service (`secret-tool`) are available. Mounting remains unsupported; upload, download, and history are supported.

### `probe`

Request: target fields only, with no password line.

Runs an anonymous share-list attempt using the isolated NT1 configuration and separately checks TCP port 548. It reports `legacySmb`, whether SMB authentication appears required, and `afpReachable`. This is compatibility/reachability evidence only.

### `shares`

Request fields: target fields plus `user`. Supply the password on line two, or add `"savedCredential":true` and omit line two.

Only machine-readable `Disk|name|comment` records from `smbclient -g` are returned. IPC, printer, malformed, and unsafe share records are ignored.

Example shape:

```json
{"ok":true,"shares":[{"name":"Data","comment":"Backup disk"}],"connected":true,"mounted":false}
```

### `verify`

Request fields: target fields, `user`, and a validated `share`. Supply a password line or use `"savedCredential":true`.

The only remote smbclient command is the literal `ls`; the validated share is part of the UNC target argument, never command text.

```json
{"ok":true,"connected":true,"mounted":false,"share":"Data"}
```

Here `connected` means **the credentials authenticated and the selected SMB protocol/share was accessible**. It does not mean a filesystem was mounted.

### `save-credential`

Request fields: target fields, `user`, and `share`; password on line two. Saved-credential mode is not accepted for this action.

The helper first performs the same authenticated share verification as `verify`. Only after success does it invoke `secret-tool store`, passing the password on stdin. Lookup attributes contain no secret:

```text
app=omarchy-control-panel
protocol=smb1
mac=<normalized expected MAC>
host=<validated host>
user=<validated user>
```

### `forget-credential`

Request fields: target fields and `user`, with no password line. This is the only deletion action. It calls `secret-tool clear` with the exact attributes above and does not attempt SMB authentication.

### Backup transport actions

`upload`, `download`, `list`, and `remove-partials` require target fields, `user`, `share`, and `"savedCredential":true`; they reject a password line. Thus unattended backup/restore can only use a password previously stored by `save-credential`. The helper feeds Secret Service lookup output directly to `smbclient` with `PASSWD_FD`.

Remote storage has a closed grammar and fixed namespace:

```text
OmarchyControlPanel/<YYYYMMDDTHHMMSSffffffZ-12hex>.payload.tar.age
OmarchyControlPanel/<YYYYMMDDTHHMMSSffffffZ-12hex>.manifest.json
```

No caller-controlled remote path is accepted. The manifest must identify the same snapshot, declare `encrypted:true` and `format:1`, and contain the payload's lowercase SHA-256 and byte size.

- `upload`: additionally accepts absolute regular `payloadFile` and `manifestFile`. It validates their hash/size, copies them to private stable local names, then runs `put payload ...part`, `rename` payload, `put manifest ...part`, and `rename` manifest. Publishing the manifest last is the commit point.
- `list`: downloads and validates only manifests named by the closed snapshot grammar. `.part` objects and payloads without a complete manifest are absent from history.
- `download`: accepts a snapshot ID and an existing empty absolute `destination`. It downloads to a sibling private temporary directory, validates manifest and payload hash/size, and only then publishes `payload.tar.age` and `manifest.json` locally.
- `remove-partials`: lists the fixed namespace and deletes only names matching `<snapshot>.(payload.tar.age|manifest.json).part`. It cannot delete completed snapshots or arbitrary share files.

These actions expose only stable redacted errors. Local source/destination paths may be supplied in JSON, but are never inserted into smbclient command text: transfers run from a private working directory with fixed local basenames.

## Limitations

- SMB1 and NTLMv1-era authentication are obsolete and cryptographically weak. Use this only on a trusted, directly connected LAN for hardware that cannot be upgraded.
- There is no kernel/GVfs mount adapter. The backup engine instead uses the direct upload/list/download actions.
- There is no general file browser, arbitrary remote path, completed-snapshot deletion, or general remote-command action.
- AFP port reachability is reported, but the helper is not an AFP client.
- Device discovery and UI/Core integration are outside this helper.
- A current matching neighbor-table MAC entry is mandatory, so a device may need to be rediscovered after sleep, link changes, or address changes.

## Tests

The isolated test suite uses fake `ip`, `smbclient`, and `secret-tool` processes; it uses no real credentials or network endpoint:

```bash
python3 -m unittest tests.test_timecapsule_smb -v
```
