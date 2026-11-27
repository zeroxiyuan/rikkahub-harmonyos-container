#!/bin/bash
# verify-container.sh - one-shot health check for the RikkaHub proot container.
# Run this FIRST whenever the container "feels broken". Every check is retried,
# because single exec calls fail randomly (exit 182) on this platform.
#
# Usage: bash /skills/rikkahub-harmonyos-container/scripts/verify-container.sh
# Output: one line per check; the last lines summarise the platform verdict.
set -u
ok=0; bad=0
say() { printf '%-34s %s\n' "$1" "$2"; }
pass() { say "$1" "OK   ($2)"; ok=$((ok+1)); }
fail() { say "$1" "FAIL ($2)"; bad=$((bad+1)); }
try() { local n=3 i; for ((i=0;i<n;i++)); do "$@" 2>/dev/null && return 0; done; return 1; }

echo "=== identity ==="
if try test -x /bin/bash; then pass "shell" "bash present"; else fail "shell" "no /bin/bash"; fi
say "rootfs" "$(. /etc/os-release 2>/dev/null; echo "${PRETTY_NAME:-unknown} $(uname -m)")"
say "workspace" "$(pwd)"
if try test -w /workspace; then pass "workspace writable" "/workspace"; else fail "workspace writable" "/workspace"; fi
if try sh -c 'echo probe > /tmp/.probe.$$'; then pass "tmp writable" "/tmp"; else fail "tmp writable" "/tmp"; fi
rm -f /tmp/.probe.* 2>/dev/null

echo
echo "=== memory / limits (OOM kills long apt runs) ==="
free -m 2>/dev/null | awk 'NR==2{printf "%-34s used=%sMB free=%sMB\n", "memory", $3, $4}'

echo
echo "=== known platform defects ==="
# 1) execve of shebang scripts fails with EFAULT
printf '#!/bin/sh\necho ok\n' > /tmp/.sc.$$ 2>/dev/null; chmod +x /tmp/.sc.$$ 2>/dev/null
if /tmp/.sc.$$ >/dev/null 2>&1; then
  pass "shebang script exec" "works - standard apt/dpkg may work"
  SCRIPTS=1
else
  fail "shebang script exec" "EFAULT 'Bad address' - strip maintainer scripts"
  SCRIPTS=0
fi
rm -f /tmp/.sc.$$ 2>/dev/null

# 2) thread creation
if python3 -c 'import threading;threading.Thread(target=lambda:None).start()' >/dev/null 2>&1; then
  pass "thread creation" "works"
else
  if command -v python3 >/dev/null 2>&1; then
    fail "thread creation" "cannot start thread - curl/git https DNS will fail"
  else
    say "thread creation" "SKIP (no python3)"
  fi
fi

# 3) exec flakiness (exit 182)
n=0; for i in $(seq 1 12); do /bin/true 2>/dev/null || n=$((n+1)); done
if [ "$n" -eq 0 ]; then pass "exec reliability" "12/12 clean"
else say "exec reliability" "WARN $n/12 calls failed - retry everything"; fi

# 4) ldconfig wrapper (noble ships a shell script that cannot exec)
if head -c2 /sbin/ldconfig 2>/dev/null | grep -q '#!'; then
  fail "ldconfig" "still a shell wrapper - swap in ldconfig.real"
else
  pass "ldconfig" "binary"
fi

# 5) apt trust + mirror
u=$(grep -h '^URIs:' /etc/apt/sources.list.d/*.sources 2>/dev/null | head -1 | awk '{print $2}')
say "apt mirror" "${u:-none}"
if command -v gpg >/dev/null 2>&1; then pass "gnupg" "present"; else fail "gnupg" "missing - repos are unsigned, use --allow-insecure-repositories"; fi

echo
echo "=== tooling ==="
for c in bash perl tar gzip dpkg apt-get jq tree less unzip zip curl wget git python3; do
  if command -v "$c" >/dev/null 2>&1; then printf '%-8s present\n' "$c"; else printf '%-8s MISSING\n' "$c"; fi
done

echo
echo "=== verdict ==="
echo "$ok checks passed, $bad failed"
if [ "${SCRIPTS:-0}" = "0" ]; then
  echo "MODE=extract  -> install packages with scripts/install-deb.sh (dpkg-deb -x), never 'apt-get install'"
else
  echo "MODE=normal   -> apt-get install may work; still retry on exit 182"
fi
