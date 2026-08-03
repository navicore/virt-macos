# Design: Direct Kernel Boot for Headless VMs

**Date**: 2026-08-03
**Status**: Implemented

## Intent

The headless console depends on a manual post-install step: editing GRUB
inside the guest to add `console=hvc0`. It is invisible (EFI/GRUB render to
an unseen framebuffer), unverifiable from the host, and its failure mode —
a blank terminal — is indistinguishable from a hang. This was the top
remaining source of "never got a solid machine".

`VZLinuxBootLoader` boots a kernel directly with a host-controlled command
line: `console=hvc0` is guaranteed, output starts in ~1s, and neither EFI
nor GRUB is involved. Chosen over automating the GRUB edit (still
invisible/unverifiable) and over unattended preseed installs (distro-specific;
revisit later).

## Constraints

- **Opportunistic default**: `virt start` uses direct boot when kernel files
  exist in the VM directory, otherwise the EFI path is unchanged
- `virt install` always uses EFI — installers and GRUB need real firmware
- Kernel/initrd live in the guest's ext4 disk (unreadable from macOS), so
  extraction goes through the virtiofs share: one explicit, verifiable step
- Direct boot must fail loudly and verifiably at import time, never silently
  at boot time

## Approach

### Kernel import

New command: `virt kernel-import <name> --from <dir> [--root <dev>] [--kernel-args <args>]`

The user copies the running kernel out of the guest via the share
(Debian/Ubuntu provide stable `/vmlinuz` and `/initrd.img` symlinks), then
imports:

```
virt install myvm --share ~/vm-share
# in guest: cp -L /vmlinuz /initrd.img /mnt/share/
virt kernel-import myvm --from ~/vm-share
```

The command:
- Finds `vmlinuz` (or newest `vmlinuz-*`) and `initrd.img` (or `initrd.img-*`/
  `initramfs-*`) in `--from`
- Validates the kernel is a bootable arm64 image — raw `ARM\x64` magic, or a
  PE/COFF machine type; x86 is a hard error
- Decompresses gzip (zboot) kernels automatically — VZLinuxBootLoader only
  boots uncompressed Images
- Copies them into the VM directory as `kernel` and `initrd`
- Records the root device (default `/dev/vda2`, Debian guided-layout) and any
  extra kernel args in config.json

Kernel updates in the guest require re-import — same copy step, repeated.

### Boot selection (`virt start` only)

- `kernel` + `initrd` present → `VZLinuxBootLoader` with
  `console=hvc0 root=<rootDevice> ro [extraArgs]`
- Otherwise → EFI/NVRAM path exactly as before, with a stderr hint that
  direct boot is available
- Partial state (only one of kernel/initrd) → warning, EFI fallback

## Domain Events

| Event | What follows |
|---|---|
| Kernel Imported | arm64 magic verified; kernel/initrd copied to VM dir; root device saved |
| Headless Start (direct) | Kernel cmdline assembled host-side; console output in ~1s |
| Headless Start (EFI) | Legacy path; stderr hints that kernel-import enables direct boot |

## Lessons learned

- **VZLinuxBootLoader only boots uncompressed arm64 Images.** Distro kernels
  are gzip-compressed zboot (PE/COFF wrapper); booting one fails with an
  opaque "Internal Virtualization error". Extract via the gzip magic bytes
  (like scripts/extract-vmlinux) and validate the raw `ARM\x64` magic
  afterwards.
- The `ARM\x64` magic at offset 56 is NOT present in compressed kernels —
  it survives an EFI-stub "MZ" prefix but not compression. PE machine type
  (0xAA64 at the PE header) identifies arm64 compressed images.
- macOS `hdiutil` refuses to mount hybrid (GPT+ISO9660) distro ISOs —
  host-side ISO file extraction needs a parser (pycdlib worked for the
  smoke test) if we ever ship `--from-iso` import.

## Checkpoints

1. ✅ `swift build` + `swift test` pass (kernel magic, config round-trip)
2. ✅ Import rejects a non-arm64 or missing kernel
3. ✅ `virt start` with kernel/initrd present — real arm64 kernel boots,
   kernel messages appear on the terminal (smoke-tested with Alpine)
4. ✅ `virt start` without kernel files — EFI path unchanged, hint printed
