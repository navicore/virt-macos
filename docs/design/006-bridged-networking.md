# Design: Bridged Networking

**Date**: 2026-08-03
**Status**: Implemented, but **runtime-gated** — `com.apple.vm.networking`
is a *restricted* entitlement. Ad-hoc signed binaries carrying it are
SIGKILLed at launch by amfid ("Adhoc signed app with restricted
entitlements detected"), and this machine has no signing identities.
Bridge mode is implemented and fails with a clear error unless virt is
signed with a paid Developer account.

## Intent

NAT mode (vmnet via `VZNATNetworkDeviceAttachment`) proved unreliable for
real desktop use. Fully packet-captured evidence chain from a guest TLS
stall:

1. Guest sends a full-size TCP segment with DF set (correct PMTUD behavior)
2. **Apple's NAT strips DF** when rewriting the source address
3. A low-MTU hop on the ISP path fragments the packet instead of
   dropping it (no DF → no `need to frag` ICMP is ever generated)
4. Fragments are lossy; the server answers `reassembly time exceeded` —
   an ICMP the guest's TCP stack can do nothing with
5. Guest retransmits full-size forever → TLS stalls, Firefox "no internet"

Physical machines on the same LAN keep DF, receive `need to frag` directly,
clamp, and work — which is why the same Ubuntu 26.04 install is fine on
hardware and broken behind the NAT. Ubuntu 26.04 made this visible because
post-quantum ML-KEM keyshares inflate every TLS ClientHello to ~1565 bytes;
older distros rarely send near-MSS packets in interactive use.

There is no API to change vmnet's behavior (no MTU control, no MSS
clamping, DF stripping hardwired). The structural fix is to remove the NAT
from the path: **bridged mode**, where the VM is a first-class machine on
the LAN — exactly like the user's working hardware installs.

## Constraints

- NAT stays the default (works on captive-portal / 802.1X networks where
  bridging fails; keeps VMs off the LAN when that's wanted)
- Mode is per-VM, recorded in config.json; changeable by editing the file
- Requires the `com.apple.vm.networking` entitlement (free, ad-hoc
  signable) in addition to `com.apple.security.virtualization`

## Approach

- `virt create <name> --network bridge [--bridge-interface en1]`
  - Default interface = the system's primary interface (from
    SystemConfiguration's global IPv4 state); `--bridge-interface` overrides
  - `networkMode` + optional `bridgeInterface` persisted in config.json;
    absent = legacy NAT behavior
- `VZBridgedNetworkDeviceAttachment` when mode is `bridge`, otherwise the
  existing NAT attachment; stable MAC logic unchanged (also gives stable
  DHCP leases from the router)
- `virt start` banner shows the network mode; `virt doctor` reports both
  entitlements
- Guest-side MTU clamp remains documented as the NAT-mode workaround

## Domain Events

| Event | What follows |
|---|---|
| VM Created (bridge) | config.json records mode + interface |
| VM Started (bridge) | Guest DHCPs directly from the LAN router; gets a LAN IP |
| Guest sends full-size packets | DF preserved; PMTUD ICMPs arrive un-NAT'd; TCP clamps and recovers |

## Checkpoints

1. ✅ `swift build` + `swift test` pass
2. ✅ `--network bridge` persisted in config.json; attachment built when entitled
3. ✅ Bridge mode without the entitlement → clear error, exit non-zero (no SIGKILL)
4. ✅ NAT mode unchanged (default path regression-tested)
5. ⏸ Bridged guest DHCP proof — blocked pending paid Developer ID signing

## Lessons learned

- `com.apple.security.virtualization` works with ad-hoc signing;
  `com.apple.vm.networking` does NOT. amfid kills the process at exec
  (SIGKILL, no output) and logs "Unable to retrieve certificate chain" /
  "adhoc signed app with restricted entitlements".
- Free "Personal Team" development certificates do not cover restricted
  entitlements (same reason UTM's build docs have free-account users strip
  com.apple.vm.networking). Bridge mode effectively requires the paid
  Apple Developer Program.
- The restricted-entitlement SIGKILL happens at process exec — before
  main() — so it must be prevented at build time (entitlements file) or
  gated at runtime with a codesign self-check (Entitlements.has), which is
  what makeNetworkAttachment does.
