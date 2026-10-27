# Maintainer: eumerdev
#
# Arch Linux package for DeepSeek Harness (`dsh`), the open-source agent
# harness from DeepSeek AI: https://github.com/deepseek-ai/deepseek-harness
#
# Scope: the CLI plus the Web UI. Upstream publishes the Electron desktop
# application for Windows and macOS only, so a Linux desktop build is not part
# of this package; see README.md for the desktop options.
#
# The npm package is the upstream-supported way to run dsh on Linux. Its
# production dependency closure is resolved from the public npm registry in
# prepare() and then frozen into the package; only the dsh launcher tarball is
# checksummed. README.md records that reproducibility caveat.

pkgname=deepseek-harness
_npmver=0.2.1-rc.4
pkgver=${_npmver/-/}
pkgrel=1
pkgdesc='Open-source agent harness from DeepSeek: CLI and Web UI'
arch=('x86_64' 'aarch64')
url='https://github.com/deepseek-ai/deepseek-harness'
license=('MIT')
depends=('nodejs' 'pnpm')
makedepends=('npm')
conflicts=(
  'deepseek-harness-bin'
  'deepseek-harness-git'
  # AUR `dsh` is the unrelated distributed shell and owns /usr/bin/dsh too.
  'dsh'
)
options=('!strip' '!debug')
install="$pkgname.install"

# Desktop artwork: apps/desktop/resources/icon.svg from the upstream repository
# (MIT), pinned to commit 22ddee3792402c3e70ec5f86a63c3e3e895a2f60.

source=(
  "dsh-$_npmver.tgz::https://registry.npmjs.org/@deepseek-ai/dsh/-/dsh-$_npmver.tgz"
  'deepseek-harness.svg'
  'deepseek-harness-web.service'
  'deepseek-harness.desktop'
)
sha256sums=(
  '1fddead34d3c943b7a4eed1d614e14fa19925803455e28c5141645caf4b02d13'
  '0458ed5e4825846a6560e90d3e4de767cd75842f7eb53539dc87a5db380d9146'
  '62610d7a259aca07d2c951bcc47dc9802c4b1599735504450d0f4bf2b65af24e'
  'e4d258438364345f5bebf8acb90fef5d20df30a270eae958ca5f72a00e88fe50'
)

prepare() {
  cd "$srcdir"
  rm -rf npmproj npm-cache
  mkdir -p npmproj npm-cache

  cd npmproj
  # Resolve the launcher and its full production dependency closure. Optional
  # platform packages (native prebuilds, @vscode/ripgrep) follow the build
  # architecture, so the package is architecture-specific even though the
  # launcher itself is plain JavaScript.
  npm install \
    --omit=dev \
    --no-audit \
    --no-fund \
    --no-progress \
    --loglevel=error \
    --cache "$srcdir/npm-cache" \
    "$srcdir/dsh-$_npmver.tgz"
}

package() {
  local _libdir="$pkgdir/usr/lib/$pkgname"

  install -d "$_libdir"
  cp -a "$srcdir/npmproj/node_modules" "$_libdir/"

  # npm links node_modules/.bin/dsh to ../@deepseek-ai/dsh/lib/bin.js; the
  # relative link keeps working under /usr/lib and the absolute launcher link
  # exposes it as dsh.
  install -d "$pkgdir/usr/bin"
  ln -s "/usr/lib/$pkgname/node_modules/.bin/dsh" "$pkgdir/usr/bin/dsh"

  install -Dm644 "$srcdir/package/LICENSE" "$pkgdir/usr/share/licenses/$pkgname/LICENSE"
  install -Dm644 "$srcdir/package/README.md" "$pkgdir/usr/share/doc/$pkgname/README.md"

  install -Dm644 "$srcdir/deepseek-harness-web.service" \
    "$pkgdir/usr/lib/systemd/user/deepseek-harness-web.service"
  install -Dm644 "$srcdir/deepseek-harness.desktop" \
    "$pkgdir/usr/share/applications/deepseek-harness.desktop"
  install -Dm644 "$srcdir/deepseek-harness.svg" \
    "$pkgdir/usr/share/icons/hicolor/scalable/apps/deepseek-harness.svg"
}
