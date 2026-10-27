# DeepSeek Harness on Arch Linux

A real pacman package for [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness)
(`dsh`) — the open-source agent harness from DeepSeek AI — covering the **CLI and
Web UI**, which upstream supports on Linux through npm.

## Is DeepSeek Harness open source?

**Yes.** Verified on 2026-10-27 against the published artifacts, not just the website:

| Check | Result |
|---|---|
| Repository | <https://github.com/deepseek-ai/deepseek-harness> — `"private": false`, `"visibility": "public"` |
| License (GitHub API `license`) | **MIT** |
| License file in the npm package | `MIT License`, `Copyright (c) 2026 DeepSeek` |
| npm package | [`@deepseek-ai/dsh`](https://www.npmjs.com/package/@deepseek-ai/dsh) — `license: MIT`, public registry, `publishConfig.access: public` |
| Every `@deepseek-ai/dsh-*` package | `license: MIT` (a few bundled third-party helpers carry their own licenses: `@deepseek-ai/libreoffice-kit` MPL-2.0, `@deepseek-ai/node-addon-system` BSD-3-Clause) |
| License disclosure | repo [`THIRD_PARTY_NOTICES.md`](https://github.com/deepseek-ai/deepseek-harness/blob/master/THIRD_PARTY_NOTICES.md) |

## Build and install

Fastest path — the artifact is already built and smoke-tested in this directory:

```sh
cd arch/deepseek-harness
sudo pacman -U deepseek-harness-0.2.1rc.4-1-x86_64.pkg.tar.zst
```

To build it yourself (or on another machine):

```sh
cd arch/deepseek-harness

# build + install (pacman asks for your sudo password)
makepkg -si

# or build only: leaves the .pkg.tar.zst in this directory
makepkg
```

Either path pulls `nodejs` and `pnpm` from the repositories; building also needs
`base-devel` (for `makepkg`/`fakeroot`) and `npm` (`makedepends`). The build resolves
the npm dependency closure from the public registry, so it needs network access.
Expect about two minutes and ~1 GB of scratch space (`src/`), which you can delete
afterwards with `rm -rf src pkg`. The installed tree is ~667 MiB, dominated by the
bundled LibreOfficeKit WASM runtime (~146 MB), per-package TypeScript sources, and the
cross-platform native prebuilds that upstream packages ship.

Installing does not start anything. Check the result, then start the UI:

```sh
pacman -Q deepseek-harness   # deepseek-harness 0.2.1rc.4-1
dsh --version                # 0.2.1-rc.4
dsh web                      # http://127.0.0.1:3080
```

If an `npx`-started `dsh web` is already holding port 3080 (as in this workspace),
stop it first — or run the packaged one on another port with
`dsh web --port 8080` — otherwise the bind fails. Uninstall with
`sudo pacman -R deepseek-harness`; your data under `~/.dsh` is left in place.

### What gets installed

```text
/usr/bin/dsh                                    -> /usr/lib/deepseek-harness/node_modules/.bin/dsh
/usr/lib/deepseek-harness/node_modules/          full npm dependency closure (incl. native prebuilds)
/usr/share/licenses/deepseek-harness/LICENSE     MIT
/usr/share/doc/deepseek-harness/README.md        upstream CLI README
/usr/share/applications/deepseek-harness.desktop launcher for "dsh web"
/usr/share/icons/hicolor/scalable/apps/deepseek-harness.svg
/usr/lib/systemd/user/deepseek-harness-web.service   optional user service, loopback:3080
```

### Verify without installing

`./verify-package.sh` builds the package, extracts the artifact into a temporary root,
runs `dsh --version`, and boots the Web UI against an isolated `DSH_HOME` to prove the
packaged tree is self-sufficient. Nothing is written outside the temp directory.

### Verified

Built and smoke-tested on CachyOS (Arch-based) on 2026-10-27, from this directory:

| Check | Result |
|---|---|
| `makepkg --nodeps -f` | package `deepseek-harness-0.2.1rc.4-1-x86_64.pkg.tar.zst`, 118 MB compressed / 667 MiB installed, 68,227 entries, 616 npm packages installed into the tree |
| `dsh --version` from the extracted artifact | `0.2.1-rc.4` |
| Fresh `HOME`/`DSH_HOME` boot of `dsh web --no-open --port 3180` | served `http://127.0.0.1:3180/?token=…` |
| HTTP fence | bare `GET /` → **401**; token URL → **303** + session cookie; cookie `GET /` → **200**, 37,971-byte page, `<title>DeepSeek Harness</title>` |
| First-run profile init | `~/.dsh/profiles/web/{package.json,cordis.yml,cordis.patch.yml,pnpm-workspace.yaml}` created from shipped templates, no network needed |
| Bundled native assets | `@vscode/ripgrep-linux-x64/bin/rg`, `sherpa-onnx-linux-x64/sherpa-onnx.node` |
| Desktop entry | `desktop-file-validate` clean |
| systemd unit | syntax verified; `systemd-analyze verify` only complains that `/usr/bin/dsh` does not exist until the package is installed |
| Update tooling | `--selftest` 9/9 comparator cases; an rc.2 copy reported "update available" (exit 1), `--bump` reproduced tarball sha256 `1fddead…` and `.SRCINFO` pkgver `0.2.1rc.4`, and the re-check exited 0. The check reports pacman/npx copies too (verified with a simulated installed package, an absent npx cache, and a stale npx copy — the last correctly printed the `npx --yes @deepseek-ai/dsh@0.2.1-rc.4 web` hint) |

`--nodeps` was used only because this machine has Node from `fnm` rather than the
`nodejs` package; on a normal Arch install `makepkg -si` resolves `nodejs`/`pnpm`/`npm`
through pacman. The package was **not** installed system-wide in this run (no
passwordless sudo), so `pacman -U`/`makepkg -si` is the step left for you.

## Usage

```sh
dsh web                          # Web UI on http://127.0.0.1:3080 (opens a browser)
dsh web --no-open --port 8080    # server only, another port
dsh --profile headless "job"     # one task, print the answer, exit
dsh plugin --profile web add ...  # profile plugin management (uses pnpm)
dsh --version
```

The Web UI prints an authenticated URL; open that one, not just the bare origin.

### As a user service

```sh
systemctl --user daemon-reload
systemctl --user enable --now deepseek-harness-web.service
journalctl --user -u deepseek-harness-web.service -f   # shows the URL/token
```

The unit runs `dsh web --no-open`, which binds `127.0.0.1:3080` (the built-in default
host is loopback-only). To expose it on another interface, run the CLI with
`--host <address>` yourself instead of using the unit.

### First launch

The Web UI asks for a model provider and stores credentials under
`${DSH_HOME:-~/.dsh}/.credentials.yaml`. Profiles live in `~/.dsh/profiles/`; adding
plugins there uses pnpm, hence the runtime dependency.

## Tracking upstream updates

Nothing in the installed system polls upstream: the harness has no updater of its
own (that is desktop-only) and pacman never phones home. Two helpers close that gap
for a locally maintained package:

```sh
./check-updates.sh            # 0 = up to date, 1 = newer version, 2 = error
./check-updates.sh --json     # machine-readable, for scripts and timers
./bump-package.sh             # bump _npmver + tarball sha256 + .SRCINFO, show the diff
./bump-package.sh --dry-run   # show what would change without writing
./bump-package.sh --build     # bump, then rebuild and run ./verify-package.sh
```

The check compares `_npmver` against the newest version across **all** npm
dist-tags, not only `latest`: upstream keeps `latest` behind `next` (when this
package was built, `latest` = `0.2.1-rc.2` while `next` = `0.2.1-rc.4`), so a naive
`npm view … version` check reports "up to date" while a newer prerelease exists. The
comparator is prerelease-aware (`rc.4 < rc.10 < 0.2.1`); `./update-package.sh
--selftest` exercises it.

The same output shows **which copies actually exist**: the PKGBUILD version, the
pacman-installed package (if any), every `dsh` tree left in the npx cache, and the
newest upstream release. Stale npx copies get the exact upgrade command:

```sh
  pkgbuild   0.2.1-rc.4  (pkgver 0.2.1rc.4; what a rebuild would install)
  pacman     not installed
  npx        0.2.1-rc.2  (/home/user/.npm/_npx/1e7f6d9597241db0)
  newest     0.2.1-rc.4

note: npx copy 0.2.1-rc.2 at /home/user/.npm/_npx/1e7f6d9597241db0 is behind 0.2.1-rc.4
      update: npx --yes @deepseek-ai/dsh@0.2.1-rc.4 web
```

### If nothing is installed (the npx case)

`npx @deepseek-ai/dsh web` installs nothing permanently: it unpacks the resolved
version into `~/.npm/_npx/<hash>/` and runs from there, so that cache — not
pacman — is what you have to update. Two traps:

- Plain `npx @deepseek-ai/dsh web` resolves the `latest` tag, which is currently
  **older** than `next`; use an explicit version (`@0.2.1-rc.4`) or `@next`.
- A running `dsh web` process keeps its loaded version until restarted. Start the
  new copy on another port first (`--port 8080`), and stop the old one when ready.

Old npx trees are ~835 MB each; delete ones no process is using under
`~/.npm/_npx/` to reclaim space.

`--bump` rewrites `_npmver`, downloads the matching tarball to compute its sha256,
regenerates `.SRCINFO` with `makepkg --printsrcinfo`, and restores the PKGBUILD if
the generated metadata does not come out consistent. `--check` needs only bash and
curl; `--bump`/`--build` also need `makepkg` plus the `nodejs`/`npm` toolchain.

If the package is published to the AUR (next section), an AUR helper can do the
scanning instead: `paru -Sua` / `yay -Sua` compare `pkgver` and flag updates.

## Reproducibility caveat

Only the `@deepseek-ai/dsh` launcher tarball is checksummed. Its dependency ranges
(`~4.0.5`, `^15.0.0`, …) are resolved at build time, so a rebuild weeks later can pull
different transitive versions. The `@deepseek-ai/*` packages themselves are pinned to
the exact rc version by the launcher's manifest. If you need bit-for-bit reproducible
builds, add a generated `package-lock.json` as a checksummed source and switch
`prepare()` from `npm install` to `npm ci --omit=dev`; that is deliberately not done
here because the lockfile has to be regenerated for every release.

## Publishing to the AUR

The AUR name `deepseek-harness` was **unclaimed on 2026-10-27** (RPC `resultcount`
0), while `deepseek-harness-bin`, `deepseek-harness-git` and
`deepseek-harness-desktop` already exist. If the plain name is still free,
publishing is a few commands:

1. Create an AUR account and register an SSH public key at
   <https://aur.archlinux.org/account>.
2. Clone the empty package repository:

   ```sh
   git clone ssh://aur@aur.archlinux.org/deepseek-harness.git
   cd deepseek-harness
   ```

3. Copy the packaging files it needs:

   ```sh
   cp /path/to/arch/deepseek-harness/{PKGBUILD,.SRCINFO,deepseek-harness.install,deepseek-harness.svg,deepseek-harness-web.service,deepseek-harness.desktop} .
   ```

4. Keep `.SRCINFO` in sync and push:

   ```sh
   makepkg --printsrcinfo > .SRCINFO
   git add -A
   git commit -m "upgpkg: deepseek-harness 0.2.1rc.4-1"
   git push
   ```

5. Users install with `paru -S deepseek-harness` (or `yay -S …`); helpers report
   new versions through `paru -Qua` and upgrade with `paru -Sua` — that is the
   "scanning" side of updates for AUR-installed copies.

Notes: the AUR package builds on the user's machine and downloads the npm
dependency closure in `prepare()`, which is the documented reproducibility caveat
and the reason `makedepends=('npm')` is declared. `conflicts` covers the `-bin` /
`-git` harness variants and the unrelated AUR `dsh` (distributed shell), which
also owns `/usr/bin/dsh`. The helper scripts (`check-updates.sh`,
`bump-package.sh`, `update-package.sh`, `verify-package.sh`) are optional in the
AUR repository — the PKGBUILD does not reference them.

## The desktop app on Linux

Upstream states it directly in [`apps/desktop/packaging/README.md`](https://github.com/deepseek-ai/deepseek-harness/blob/master/apps/desktop/packaging/README.md):
**"Linux is not a supported Desktop release target."** The official download page
offers Windows 64-bit and macOS (Apple Silicon) only, and no Linux artifact is
published. The Electron-builder config does contain a `linux: { target: ['AppImage'] }`
stanza, but it is not a supported release lane. The existing AUR packages show two
viable routes if you want the GUI:

| Route | Package | Notes |
|---|---|---|
| Build from source | `deepseek-harness-desktop` (AUR) | Patches the repo's packaging target; bundles Electron, Node, CPython and Office libraries. ~15–25 min and ~6 GB scratch. |
| Third-party prebuilt | `dsh-desktop-linux-bin` (AUR) | Repacks a community Linux `.deb` build; not an upstream artifact. |

Neither is part of this package. If you want a desktop build maintained here, the
source-build route is the one to reproduce; it is a separate, much heavier package.

## Notes

- The AUR already carries `deepseek-harness-bin` (rc.2 at the time of writing, flagged
  out of date). This package tracks the current npm release (rc.4), installs into
  `/usr/lib/deepseek-harness`, and ships the launcher plus the user service; it
  declares conflicts with the `-bin`/`-git` variants and with the unrelated AUR `dsh`
  (distributed shell), which also owns `/usr/bin/dsh`.
- The plain AUR name `deepseek-harness` was unclaimed on 2026-10-27; see the
  publishing section above for the exact steps.
- Removing the package leaves `~/.dsh` untouched on purpose.
- DeepSeek Harness is in **developer preview**; upstream warns that breaking changes
  will happen between releases.
