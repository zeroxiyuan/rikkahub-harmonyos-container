#!/bin/bash
# install-deb.sh - install Ubuntu packages in the RikkaHub proot container.
#
#   install-deb.sh pkg [pkg...]      install by package name
#   install-deb.sh -d pkg            also install the recursive Depends closure
#   install-deb.sh http://h/x.deb    install from a direct URL
#
# dpkg cannot exec maintainer scripts here (EFAULT) and apt's http helper dies
# with exit 182, so `apt-get install` leaves packages half-configured. Instead:
# fetch the .deb with perl (pget.pl) and unpack it with `dpkg-deb -x /`.
# Requires: perl (perl-base), dpkg, a reachable mirror in /etc/apt/sources.list*.
# Override the URL prefix with SKILL_APT_MIRROR_PREFIX.
set -u
PREFIX="${SKILL_APT_MIRROR_PREFIX:-http://mirrors.aliyun.com/ubuntu-ports}"
HERE=${0%/*}; [ "$HERE" = "$0" ] && HERE=.
PGET="$HERE/pget.pl"
W=/var/tmp/skill-install-deb
mkdir -p "$W" 2>/dev/null
LOG="$W/log"; : > "$LOG" 2>/dev/null
log() { echo "$*" >>"$LOG" 2>/dev/null; }

WITH_DEPS=0
[ "${1:-}" = "-d" ] && { WITH_DEPS=1; shift; }
[ $# -eq 0 ] && { echo "usage: install-deb.sh [-d] pkg|url ..."; exit 2; }

if head -c2 /sbin/ldconfig 2>/dev/null | grep -q '#!' && [ -x /sbin/ldconfig.real ]; then
  mv -f /sbin/ldconfig /sbin/ldconfig.wrapper-bak 2>/dev/null
  cp -f /sbin/ldconfig.real /sbin/ldconfig 2>/dev/null && echo "swapped ldconfig -> ldconfig.real"
fi

ac() { local i; for i in 1 2 3; do apt-cache "$@" 2>/dev/null && return 0; done; return 1; }
field() { ac show "$1" | awk -F': ' -v k="^$2:" '$0 ~ k {print $2; exit}'; }

guess_uris() {
  local p=$1 v base arch src d comp
  v=$(ac policy "$p" | awk '/Candidate:/{print $2}')
  { [ -z "$v" ] || [ "$v" = "(none)" ]; } && return 1
  base="${v#*:}"
  arch=$(field "$p" Architecture); arch=${arch:-$(dpkg --print-architecture)}
  src=$(field "$p" Source); src=${src:-$p}; src=${src%% (*}
  if [ "${src#lib}" != "$src" ]; then d="lib$(printf '%s' "${src#lib}" | cut -c1)"; else d=$(printf '%s' "$src" | cut -c1); fi
  for comp in main universe multiverse restricted; do
    echo "$PREFIX/pool/$comp/$d/$src/${p}_${base}_${arch}.deb"
  done
}

names=""
for a in "$@"; do
  case "$a" in http://*|https://*) continue;; *) names="$names $a";; esac
done
if [ "$WITH_DEPS" = 1 ] && [ -n "$names" ]; then
  extra=$(ac depends --recurse --no-recommends --no-suggests --no-conflicts \
          --no-breaks --no-replaces --no-enhances $names \
          | sed -n 's/^ *[A-Za-z-]*Depends: *//p' | sort -u | tr '\n' ' ')
  echo "closure: $(echo $extra | wc -w) extra package(s)"
  set -- "$@" $extra
fi

fail=0
for a in "$@"; do
  case "$a" in
    http://*|https://*) cands="$a";;
    *)
      case "$a" in libc6|libgcc-s1|libstdc++6|libc-bin|base-files|dpkg|apt|tar|zlib1g|libbz2-1.0|liblzma5|gcc-14-base)
        echo "skip $a (base system)"; continue;; esac
      st=$(dpkg-query -W -f='${Status}' "$a" 2>/dev/null)
      case "$st" in *"install ok installed"*) echo "skip $a (installed)"; continue;; esac
      uri=$(ac download --print-uris "$a" | awk 'NR==1{print $1}' | tr -d "'")
      cands="$uri $(guess_uris "$a" | tr '\n' ' ')";;
  esac
  got=""
  for uri in $cands; do
    [ -z "$uri" ] && continue
    case "$(basename "$uri")" in *.deb) ;; *) continue;; esac
    f="$W/$(basename "$uri")"
    if [ ! -s "$f" ]; then
      out=$(perl "$PGET" "$uri" "$f" 2>&1)
      case "$out" in ok*) ;; *) log "DLFAIL $uri"; rm -f "$f"; continue;; esac
    fi
    got="$f"; break
  done
  if [ -z "$got" ] || [ ! -f "$got" ]; then echo "!! cannot fetch $a"; fail=$((fail+1)); continue; fi
  unpacked=0
  for i in 1 2 3; do          # dpkg-deb dies with exit 182 at random
    if dpkg-deb -x "$got" / 2>>"$LOG"; then unpacked=1; break; fi
  done
  if [ "$unpacked" = 1 ]; then echo "ok $(basename "$got")"; else echo "!! unpack failed $a"; fail=$((fail+1)); fi
done

ldconfig 2>/dev/null && echo "ldconfig refreshed"
[ "$fail" -gt 0 ] && echo "$fail failure(s), see $LOG"
exit 0
