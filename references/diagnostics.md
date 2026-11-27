# Diagnostics: exact commands and observed outputs

Environment where these were recorded: RikkaHub workspace, `libproot_exec.so` (proot),
Ubuntu 24.04.3 LTS, `aarch64`, kernel string `6.6.98` (host kernel, not the rootfs'),
~300–400 MB free RAM, 221 GB disk.

Run everything below with retries; any single command may die with exit 182.

## 1. Is the shell alive at all?

```bash
echo ok; uname -a; df -h / | tail -1; ls -A /workspace | wc -l
```

Observed: `ok`, `Linux localhost 6.6.98 ... aarch64`, `221G ... 76G ... 66% /`.
If instead you see `shell-init: error retrieving current directory ... Function not implemented`
plus `chdir: /workspace: Function not implemented`, the workspace was not mounted: nothing can
be done from inside, the user must restart the workspace / the app.

## 2. Can scripts be executed?

```bash
printf '#!/bin/sh\necho script-ok\n' > /tmp/t.sh; chmod +x /tmp/t.sh; /tmp/t.sh; echo rc=$?
```

Broken (typical): `rikkahub: /tmp/t.sh: /bin/sh: bad interpreter: Bad address`, `rc=126`.
20 consecutive runs: 0 successes. Every interpreter behaves the same (`/bin/sh`, `/bin/bash`,
`/usr/bin/perl`). The same file works when run as `sh /tmp/t.sh` — it is `execve`, not the file.

Consequence: all of dpkg's maintainer scripts fail. Never trust `dpkg -l` status here.

## 3. Are threads available?

```bash
python3 -c 'import threading; threading.Thread(target=lambda: None).start()'
curl -s -o /dev/null -w '%{http_code}\n' https://example.com
```

Observed: `RuntimeError: can't start new thread`; `curl` verbosely prints
`* getaddrinfo() thread failed to start` / `* Could not resolve host`. `wget`, `python3` and
`getent hosts` resolve fine, because they are single-threaded.

## 4. Exit code 182

`182` appears whenever the proot launcher fails to set up a child: apt, dpkg, dpkg-deb, `tar`
inside dpkg-deb, even `rm` during cleanup. It is random — the identical command usually
succeeds on the next attempt. Two related rules:

- two concurrent `workspace_shell` calls: one returns 182 with empty output;
- a foreground call lasting >30 s is killed (`proot info: vpid 1: terminated with signal 9`),
  which looks like an OOM but is the tool timeout.

## 5. apt state

```bash
apt-get update --allow-insecure-repositories
apt-get install -y --allow-unauthenticated --no-install-recommends jq
```

Without `--allow-insecure-repositories`: `E: The repository ... is not signed` and
`Couldn't execute /usr/bin/apt-key` (no `gnupg` in the rootfs). After a failed install the
solver can start refusing everything with `E: Unable to correct problems, you have held broken
packages` — that is why dependencies are resolved with `apt-cache depends --recurse`.

## 6. Mirror throughput

```bash
time apt-get -o APT::Get::AllowUnauthenticated=true download libpython3.12-stdlib
```

- `ports.ubuntu.com`: `Fetched 2039 kB in ... (1104 B/s … 15.2 kB/s)` — 81 packages would be
  an hour or more.
- `mirrors.aliyun.com/ubuntu-ports`: `Fetched 2039 kB in 8s (242 kB/s)`.
Check the mirror before blaming the container for being slow.

## 7. Filesystem traps

- `umask` is `077`: new files are mode 600 and new directories 700. `dpkg-deb -b` rejects a
  control directory that is 700, and unpacked payloads keep restrictive modes, so
  `chmod -R go+rX <dir>` before repacking.
- `workspace_write_file` can report `Write file failed with exit code 1`/`182` while the file
  was written completely, and occasionally leaves a 0-byte file. Always verify with
  `wc -c <path>`; rewrite only when it is 0.
- `mkdir -p` can silently fail (182) — a later write then reports "No such file or directory".
  Create directories with a retry loop.

## 8. Checklist when a new device / app version is tested

1. `verify-container.sh` — read the MODE line.
2. If `shebang script exec` is now OK: use plain apt and stop reading this skill.
3. If threads now work: `git clone` and `curl` should be fine too.
4. Otherwise stay on the extract route and mirror switch.
