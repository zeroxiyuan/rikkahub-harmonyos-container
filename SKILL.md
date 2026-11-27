---
name: rikkahub-harmonyos-container
description: >-
  Diagnose and work around the broken Linux container (proot workspace) that RikkaHub runs on
  HarmonyOS. Use when the workspace shell fails, commands return exit code 182 or "Bad address",
  apt-get/dpkg fail or leave packages half-configured, curl or git cannot resolve hosts, package
  downloads crawl, or when installing tools (git, python3, curl, jq, less) inside this container.
compatibility: >-
  Target is the RikkaHub workspace itself (Ubuntu arm64 proot on HarmonyOS). Scripts need perl,
  dpkg-deb, tar and a reachable apt mirror. run_skill scripts assume bash is at /bin/bash.
---

# RikkaHub container on HarmonyOS

The workspace is not a normal VM: it is an arm64 Ubuntu rootfs run by `libproot_exec.so`
(proot) inside the RikkaHub app on HarmonyOS. Several syscalls are missing or emulated badly,
so ordinary package management and some networking silently break. Treat every failure as a
platform trait, not as a user error, and never "retry until it works" more than a few times.

## Operating rules

1. **Tool permissions are pre-approved.** Run commands directly; do not ask for confirmation
   before reading, writing, installing, or changing config inside the container.
2. **If a tool call fails, stop retrying and answer in plain text.** After at most two retries,
   describe the cause, the exact workaround, and the commands the user can paste. Never leave
   the user with a raw stack trace.
3. **One shell call at a time.** Two concurrent `workspace_shell` calls make one of them die
   with exit `182` and empty output.
4. **Anything slower than ~10 s goes to the background** with output redirected to a log, then
   poll the log. Foreground calls are killed (SIGKILL) at ~30 s.
5. **A reported write failure may still have succeeded.** After `write_file` errors, check
   `wc -c <path>` before rewriting; an empty file (0 bytes) means it really failed.
6. Prefer short commands. Long heredocs and pipelines are the calls most likely to die.

## Symptoms → cause → fix

| Symptom | Cause | Fix |
|---|---|---|
| `... : /bin/sh: bad interpreter: Bad address`, rc 126 | `execve` of shebang scripts fails with EFAULT | Never let dpkg run maintainer scripts. Install by unpacking `.deb` payloads (see below), run post-install scripts manually with `sh script` |
| Random exit `182`, empty stdout | exec/pipe setup fails sporadically for any binary | Retry the command 2–3 times; wrap loops in `for i in 1 2 3` |
| Background call exits `182` in 0 s | session failed to start | Simply re-launch it |
| `E: Sub-process /usr/bin/dpkg returned an error code`, packages stuck `iF` | postinst/prerm could not exec | Do not fight it: use the extract route, or see [package-install.md](references/package-install.md) for the dpkg status repair recipe |
| `curl: getaddrinfo() thread failed` / `Can't start new thread` | **threads cannot be created at all**; libcurl's resolver is threaded | Use `wget` or `python3` for network, or `curl --resolve host:443:IP`. `git clone https://` cannot work; download a tarball with python3 instead |
| Downloads 1–15 kB/s from `ports.ubuntu.com` | default mirror unreachable/degraded from HarmonyOS networks | Switch to a China mirror (aliyun/tuna). Gives ~240 kB/s |
| `apt-get update`: "repository is not signed" | `gnupg` is not installed, so `apt-key` cannot verify | `apt-get update --allow-insecure-repositories`, install with `--allow-unauthenticated` |
| `apt-get` reports "held broken packages" after a `--force-depends` install | apt's solver gives up | Resolve deps with `apt-cache depends --recurse` instead of apt's solver |
| `dpkg-deb -b`: "tar subprocess returned error 182" or "control directory has bad permissions 700" | flaky exec + umask 077 | Retry; `chmod -R go+rX` the tree; use `-Zgzip` |
| Long `apt-get`/`dpkg` run vanishes | OOM (only ~300–400 MB free) | Small batches, one package group per background job |
| `pkill -f foo` kills your own session | the pattern matches the current shell's cmdline | Kill by PID, or pattern `'bash /path/script.sh'` |

## Standard workflow

1. **Health check first** (it prints a MODE verdict):
   `bash /skills/rikkahub-harmonyos-container/scripts/verify-container.sh`
2. **MODE=extract** (the normal case): install software with
   `bash /skills/rikkahub-harmonyos-container/scripts/install-deb.sh -d <pkg>`
   It resolves the Depends closure with `apt-cache depends --recurse`, downloads each `.deb`
   with perl (never apt's http helper) and unpacks it with `dpkg-deb -x /`. No dpkg database,
   no maintainer scripts, so nothing can half-configure.
3. **MODE=normal** (scripts executable): plain `apt-get install -y --allow-unauthenticated`
   still works; keep the retry habit.
4. **Verify by running the tool**, not by `dpkg -l`: `git --version`, `python3 -c 'print(1)'`,
   `jq --version`. Binaries can be present while a shared lib is missing — then `ldd <bin>`
   and install the library package by its soname's package name.
5. **When something is impossible, say so and give the alternative**:
   `git clone` → python3 tarball download; `curl` → `wget`/python3; multithreaded tools → avoid.

## Mirror switch (do this early, it saves the most time)

```bash
sed -i 's|http://ports.ubuntu.com/ubuntu-ports/|http://mirrors.aliyun.com/ubuntu-ports/|g' \
  /etc/apt/sources.list.d/ubuntu.sources
apt-get update --allow-insecure-repositories
```

Keep a backup (`cp /etc/apt/sources.list.d/ubuntu.sources /var/tmp/ubuntu.sources.bak`) and
mention the change to the user: it is a persistent system edit.

## Details

- [references/package-install.md](references/package-install.md) — extract-route recipe,
  dependency resolution, ldconfig swap, CA certificates, repairing a half-configured dpkg,
  and how to keep `git`/`curl`/`python3` usable.
- [references/diagnostics.md](references/diagnostics.md) — exact commands and observed outputs
  for every defect, useful to compare against a new device or app version.
