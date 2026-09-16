# Design: Reliability Hardening (Post-Audit)

**Date**: 2026-08-03
**Status**: Implemented

## Intent

An end-to-end audit (build, commands, code, live behavior) found that virt's
core flows work, but a layer of trust and safety bugs made the tool feel
unreliable: silent failures, wrong-target signals, disk-corruption windows,
and no diagnostics when a boot went wrong. This design hardens the existing
commands without changing the UX model.

Key audit findings addressed here:

- **PID file was trusted blindly** — a recycled PID made `list` lie and made
  `stop` signal an innocent process (reproduced live)
- **x86 ISOs accepted silently** — the only ISO on the dev machine was
  x86_64; attaching it produced a black window with no error
- **Window close hard-killed the guest** — 2s grace, then process exit
  regardless of guest state: filesystem corruption risk
- **Shutdown requested during early boot** exited the process immediately
  (`canRequestStop` false → no fallback): another hard-kill window
- **Failed `vm.start` exited 0** — async error was printed but never
  propagated
- **Force-killed `virt start` left the user's terminal in raw mode** (no
  echo) — looked like the tool broke the shell
- **New random MAC every boot** — IP churn, ssh `known_hosts` churn
- **No diagnostics** — when a boot failed there was nothing to inspect

## Constraints

- No UX changes: same commands, same flags
- Fixes must not regress the headless console or GUI install flows
- Locking must be race-free (flock, not check-then-act on PID files)

## Approach

### 1. Lock file replaces PID-file trust (C1, C4, M5)

`vm.lock` in each VM directory, held with `flock(LOCK_EX)` for the lifetime
of a running `start`/`install` process. Locks die with the process, so:

- `start`/`install`: `flock(LOCK_EX|LOCK_NB)` — atomic, no TOCTOU race
- `list`/`stop`/`delete`: try the lock; held = genuinely running
- `stop` still reads `vm.pid` to find *where* to signal, but only after
  confirming the lock is held — so the PID can never belong to a stranger

### 2. ISO architecture preflight (C5)

`virt install --iso` scans the image for EFI boot markers
(`BOOTAA64`/`arm64-efi` → arm64; `BOOTX64`/`x86_64-efi` → x86). x86 is a
hard error with a clear message; undetermined prints a warning and proceeds.

### 3. Graceful shutdown everywhere (C3, H5)

- `requestShutdown()` now only records intent; the ACPI request is issued by
  `issueStopIfPossible()` once `canRequestStop` is true — early-boot stops
  wait for the guest instead of hard-exiting
- GUI: `windowShouldClose` vetoes close while the guest runs, requests
  shutdown, and closes only when the guest stops (15s cap, then forced with
  a warning)
- SIGHUP and SIGTERM join SIGINT as graceful-shutdown triggers

### 4. Terminal rescue (C2)

`virt stop` captures the target's controlling tty before SIGKILL and runs
`stty sane` on it afterwards, undoing raw mode when the killed process
couldn't restore it itself.

### 5. Correct exit codes (H4)

Async `vm.start` failure is rethrown from `runHeadless()` (non-zero exit);
GUI start failure exits 1 after cleanup.

### 6. Stable MAC addresses (H3)

`virt create` generates a locally-administered MAC, stored in config.json.
Legacy configs without one are assigned and persisted on first boot. Stable
MAC → stable DHCP lease → stable IP → ssh stops churning.

### 7. Observability (M1)

- `vm.log` in each VM directory: timestamped lifecycle events from both the
  VM process and `virt stop` (start, started, failed, shutdown, force-stop)
- stderr milestone when the VM reaches running state
- New `virt doctor` command: VZ support, binary entitlement, disk space,
  port-53 listeners (DNS culprits), VM lock states

### 8. Create-time free space check (M3)

Warn when the volume holds less than the requested disk size; hard error
below 1 GB free.

## Domain Events

| Event | What follows |
|---|---|
| VM Starting | Lock acquired (fails fast if held); PID file written; vm.log appended |
| Start Failed | Error thrown → non-zero exit; logged to vm.log |
| Shutdown Requested | Intent recorded; ACPI issued when guest can accept; 10s cap then force |
| Force Kill | SIGKILL; target's tty restored to sane; pid file removed |
| Window Close Requested | Vetoed while guest runs; proceeds once stopped |

## Checkpoints

1. ✅ `swift build` + `swift test` pass (new: lock, ISO-check, MAC tests)
2. ✅ Double `virt start` — second instance fails "already running"
3. ✅ `vm.pid` pointed at an innocent live process — `list` says stopped, `stop` refuses to signal
4. ✅ `virt install --iso <x86_64.iso>` — hard error naming the architecture
5. ✅ `virt stop` after SIGKILL escalation — terminal remains usable
6. ✅ `virt doctor` — reports entitlement, disk, DNS listeners, VM states
