# Release v1.0.0

Skill package for the RikkaHub agent workspace on HarmonyOS (Ubuntu arm64 proot container).

**Asset:** `rikkahub-harmonyos-container.skill` — a zip archive whose root folder is
`rikkahub-harmonyos-container/`.

## Contents

- `SKILL.md` — operating rules, symptom → cause → fix table, standard workflow
- `references/diagnostics.md` — exact commands and observed outputs for every platform defect
- `references/package-install.md` — .deb extract route, dependency closure, dpkg repair
- `scripts/verify-container.sh` — health check, prints `MODE=extract` or `MODE=normal`
- `scripts/install-deb.sh` — install packages by unpacking .deb payloads
- `scripts/pget.pl` — single-threaded HTTP downloader

## Install

```bash
cd /skills
unzip -o rikkahub-harmonyos-container.skill
bash /skills/rikkahub-harmonyos-container/scripts/verify-container.sh
```
