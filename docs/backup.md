# Backup backend contract

Invoke `python3 bin/control-panel-backup ACTION` with one JSON object on stdin. Actions: `capabilities`, `create-key`, `plan`, `backup`, `history`, `restore`. Every response is one JSON object on stdout: `{ "ok": true, "error": null, ... }` or `{ "ok": false, "error": "message" }`; failures exit 1. No shell interpolation, mounting, package installation, or live-home restore is performed.

## Requests

- `destination`: an existing absolute directory for `local` and mounted adapters; for `sftp`, a preconfigured rclone remote and nonempty subdirectory (`capsule:omarchy-backups`). A direct legacy Time Capsule destination is instead the exact authenticated selection object `{host,address,mac,user,share,savedCredential:true}`. No password field is accepted.
- `transport`: `local` (default), `smb`, `timecapsule`, or `sftp`.
- `configurations` and `files`: independent booleans, default false; select at least one for plan/backup.
- `home`: absolute source home, default the current user's home. Tests always supply a disposable fixture.
- `paths`: optional array of home-relative file/directory names, used only for files. Default `["."]`. Absolute paths and `..` are rejected. Symlinks and special files are skipped, never followed.
- `encrypted`: boolean, default false. True requires `ageRecipient` for backup, `identityFile` for restore. Only age public-key encryption is supported; `passwordFile` is rejected (not silently ignored). Keep the age private key offline and separate from backups.
- `snapshot`: required ID returned by backup/history for restore.
- `target`: required existing empty absolute staging directory for restore; never the source home or any directory inside it. Restored data appears in `target/home`, with `target/packages.json` for inventory. Configuration data takes precedence if the same path is present in both streams.

`capabilities` needs no other fields and returns installed tool booleans and supported transports. `plan` validates inputs without creating a backup or enumerating home contents and returns categories, exclusions, selected paths, required/missing tools, and warnings. `backup` returns `snapshot` and `manifest`; `history` returns `snapshots` (manifest objects sorted by ID). Restore returns `target` and `snapshot`.

## Storage and recovery

`create-key` accepts `identityFile`, an absolute new filename ending in `.key`,
and requires `age-keygen` (provided by age). It creates the recovery identity with
mode 0600 without overwriting an existing file, returning only the public
`ageRecipient` and the chosen path. Private key contents never enter the JSON
response. The `.key` suffix ensures the generated identity is excluded from file
backups. Keep an offline copy separate from backup storage; losing it prevents
encrypted recovery. This action never runs automatically.

Plaintext configuration snapshots are Git repositories with a commit per backup, preserving prior configuration history. Plaintext file snapshots use rsync checksum comparison and `--link-dest` against the previous plaintext file snapshot: unchanged files share storage where hard links are supported. Each snapshot is immutable from the backend's perspective. Never edit backup files in place (hard-linked file versions share inodes). No automatic pruning is implemented.

Encrypted backups use age-encrypted tar archives; they are full snapshots, not incrementally deduplicated. Encryption covers file names, Git history, package inventory, and contents, but the outer manifest exposes timestamp, selection flags, and snapshot ID. Temporary plaintext is staged in a mode-0700 temporary directory and removed on normal exit; use an encrypted local disk because secure deletion and crash cleanup cannot be guaranteed. No homegrown cryptography is used.

Direct legacy Time Capsule operation is selected with `transport:"timecapsule"` and an object `destination`:

```json
{"host":"capsule.local","address":"192.168.50.15","mac":"5C:96:9D:6D:B2:4A","user":"alice","share":"Data","savedCredential":true}
```

It supports only age-encrypted full snapshots. `backup` builds and encrypts the normal snapshot locally, adds `payloadSha256` and `payloadSize` to its manifest, then asks `timecapsule-smb` to publish the payload and manifest directly through SMB1. `history` lists complete remote manifests. `restore` downloads both files, verifies size and SHA-256 before decrypting, and then enters the same existing empty-staging restore path used by local encrypted backups. The password is retrieved by `secret-tool` and piped to `smbclient` through `PASSWD_FD`; it is never included in this API's JSON, argv, ordinary environment, logs, or files. The fixed remote namespace is `OmarchyControlPanel/` on the selected share. Mounting is not required.

SFTP uses an already authenticated rclone remote. No credentials are accepted by this API. Remote operation stages the repository locally, then publishes a new uniquely named snapshot and its manifest last. Remote transfer is not verified in local tests; it needs installed rclone and an actual configured SFTP remote. Remote backups require temporary space for downloaded history and staged data; no server-side deduplication guarantee. Local writers are locked; concurrent remote writers use unique IDs but may branch history. Interrupted uploads without a manifest are ignored. Do not allow untrusted writers to mutate a backup repository during operation.

Configurations include allowlisted Omarchy/Hyprland, terminal/editor/GTK application preferences, themes, local desktop application launchers, Hermes skills/templates, and explicit safe configuration files within Hermes profiles. Hermes databases, conversations, memories, environment files, authentication, provider config, and credentials are not included. Files mode also excludes common credential stores, caches, VCS internals, browser profiles, tokens, SSH/GPG material, and private-key filename patterns. Exclusions are conservative filename rules, **not secret detection**: manually review selected data; an arbitrary document or application preference can contain a secret. Symlinks are omitted, including Omarchy's current-theme link; installed themes are captured, but select the theme again after recovery.

On fresh Omarchy: install Git and rsync (and age/rclone if needed), mount the backup or configure the remote, copy the helper, inspect `history`, and `restore` into a new empty staging directory outside the new home. Review `packages.json` and reinstall desired packages manually using Omarchy's package helpers; inspect and selectively copy `home/` contents. No package reinstall, service activation, permission escalation, or automatic overwrite is done. POSIX regular files/directories and executable bits are supported; ACLs, xattrs, ownership, sparse-file layout, symlinks, and live database consistency are not preserved. Stop applications whose files require a consistent snapshot.

Run fixture-only tests with `python3 -m unittest discover -s tests -p test_backup.py -v`. Install `age` (including `age-keygen`) and `rclone` on the test PATH to exercise encryption and the loopback SFTP server; otherwise those optional tests explicitly skip. Direct Time Capsule orchestration uses a disposable fake age process and mocked transport; `tests/test_timecapsule_smb.py` mocks `smbclient`. No test writes to a live SMB endpoint.

The backend verifies stored payload checksums before restore or reuse of an incremental snapshot. Reused Git repositories have their local configuration reset so stored includes/filter commands are not executed. Checksums detect accidental corruption, not a malicious party who can rewrite both the payload and its index. Only use storage you control.
