# Design: CI/CD and tag-driven releases

**Date**: 2026-09-24
**Status**: Proposed

## Intent

- Every PR to `main` runs the same checks as local dev (`just ci`) on real
  macOS hardware — this project is mac-only, so Linux runners can't build it.
- Push a `vX.Y.Z` tag → a release workflow stamps the version into the
  source, commits the bump back to main, builds + signs the release binary,
  and publishes a Forgejo Release with the artifact attached.
- `virt --version` reports the released version.

## Pattern

Mirror the conventions codified in patch-prolog's `.claude/commands/`
(`setup-rust-ci.md`, `setup-crates-release.md`):

- The justfile is the single source of truth for build/test/lint; workflows
  only call `just ci` / `just build`.
- The version lives in exactly one place, rewritten by the release workflow
  from the tag. Cargo gets this from `[package].version`; Swift has no
  manifest version, so we add `Sources/virt/Version.swift`.
- Release triggers on tag push (`v*`) — the GitHub `release:` event has no
  Forgejo equivalent.
- Release checks out `main` with a PAT so it can push the bump back.
- Artifacts are attached with curl against the Forgejo Releases API (no
  GitHub-only actions).

Differences forced by Swift/macOS:

- No `rust-toolchain.toml` equivalent — the runner machine's Xcode *is* the
  pin. The runner project records the pinned version; workflows print
  `swift --version` for traceability.
- The binary must be codesigned with `virt.entitlements`. Ad-hoc signing
  (current `just build` behavior) is retained; only `--network bridge`
  needs a paid Developer account, unchanged.
- CI runs on a self-hosted mac mini **host** runner (`runs-on:
  navicore-macos`), not a container — Virtualization.framework linking and
  ad-hoc codesigning work fine in CI; tests are pure unit tests (file ops
  + parsing), no GUI session needed.

## A. `virt --version`

New `Sources/virt/Version.swift`:

```swift
/// Single source of truth for the virt version.
/// Rewritten by the release workflow from the pushed vX.Y.Z tag
/// (.forgejo/workflows/release.yml) — do not hand-edit.
enum VirtVersion {
  static let current = "0.1.0"
}
```

`Virt.swift` gains `version: "virt \(VirtVersion.current)"` in
`CommandConfiguration`. swift-argument-parser then adds the `--version`
flag automatically, printing e.g. `virt 0.1.0`. (Analog of Cargo
injecting `CARGO_PKG_VERSION` into clap.)

## B. CI — `.forgejo/workflows/ci-macos.yml`

```yaml
name: CI - macOS

on:
  pull_request:
    branches: [ main ]
  workflow_dispatch:

# This workflow ONLY calls `just` commands. The justfile is the source
# of truth for all build/test/lint logic, preventing drift between
# local development and CI.
#
# `runs-on: navicore-macos` targets the self-hosted mac mini host runner
# (see ../navicore-macos-runner). Xcode + swiftlint + just are
# pre-installed there; `swift format` ships with the Xcode toolchain.

jobs:
  ci-macos:
    name: CI - macOS arm64
    runs-on: navicore-macos
    steps:
      - name: Checkout code
        uses: actions/checkout@v6

      - name: Verify toolchain
        run: |
          swift --version
          swiftlint version
          just --version

      - name: Run CI checks (just ci)
        run: just ci
```

No caching initially — mirrors the rust rule of not caching build output
for test runs, and a full `swift build` is only a few minutes on the mini.
`Package.resolved` is committed (the Cargo.lock analog).

CLT constraint: the mini has Command Line Tools only (no full Xcode),
and the CLT ships **swift-testing but not XCTest**. Test targets use
`import Testing` / `@Test` / `#expect` — SwiftPM then builds a Testing
entrypoint executable, no `xctest` needed. (virt's tests were migrated
from XCTest accordingly; the migration also runs green on full-Xcode
machines like the laptop.) Second CLT quirk: the Swift Build backend
omits the swift-testing macro plugin on CLT-only hosts, so the justfile
`test` recipe conditionally passes `-Xswiftc -load-resolved-plugin ...`
(gated on Xcode's absence) — see `test-plugin-flag` in the justfile.

## C. Release — `.forgejo/workflows/release.yml`

Trigger `on: push: tags: ['v*']`, `runs-on: navicore-macos`, job guarded
by `if: startsWith(github.ref, 'refs/tags/v')`. Steps:

1. `actions/checkout@v6` with `token: ${{ secrets.PAT }}`, `ref: main`
2. Extract `VERSION="${GITHUB_REF_NAME#v}"`.
3. Rewrite `Version.swift` with BSD sed:
   `sed -i '' "s/static let current = \".*\"/static let current = \"$VERSION\"/" Sources/virt/Version.swift`
4. Commit `chore: bump version to $VERSION` as
   `forgejo-actions[bot]@users.noreply.git.navicore.tech`, push to main
   (plain shell vars, no deprecated `set-output` — runner v13 removed it).
5. `just build` — release build + ad-hoc codesign with entitlements.
6. Smoke test: `.build/release/virt --version` must print the tag version.
7. `just dist VERSION=$VERSION` — new justfile recipe producing
   `dist/virt-$VERSION-aarch64-apple-darwin.tar.gz` + `.sha256`.
8. Create the Forgejo Release and upload the asset via the API:

```sh
# create (tag already exists — the release attaches to it)
release_id=$(curl -sS -H "Authorization: token $PAT" \
  -H 'Content-Type: application/json' \
  -d "{\"tag_name\":\"v$VERSION\",\"name\":\"virt $VERSION\"}" \
  https://git.navicore.tech/api/v1/repos/navicore/virt/releases | jq -r .id)
# attach artifact
curl -sf -H "Authorization: token $PAT" \
  -H 'Content-Type: application/octet-stream' \
  --data-binary @dist/virt-$VERSION-aarch64-apple-darwin.tar.gz \
  "https://git.navicore.tech/api/v1/repos/navicore/virt/releases/$release_id/assets?name=virt-$VERSION-aarch64-apple-darwin.tar.gz"
```

Required secret (repo Settings → Actions → Secrets): `PAT` — Forgejo
token with `write:repository` (checkout push-back + Releases API). That
is the only secret; there is no crates.io analog.

Same accepted race as the rust flow: the release builds current `main`
with the version stamped in, not the tagged commit itself.

## D. New project: `navicore/navicore-macos-runner`

Parallel to `navicore-forgejo-runner` (the Linux job image), but for a
bare-metal mac mini (**vashon.local**, arm64, macOS 26) **host** runner —
no Docker: Virtualization.framework tooling and ad-hoc codesigning want
the real OS, and Docker-on-macOS is a VM anyway. The runner dials out to
git.navicore.tech, so no ingress/NAT changes are needed.

forgejo-runner publishes **no darwin binaries** (v10–v13 releases are
linux/windows only), so the pinned tag (v13.2.0 — same v13 config schema
as the k8s runners' 13.0.0, including the Forgejo 15 UUID/token flow) is
built from source with brew Go. The mini needs no full Xcode — its
Command Line Tools already provide Swift 6.4 + `swift format`, and brew
has `just`; only `swiftlint` is missing.

Contents (written, pending install on the mini):

- `README.md` — the version pin table: Xcode CLT (Swift 6.4 — the
  toolchain pin, bumped deliberately like `rust-toolchain.toml`), brew
  `just`/`swiftlint`, forgejo-runner v13.2.0 from source
- `scripts/install.sh` — installs the pinned runner binary + brew deps,
  creates a dedicated non-admin `ci` user (a host runner executes workflow
  shell commands directly; it must not run as an admin)
- `config.yaml.template` — labels `navicore-macos:host`, `capacity: 1`,
  `timeout: 3h`, canonical server URL `https://git.navicore.tech/`
  (UUID + token rendered in by the installer; same Forgejo 15 flow as
  the k8s runners)
- `com.navicore.forgejo-runner.plist` — LaunchDaemon running
  `forgejo-runner daemon --config` as a dedicated non-admin `ci` user,
  with `KeepAlive` and a PATH that includes `/opt/homebrew/bin`
- `install.sh` / `uninstall.sh` — brew deps installed as the admin user
  (brew refuses root; never compiles as root), `ci` user creation, source
  build + ad-hoc sign, config render, daemon bootstrap

## E. Homelab doc — `k8s-vcluster-homelab/docs/08-forgejo-macos-runner.md`

Documents the runner as homelab CI infrastructure alongside the in-cluster
runners: why host-mode, registration (admin → Runners → Create, capture
UUID + Token), the `navicore-macos` label, LaunchDaemon lifecycle,
maintenance (macOS/Xcode updates — coordinate with repos that depend on
the pin), and a link to the runner repo.

## F. README updates (virt)

- Mention `virt --version`.
- "Install from release": download the tar.gz, verify sha256, untar to
  `/usr/local/bin`. Browser-downloaded files get quarantined —
  `xattr -d com.apple.quarantine` (or re-sign locally with the bundled
  entitlements); curl downloads are unaffected. The embedded ad-hoc
  signature and entitlement survive the tarball intact.

## Sequencing

1. ~~Runner project + register the runner~~ — project written
   (`navicore-macos-runner`); install on vashon.local (UUID/token from
   the admin runners page), confirm `runs-on: navicore-macos` picks up
   a job.
2. `Version.swift` + `--version` wiring (PR — exercises CI once (3) lands;
   land together).
3. `ci-macos.yml` (PR).
4. `release.yml` + `dist` recipe + `PAT` secret (PR), then push `v0.1.0`
   to validate end-to-end: bump commit on main, release page, artifact,
   `virt --version` output.
5. ~~Homelab doc `08-forgejo-macos-runner.md`~~ — written.

## Open questions

- ~~Runner repo name~~ — `navicore-macos-runner`.
- First tag: `v0.1.0` (proposed) vs `v1.0.0` — the tool is "usable and
  awesome", but 1.0 signals an API-stability promise the CLI hasn't
  promised anywhere else.
- Artifact is aarch64-only by design (Apple Silicon target; no Intel Mac
  to test a universal binary on). Revisit only if ever needed.
- Bridge networking stays ad-hoc-unsigned (paid-account-only entitlement)
  — release binaries are NOT bridge-capable unless a signing identity is
  introduced later; README already documents the restriction.
