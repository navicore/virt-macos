# Design: clone a VM (templates)

**Date**: 2026-09-28
**Status**: Implemented — `virt clone <source> <new-name> [--description ...]`.
Disk copy via `clonefile(2)` with `FileManager.copyItem` fallback; fresh MAC
via `VZMACAddress.randomLocallyAdministered()`; NVRAM and kernel-boot files
copied when present; transient files (pid/lock/log) excluded. Verified
end-to-end (create → clone → config diff → delete) plus unit tests.

## Intent

Port virt-linux's `clone` command: keep a fully configured VM stopped and
clone it for each new instance. The clone gets the template's disk, EFI
store, kernel-boot files, and config — restamped with a new name, a fresh
MAC, and a default `clone of <source>` description. Clones inherit network
mode, so cloning a bridge VM gives each instance its own LAN identity.

Same template workflow as virt-linux; the template stays untouched.

## Approach

### What travels, what doesn't

| File | Copied? | Notes |
|---|---|---|
| `config.json` | restamped | new name/description/MAC; hardware, boot, network pass through |
| `disk.raw` | yes | APFS clone — see below |
| `nvram.bin` | yes | EFI variable store, when present |
| `kernel`, `initrd` | yes | direct-kernel-boot files, when present |
| `vm.pid`, `vm.lock`, `vm.log` | no | transient; the clone's log starts with its own clone entry |

Guards, in order: source exists; new name passes `nameValidationError`
(same rules as virt-linux — names move between the tools unchanged);
destination does not exist; source not locked (flock is authoritative, PID
file only adds detail to the error). On any failure after `dst.create()`,
the destination directory is removed — no half-cloned VMs.

### APFS clonefile instead of sparse cp

virt-linux copies the disk with `cp --sparse=always` (holes preserved;
usage, not declared size, gets written). macOS does better: `clonefile(2)`
creates a copy that shares blocks copy-on-write — instant even for a 100 GB
template, and near-zero extra space until either side writes. The clone and
template are fully independent afterward (writes are private). `clonefile`
is available macOS 10.12+ (we target 13+) but can fail on non-APFS
filesystems or exotic setups; the fallback is `FileManager.copyItem`
(a plain byte copy, reported as such in the output).

### Guest identity

virt-linux runs `virt-sysprep` (libguestfs) to reset machine-id, SSH host
keys, and hostname — no libguestfs port exists for macOS, so the macOS clone
resets only host-side identity (MAC) and prints a note pointing at the
in-guest reset commands (documented in the README). k3s-style users must run
those commands once inside each clone; there is deliberately no `--no-sysprep`
flag here because there is no sysprep to skip.

### Small parity wins shipped with it

- **VM name validation** (`VMDirectory.nameValidationError`), used by
  `create` and `clone` — mirrors virt-linux's `validate_name`.
- **NETWORK column in `virt list`** (`VMConfig.networkDisplay`):
  `nat` / `bridge (en0)` / `bridge (primary)`.

## CLI surface

```
virt clone <source> <new-name> [--description <text>]
```

Output: clone summary, disk size + copy mode (APFS clone vs full copy),
fresh MAC, path, and the guest-identity note.

## Test plan

- `CloneTests.performCopiesDiskAndRestampsIdentity` — synthetic VM: config
  restamped (name/description/MAC) with hardware, boot, and network fields
  intact; disk/NVRAM/kernel/initrd copied; `vm.pid` does not travel.
- `CloneTests.apfsClonePreservesContent` — clonefile path preserves bytes.
- `CloneTests.humanBytesFormats` — MB/GB formatting from logical size;
  doubles as a regression test for `URL.resourceValues` staleness (use
  `FileManager.attributesOfItem`, which always stats fresh).
- `VMDirectoryTests.nameValidation`, `VMConfigTests.withCloneIdentity...`
  and `networkDisplayModes` for the parity helpers.

## Out of scope

- Linked/overlay clones beyond what APFS CoW gives for free.
- `lan:NAME` cluster networking (virt-linux feature) — Virtualization
  framework has no multicast-socket L2 fabric; would need a different
  mechanism entirely.
- In-guest identity reset (needs a guest-aware offline editor, which is
  exactly the libguestfs dependency we don't have on macOS).
