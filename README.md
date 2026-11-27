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

Download a `.skill` from the [Releases](https://github.com/zeroxiyuan/rikkahub-harmonyos-container/releases) page, or use the repository directly.

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

Releases are cut automatically by `.github/workflows/release-skill.yml`. The version is never hardcoded in the workflow; it comes from whichever entry point fired. There are three entry points:

1. **Tag push** — push a tag named `v*` (for example `v1.0.1`). The tag name is the release version, and the release is created against that tag.

   ```bash
   git tag v1.0.1
   git push origin v1.0.1
   ```

2. **Main push updating `.release-version`** — the file `.release-version` on `main` holds the version (for example `v1.0.1`). A push to `main` that changes this file publishes a release for that version, created at `main`. Pushes to `main` that do not change `.release-version` build only.

3. **Manual dispatch** — open the Actions tab and run the workflow by hand. Filling the `version` input (`v1.0.1`) creates or updates that release from `main`; leaving the input empty builds the archive without publishing anything, and the build details are written to the job summary.

The workflow builds `rikkahub-harmonyos-container.skill` from `SKILL.md` + `references/` + `scripts/` (archive root `rikkahub-harmonyos-container/`) and attaches it to the release, with `RELEASE_NOTES.md` as the release body.

If a release for that version already exists, the run replaces the asset with `--clobber` and re-syncs the body from `RELEASE_NOTES.md` instead of failing, so re-pushing or re-running is safe.

The version in `.release-version` (or the manual `version` input) must start with `v`; otherwise the run fails explicitly with an error instead of publishing anything.
