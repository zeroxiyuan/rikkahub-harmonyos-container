# Installing software without dpkg

`apt-get install` cannot work reliably here: dpkg execs maintainer scripts and those
execve() calls fail with `EFAULT` (`Bad address`). The result is a package marked `iF`
(half-configured) whose files may or may not be usable. The reliable route is to take the
`.deb` apart and copy the payload into place.

## The extract route

```bash
# 1. resolve the Depends closure without apt's solver
apt-cache depends --recurse --no-recommends --no-suggests --no-conflicts \
  --no-breaks --no-replaces --no-enhances curl \
  | sed -n 's/^ *[A-Za-z-]*Depends: *//p' | sort -u

# 2. get a URL for one package (works even when the solver is unhappy)
apt-get download --print-uris libcurl4t64

# 3. fetch it with perl (apt's own http helper is unreliable)
perl /skills/rikkahub-harmonyos-container/scripts/pget.pl \
  'http://mirrors.aliyun.com/ubuntu-ports/pool/main/c/curl/libcurl4t64_8.5.0-2ubuntu10.16_arm64.deb' \
  /tmp/libcurl4t64.deb

# 4. unpack into / (no database update, no scripts)
dpkg-deb -x /tmp/libcurl4t64.deb / && ldconfig
```

`scripts/install-deb.sh -d <pkg>` automates all four steps, including a pool-URL fallback for
packages where `--print-uris` returns nothing:

```
http://<mirror>/pool/<main|universe>/<dir>/<source>/<pkg>_<version-without-epoch>_<arch>.deb
```
`<dir>` is the first letter of the source package, or `lib<letter>` for `lib*` sources
(`brotli` → `b`, `libpsl` → `libp`).

If a binary fails with `error while loading shared libraries: libfoo.so.4`, the package is
usually named after the library: `libssh.so.4` → `libssh-4`, `libpsl.so.5` → `libpsl5t64`,
`librtmp.so.1` → `librtmp1`. Extract it and run `ldconfig`.

## Two system files that must be fixed first

**ldconfig.** On noble `/sbin/ldconfig` is a shell wrapper (387 bytes) that cannot be exec'd,
which breaks every post-install script that calls it:

```bash
mv -f /sbin/ldconfig /sbin/ldconfig.wrapper-bak
cp -f /sbin/ldconfig.real /sbin/ldconfig
```

**CA certificates.** `update-ca-certificates` reports "0 added" because
`/etc/ca-certificates.conf` is missing from the package payload:

```bash
(cd /usr/share/ca-certificates && ls mozilla/*.crt) > /etc/ca-certificates.conf
sh /usr/sbin/update-ca-certificates        # /etc/ssl/certs then holds ~180 certs
```
Note: `update-ca-certificates` is a shell script, so run it with `sh`, never directly.

## Repairing a dpkg left half-configured

Only needed if `apt-get` already ran and something is stuck. Work on a fresh rootfs this is
normally unnecessary — prefer the extract route.

1. Run the failing script by hand: `sh /var/lib/dpkg/info/<pkg>.postinst configure`.
2. Mark the database entry as installed by editing the stanza in `/var/lib/dpkg/status`:
   change `Status: install ok half-configured` to `install ok installed` **and delete its
   `Config-Version:` line** (otherwise dpkg-query refuses to parse the whole file: "Config-Version
   field present for package with inappropriate 'Status' field").
3. If dpkg refuses to upgrade a package because the *old* `prerm` cannot be exec'd, move it
   aside first: `mv /var/lib/dpkg/info/<pkg>.prerm /var/tmp/` — dpkg then skips it. A rebuilt
   package that lacks scripts makes dpkg abort with "there is no script in the new version",
   so always remove the old script too.
4. `dpkg -i --force-depends --no-triggers <pkg>.deb` and finally `ldconfig`.

## Building a modified .deb (only if you must)

`dpkg-deb -R x.deb dir` → delete `dir/DEBIAN/{preinst,postinst,prerm,postrm}` →
`chmod -R go+rX dir` → `dpkg-deb -Zgzip -b dir out.deb`. Two traps: the control directory must
not be mode 700 (umask 077 is the default here) and the default compressor may fail, so pass
`-Zgzip`. `dpkg-deb -R` also refuses a non-empty target directory — always `rm -rf` it first.

## What each tool can actually do afterwards

- `git` — local init/add/commit/log/diff fine. `clone`/`fetch` over https need libcurl-gnutls
  *and* a working thread for DNS, which this container cannot create, so use a tarball instead:
  ```bash
  python3 -c "import urllib.request;open('/tmp/r.tar.gz','wb').write(
      urllib.request.urlopen('https://github.com/user/repo/archive/refs/heads/main.tar.gz').read())"
  tar -xzf /tmp/r.tar.gz -C /workspace
  ```
- `curl` — everything except hostname resolution; `curl --resolve host:443:<ip>` works,
  `wget` and `python3` are better default choices.
- `python3` — threads raise `RuntimeError: can't start new thread`; asyncio/subprocess are fine.
- Anything that forks many helpers (`apt`, `dpkg`, `mandb`, `locale-gen`) will hit exit 182
  occasionally; retry.
