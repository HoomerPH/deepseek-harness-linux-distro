#!/usr/bin/env bash
#
# Update helper for the deepseek-harness Arch package.
#
#   ./update-package.sh                 # check for a newer upstream release
#   ./update-package.sh --json          # same, machine-readable
#   ./update-package.sh --bump          # bump _npmver + tarball checksum + .SRCINFO
#   ./update-package.sh --bump --dry-run
#   ./update-package.sh --build         # bump (if needed) and rebuild + verify
#   ./update-package.sh --selftest      # exercise the version comparator
#
# Exit codes for the check mode: 0 = up to date, 1 = newer upstream version
# available, 2 = error.
#
# Why this exists: upstream publishes prereleases rapidly (0.2.1-rc.1 through
# rc.4 landed inside nine days) and npm's `latest` tag lags behind `next`, so
# "is there a new release?" needs prerelease-aware comparison across dist-tags,
# not a simple `npm view ... version`.
#
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"

PKGBUILD=PKGBUILD
DIST_TAGS_URL='https://registry.npmjs.org/-/package/@deepseek-ai/dsh/dist-tags'
TARBALL_URL='https://registry.npmjs.org/@deepseek-ai/dsh/-/dsh-%s.tgz'

# Scratch path used by --bump; declared globally so the EXIT trap can clean it
# up even after do_bump's locals have gone out of scope.
tmp=
cleanup() {
  if [[ -n $tmp ]]; then
    rm -f "$tmp" "$tmp".*
  fi
  return 0
}
trap cleanup EXIT

mode=check
dry_run=0
force=0
json=0

die() {
  echo "update-package: $*" >&2
  exit 2
}

usage() {
  cat <<'EOF'
Usage: update-package.sh [--check | --bump | --build | --selftest] [options]

  --check       compare _npmver against the newest published version (default)
  --bump        update PKGBUILD (_npmver + tarball sha256) and regenerate .SRCINFO
  --build       bump when needed, then run ./verify-package.sh (rebuild + smoke test)
  --selftest    run the version-comparison self-test and exit

Options:
  --dry-run     with --bump/--build: show the change without writing
  --force       with --bump: write even when already at the newest version
  --json        with --check: print a JSON object instead of a table
  -h, --help    show this help
EOF
}

# --- semver-like comparison -------------------------------------------------
# Prints 1 when $1 > $2, -1 when $1 < $2, 0 when equal. Handles prerelease
# identifiers (0.2.1-rc.4 < 0.2.1-rc.10 < 0.2.1) the way semver does.
vercmp() {
  local a=$1 b=$2 acore apre bcore bpre
  if [[ $a == *-* ]]; then acore=${a%%-*} apre=${a#*-}; else acore=$a apre=; fi
  if [[ $b == *-* ]]; then bcore=${b%%-*} bpre=${b#*-}; else bcore=$b bpre=; fi

  local -a ap=() bp=()
  IFS=. read -r -a ap <<<"$acore"
  IFS=. read -r -a bp <<<"$bcore"

  local n=${#ap[@]} i x y
  (( ${#bp[@]} > n )) && n=${#bp[@]}
  for ((i = 0; i < n; i++)); do
    x=${ap[i]:-0}
    y=${bp[i]:-0}
    if [[ $x =~ ^[0-9]+$ && $y =~ ^[0-9]+$ ]]; then
      (( 10#$x > 10#$y )) && { echo 1; return; }
      (( 10#$x < 10#$y )) && { echo -1; return; }
    else
      [[ $x == "$y" ]] && continue
      if [[ $x > $y ]]; then echo 1; else echo -1; fi
      return
    fi
  done

  # Equal cores: a release outranks any prerelease of the same core.
  [[ -z $apre && -z $bpre ]] && { echo 0; return; }
  [[ -z $apre ]] && { echo 1; return; }
  [[ -z $bpre ]] && { echo -1; return; }

  local -a ai=() bi=()
  IFS=. read -r -a ai <<<"$apre"
  IFS=. read -r -a bi <<<"$bpre"

  local m=${#ai[@]}
  (( ${#bi[@]} > m )) && m=${#bi[@]}
  for ((i = 0; i < m; i++)); do
    x=${ai[i]:-}
    y=${bi[i]:-}
    [[ -z $x && -z $y ]] && continue
    [[ -z $x ]] && { echo -1; return; }
    [[ -z $y ]] && { echo 1; return; }
    if [[ $x =~ ^[0-9]+$ && $y =~ ^[0-9]+$ ]]; then
      (( 10#$x > 10#$y )) && { echo 1; return; }
      (( 10#$x < 10#$y )) && { echo -1; return; }
    elif [[ $x =~ ^[0-9]+$ ]]; then
      echo -1; return # numeric identifiers rank below alphanumeric ones
    elif [[ $y =~ ^[0-9]+$ ]]; then
      echo 1; return
    else
      [[ $x == "$y" ]] && continue
      if [[ $x > $y ]]; then echo 1; else echo -1; fi
      return
    fi
  done
  echo 0
}

selftest() {
  local -a cases=(
    '0.2.1-rc.4 0.2.1-rc.10 -1'
    '0.2.1-rc.10 0.2.1-rc.4 1'
    '0.2.1 0.2.1-rc.4 1'
    '0.2.1-rc.4 0.2.1 -1'
    '0.2.1-rc.4 0.2.1-rc.4 0'
    '0.2.1-alpha.5 0.2.1-rc.2 -1'
    '0.10.0 0.9.9 1'
    '0.2.2 0.2.1-rc.4 1'
    '1.0.0 0.2.1 1'
  )
  local failed=0 c a b want got
  for c in "${cases[@]}"; do
    read -r a b want <<<"$c"
    got=$(vercmp "$a" "$b")
    if [[ $got == "$want" ]]; then
      printf '  ok    %-18s vs %-14s -> %s\n' "$a" "$b" "$got"
    else
      printf '  FAIL  %-18s vs %-14s -> %s (want %s)\n' "$a" "$b" "$got" "$want" >&2
      failed=1
    fi
  done
  [[ $failed == 0 ]] && echo "selftest: PASS" || { echo "selftest: FAIL" >&2; exit 1; }
}

pkgbuild_value() { sed -n "s/^$1=//p" "$PKGBUILD" | head -1; }

# Version of the system package, empty when pacman does not have it installed.
pacman_version() {
  command -v pacman >/dev/null 2>&1 || return 0
  # `pacman -Q` exits 1 for an uninstalled package; tolerate it under pipefail.
  pacman -Q "$1" 2>/dev/null | awk 'NR==1 { print $2 }' || true
}

# Every dsh copy inside the npx cache, one "version<TAB>path" line each. These
# are the copies that exist when nothing was installed with pacman: `npx`
# unpacks each resolved version into ~/.npm/_npx/<hash>/ and keeps it there
# until it is deleted, so several versions can coexist.
npx_copies() {
  local base=${NPX_CACHE_DIR:-$HOME/.npm/_npx} d pj v
  [[ -d $base ]] || return 0
  for d in "$base"/*/; do
    [[ -d $d ]] || continue
    pj="$d/node_modules/@deepseek-ai/dsh/package.json"
    [[ -f $pj ]] || continue
    v=$(grep -o '"version": *"[^"]*"' "$pj" 2>/dev/null | head -1 | sed 's/.*"\([^"]*\)"$/\1/') || true
    if [[ -n $v ]]; then
      printf '%s\t%s\n' "$v" "${d%/}"
    fi
  done
  return 0
}

fetch_dist_tags() {
  command -v curl >/dev/null || die "curl is required"
  curl -fsSL --max-time 25 "$DIST_TAGS_URL" || die "cannot reach the npm registry"
}

# Highest version among all dist-tags. Every npm publish carries at least one
# tag, so the newest release is always reachable this way; `latest` alone is
# not enough because it can lag behind `next`.
newest_from_tags() {
  local tags_json=$1 v newest=''
  while IFS= read -r v; do
    [[ -z $v ]] && continue
    if [[ -z $newest ]] || [[ $(vercmp "$v" "$newest") == 1 ]]; then
      newest=$v
    fi
  done < <(grep -oE '"[0-9][0-9A-Za-z.+-]*"' <<<"$tags_json" | tr -d '"' | sort -u)
  printf '%s' "$newest"
}

# Replace the first sha256sums entry (the dsh tarball) in $2, output to stdout.
replace_tarball_sum() {
  local file=$1 sum=$2
  awk -v h="$sum" '
    /^sha256sums=\(/ {
      print
      if ((getline line) > 0) { sub(/[0-9a-f]+/, h, line); print line }
      next
    }
    { print }
  ' "$file"
}

do_bump() {
  local current=$1 newest=$2 rel=$3
  local tarball sha orig backup pkgver_expected pkgver_got

  if [[ $rel != 1 && $force == 0 ]]; then
    echo "Already at the newest published version ($current); nothing to bump."
    [[ $mode == build ]] && exec ./verify-package.sh
    exit 0
  fi
  if [[ $rel != 1 ]]; then
    echo "Forcing a rewrite of $current (--force)."
  fi

  tarball=$(printf "$TARBALL_URL" "$newest")
  tmp=$(mktemp)

  echo "==> downloading $newest tarball"
  curl -fsSL --max-time 180 -o "$tmp.tgz" "$tarball" || die "cannot download $tarball"
  sha=$(sha256sum "$tmp.tgz" | cut -d' ' -f1)
  rm -f "$tmp.tgz"

  sed "s/^_npmver=.*/_npmver=$newest/" "$PKGBUILD" >"$tmp"
  replace_tarball_sum "$tmp" "$sha" >"$tmp.new"
  mv "$tmp.new" "$tmp"

  pkgver_expected=${newest/-/}

  echo "==> _npmver: $current -> $newest"
  echo "==> tarball sha256: $sha"
  echo
  diff -u "$PKGBUILD" "$tmp" || true
  echo

  if [[ $dry_run == 1 ]]; then
    echo "Dry run: PKGBUILD not written."
    return 0
  fi

  backup=$(mktemp)
  cp "$PKGBUILD" "$backup"
  cp "$tmp" "$PKGBUILD"

  if ! makepkg --printsrcinfo >"$tmp.srcinfo"; then
    cp "$backup" "$PKGBUILD"
    rm -f "$tmp.srcinfo"
    die "makepkg --printsrcinfo failed; PKGBUILD restored"
  fi
  mv "$tmp.srcinfo" .SRCINFO
  pkgver_got=$(sed -n 's/^[[:space:]]*pkgver = //p' .SRCINFO | head -1)
  if [[ $pkgver_got != "$pkgver_expected" ]]; then
    cp "$backup" "$PKGBUILD"
    die "generated .SRCINFO pkgver '$pkgver_got' != expected '$pkgver_expected'; PKGBUILD restored"
  fi
  rm -f "$backup"

  echo "==> updated PKGBUILD and .SRCINFO (pkgver $pkgver_got)"

  if [[ $mode == build ]]; then
    echo "==> building and verifying"
    ./verify-package.sh
  else
    echo
    echo "Next: ./update-package.sh --build   (rebuild + smoke test)"
  fi
}

# --- argument parsing -------------------------------------------------------

while (($#)); do
  case $1 in
    --check) mode=check ;;
    --bump) mode=bump ;;
    --build) mode=build ;;
    --selftest) mode=selftest ;;
    --dry-run) dry_run=1 ;;
    --force) force=1 ;;
    --json) json=1 ;;
    -h | --help) usage; exit 0 ;;
    *)
      echo "unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

if [[ $mode == selftest ]]; then
  selftest
  exit 0
fi

[[ -f $PKGBUILD ]] || die "no PKGBUILD in $PWD"

current=$(pkgbuild_value _npmver)
[[ -n $current ]] || die "cannot read _npmver from PKGBUILD"
# PKGBUILD derives pkgver from _npmver (`pkgver=${_npmver/-/}`), so the literal
# sed result is not usable here; derive it the same way the PKGBUILD does.
current_pkgver=${current/-/}
pkgname=$(pkgbuild_value pkgname)

if [[ $json == 1 && $mode == check ]]; then
  echo "==> querying npm dist-tags for @deepseek-ai/dsh" >&2
else
  echo "==> querying npm dist-tags for @deepseek-ai/dsh"
fi
tags_json=$(fetch_dist_tags)
newest=$(newest_from_tags "$tags_json")
[[ -n $newest ]] || die "cannot determine newest version from dist-tags: $tags_json"
rel=$(vercmp "$newest" "$current")

pacman_installed=$(pacman_version "$pkgname")
npx_lines=$(npx_copies)

if [[ $json == 1 && $mode == check ]]; then
  update=false
  [[ $rel == 1 ]] && update=true
  [[ -n $pacman_installed ]] && pacman_json="\"$pacman_installed\"" || pacman_json=null
  npx_json='['
  first=1
  while IFS=$'\t' read -r v p; do
    [[ -z $v ]] && continue
    [[ $first == 1 ]] || npx_json+=','
    first=0
    npx_json+=$(printf '{"version":"%s","path":"%s"}' "$v" "$p")
  done <<<"$npx_lines"
  npx_json+=']'
  printf '{"current":"%s","current_pkgver":"%s","newest":"%s","update_available":%s,"pacman_installed":%s,"npx_copies":%s,"dist_tags":%s}\n' \
    "$current" "$current_pkgver" "$newest" "$update" "$pacman_json" "$npx_json" "$tags_json"
  [[ $rel == 1 ]] && exit 1
  exit 0
fi

echo
printf '  pkgbuild   %s  (pkgver %s; what a rebuild would install)\n' "$current" "$current_pkgver"
if [[ -n $pacman_installed ]]; then
  printf '  pacman     %s  (installed system package)\n' "$pacman_installed"
else
  printf '  pacman     not installed\n'
fi
if [[ -n $npx_lines ]]; then
  while IFS=$'\t' read -r v p; do
    [[ -z $v ]] && continue
    printf '  npx        %s  (%s)\n' "$v" "$p"
  done <<<"$npx_lines"
else
  printf '  npx        no cached copies\n'
fi
printf '  newest     %s\n' "$newest"
printf '  dist-tags  %s\n' "$(tr -d '{}"' <<<"$tags_json" | tr ',' ' ')"
echo

if [[ $mode == check ]]; then
  # Report every copy that lags behind, including npx caches that pacman does
  # not manage and therefore never updates on its own.
  stale=0
  while IFS=$'\t' read -r v p; do
    [[ -z $v ]] && continue
    if [[ $(vercmp "$v" "$newest") == -1 ]]; then
      stale=1
      echo "note: npx copy $v at $p is behind $newest"
      echo "      update: npx --yes @deepseek-ai/dsh@$newest web"
      echo "      (a running dsh web process keeps its version until restarted)"
    fi
  done <<<"$npx_lines"

  if [[ $rel == 1 ]]; then
    echo "Update available: pkgbuild $current -> $newest"
    echo "Run: ./update-package.sh --bump   (then install the rebuilt package)"
    exit 1
  fi
  if [[ $stale == 1 ]]; then
    echo "PKGBUILD is up to date, but a cached npx copy is behind (see notes above)."
    exit 0
  fi
  echo "Up to date."
  exit 0
fi

do_bump "$current" "$newest" "$rel"
