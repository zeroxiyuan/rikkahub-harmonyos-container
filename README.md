# rikkahub-harmonyos-container

A Claude-style skill (packaged as `rikkahub-harmonyos-container.skill`) for repairing and working around the broken Linux container that **RikkaHub** runs its agent workspace in on **HarmonyOS**.

The workspace is an arm64 Ubuntu rootfs launched through `libproot_exec.so` (proot), not a real VM. In practice that means:

- shebang scripts cannot be `execve`'d → `bad interpreter: Bad address`, rc 126;
- `dpkg`/`apt` maintainer scripts therefore fail and packages are left half-configured (`iF`);
- threads cannot be created → `curl` DNS and `git clone https://` fail;
- exec calls randomly die with exit `182`;
- the default `ports.ubuntu.com` mirror is unusably slow from HarmonyOS networks.

The skill turns those failures into a fixed procedure instead of guesswork: a health check that reports the platform mode, a `.deb` extract route that never touches the dpkg database, mirror switching, dpkg repair recipes, and a table mapping every symptom to its cause and fix.

## Install

Download the latest `.skill` from the [Releases](https://github.com/zeroxiyuan/rikkahub-harmonyos-container/releases) page, or use the repository directly.

**In the RikkaHub workspace** — unpack the archive so the folder sits under `/skills`:

```bash
cd /skills
unzip -o rikkahub-harmonyos-container.skill
bash /skills/rikkahub-harmonyos-container/scripts/verify-container.sh
```

**As a Claude / agent skill** — unpack the archive into your skills directory so it appears as `rikkahub-harmonyos-container/SKILL.md`.

The workflow files under `.github/` and this README are repository packaging; only `SKILL.md`, `references/` and `scripts/` are needed by the skill itself.

## Layout

```
SKILL.md                        entry point: rules, symptom table, standard workflow
references/diagnostics.md       exact commands + observed outputs for each platform defect
references/package-install.md   extract route, dependency resolution, dpkg repair
scripts/verify-container.sh     health check, prints MODE=extract or MODE=normal
scripts/install-deb.sh          install packages via .deb extraction (perl downloader)
scripts/pget.pl                 single-threaded HTTP downloader for the broken container
```

## Release

Every push to `main` that touches the skill files re-runs `.github/workflows/release-skill.yml`, which zips the skill folder into `rikkahub-harmonyos-container.skill` and attaches it to the `v1.0.0` release.
