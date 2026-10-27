#!/usr/bin/env bash
#
# Build the deepseek-harness package and smoke-test the artifact without
# installing it. Everything happens in a temporary directory; ~/.dsh is not
# touched.
#
#   ./verify-package.sh
#   DSH_TEST_PORT=3199 ./verify-package.sh
#
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"

for tool in makepkg node npm curl bsdtar; do
  command -v "$tool" >/dev/null || { echo "missing required tool: $tool" >&2; exit 1; }
done

echo "==> building package"
makepkg --nodeps -f

pkg=$(ls -1t deepseek-harness-*.pkg.tar.zst 2>/dev/null | head -1)
[[ -n $pkg ]] || { echo "no package artifact produced" >&2; exit 1; }
echo "==> artifact: $pkg"

work=$(mktemp -d)
webpid=
cleanup() {
  [[ -n $webpid ]] && kill "$webpid" 2>/dev/null || true
  rm -rf "$work"
}
trap cleanup EXIT

echo "==> extracting into a scratch root"
bsdtar -xf "$pkg" -C "$work"

dsh="$work/usr/lib/deepseek-harness/node_modules/.bin/dsh"
[[ -x $dsh ]] || { echo "launcher missing at $dsh" >&2; exit 1; }

echo "==> dsh --version"
version=$("$dsh" --version)
echo "    $version"

port=${DSH_TEST_PORT:-3180}
home="$work/home"
mkdir -p "$home"
log="$work/web.log"

echo "==> booting the packaged Web UI on 127.0.0.1:$port (isolated HOME/DSH_HOME)"
HOME="$home" DSH_HOME="$home/.dsh" "$dsh" web --no-open --port "$port" >"$log" 2>&1 &
webpid=$!

url=
for _ in $(seq 1 90); do
  url=$(grep -oE "http://127\.0\.0\.1:$port/\?token=[A-Za-z0-9_-]+" "$log" 2>/dev/null | head -1 || true)
  [[ -n $url ]] && break
  if ! kill -0 "$webpid" 2>/dev/null; then
    echo "FAIL: Web UI process exited before serving" >&2
    tail -40 "$log" >&2
    exit 1
  fi
  sleep 1
done
if [[ -z $url ]]; then
  echo "FAIL: no authenticated URL printed on 127.0.0.1:$port" >&2
  tail -40 "$log" >&2
  exit 1
fi
echo "    printed URL: ${url%%\?*}?token=<redacted>"

bare=$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:$port/")
[[ $bare == 401 ]] || { echo "FAIL: bare origin returned $bare, expected 401" >&2; exit 1; }
echo "    bare origin: HTTP $bare (auth fence)"

jar="$work/cookies"
token=$(curl -s -c "$jar" -o /dev/null -w '%{http_code}' "$url")
[[ $token == 303 || $token == 302 ]] || { echo "FAIL: token URL returned $token" >&2; exit 1; }
echo "    token URL: HTTP $token (session cookie issued)"

page="$work/page.html"
app=$(curl -s -b "$jar" -o "$page" -w '%{http_code}' "http://127.0.0.1:$port/")
[[ $app == 200 ]] || { echo "FAIL: authenticated page returned $app" >&2; exit 1; }
grep -q '<title>DeepSeek Harness</title>' "$page" \
  || { echo "FAIL: authenticated page is not the Web UI shell" >&2; exit 1; }
echo "    authenticated page: HTTP $app, $(wc -c <"$page") bytes, title 'DeepSeek Harness'"

echo "==> first run initialized the profile from shipped templates:"
find "$home/.dsh/profiles" -maxdepth 2 -name package.json | sed 's/^/    /' || true

kill "$webpid" 2>/dev/null || true
webpid=
wait 2>/dev/null || true

echo "PASS: package builds and the packaged dsh serves the authenticated Web UI"
