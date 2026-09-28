# virt

A CLI tool for managing Linux VMs on macOS using Apple's Virtualization.framework.

Sibling tool for Linux hosts: **[virt-linux](https://git.navicore.tech/navicore/virt-linux)**
([GitHub mirror](https://github.com/navicore/virt-linux)) — the Rust/QEMU twin of this
tool. Same command surface, same `~/.virt/vms/` on-disk layout, so disks, kernels, and
configs move between the two with plain copies.

## Source and mirrors

The home of this project is my Forgejo:
**[git.navicore.tech/navicore/virt-macos](https://git.navicore.tech/navicore/virt-macos)** —
the canonical source of truth for code and releases. It is mirrored to
**[github.com/navicore/virt-macos](https://github.com/navicore/virt-macos)**; issues,
pull requests, and forks are welcome on the GitHub mirror.

## Requirements

- macOS 13+ on Apple Silicon
- ARM64 Linux ISOs only (aarch64; no x86 emulation). `virt install` checks
  the ISO and rejects x86 images up front instead of showing a black window.

## Build

```
just dev
```

This runs `swift build` and signs the binary with the required virtualization
entitlement. `just build` makes a release build.

Requires [just](https://just.systems) (`brew install just`). Run `just ci`
before pushing — it checks formatting (`swift format`), lints
(`swiftlint --strict`), runs the tests, and builds release.

## Install

```
just build
just install
```

Installs to `/usr/local/bin`; customize with `PREFIX=~/.local`. Add `sudo` to
the install step only if the target isn't user-writable (on stock Apple
Silicon Macs `/usr/local` is root-owned; if Homebrew's old Intel layout
chowned `/usr/local/bin` to you, no sudo is needed). Building and installing
are separate steps on purpose: `sudo just install` never compiles, so no
root-owned files are left in `.build/`.

## Releases

`virt --version` reports the version. Pushing a `vX.Y.Z` tag triggers
`.forgejo/workflows/release.yml`: it stamps the tag into
`Sources/virt/Version.swift`, commits the bump to `main`, builds and
signs the release binary, and publishes it to the
[releases page](https://git.navicore.tech/navicore/virt-macos/releases).
(Requires the repo secret `PAT` — a token with `write:repository`.)

### Install from a release

Download `virt-X.Y.Z-aarch64-apple-darwin.tar.gz` (and its `.sha256`)
from the releases page, then:

```
shasum -a 256 -c virt-X.Y.Z-aarch64-apple-darwin.tar.gz.sha256
tar xzf virt-X.Y.Z-aarch64-apple-darwin.tar.gz
xattr -d com.apple.quarantine virt   # browser downloads only; curl is unaffected
install -m 0755 virt /usr/local/bin/virt
```

The binary ships ad-hoc signed with the virtualization entitlement — no
re-signing needed. (Bridge networking still requires a paid Developer
account; see [Networking](#networking).)

## Shell completions

```
source <(virt completions zsh)
```

Add that line to your `.zshrc` for persistent tab completion. Bash and fish are also supported:

```
source <(virt completions bash)
virt completions fish | source
```

## Usage

### Create a VM

```
virt create milford --description "medium size vm with rocky 10 os" --disk 100 --cpus 4 --memory 8192
```

`--description` is required, as are `--memory` (MB) and `--disk` (GB) —
`--cpus` defaults to 2. Tab completion offers sensible values for memory
(1024/2048/4096/8192) and disk (10/20/50); any value is accepted.
Update a description later with `virt set milford --description "..."`.

### Install an OS from ISO

Opens a GUI window with the VM's display for OS installation:

```
virt install myvm --iso ~/Downloads/debian-13-arm64-netinst.iso
```

During the Debian installer:
- Skip the network mirror step if DNS isn't working (see Troubleshooting)
- Let GRUB install to the EFI system partition

(If you plan to use direct kernel boot, the GRUB `console=hvc0` step below
is unnecessary — the kernel command line is set by the host.)

After install, boot the VM once more with the GUI:

```
virt install myvm
```

**Ubuntu 26.04+ and other current distros enable the hvc0 console
automatically** — skip straight to `virt start`. On older distros (or if
`virt start` shows no login prompt), log in as root and add `console=hvc0`
to every `linux` line in `/boot/grub/grub.cfg`:

```
nano /boot/grub/grub.cfg
```

Then shut down:

```
systemctl poweroff
```

### Start headless

```
virt start myvm
```

EFI boots silently (~5s), then the Linux console appears in your terminal.
Use `virt stop myvm` from another terminal to shut down.

### Direct kernel boot (recommended)

Skip EFI/GRUB entirely for daily use: boot the guest kernel directly.
Console output starts in ~1s and no GRUB configuration is needed.

Copy the kernel out of the guest during a GUI session (Debian/Ubuntu
provide stable `/vmlinuz` and `/initrd.img` symlinks):

```
virt install myvm --share ~/vm-share
# inside the guest:
mkdir -p /mnt/share
mount -t virtiofs share /mnt/share
cp -L /vmlinuz /initrd.img /mnt/share/
```

Then on the host:

```
virt kernel-import myvm --from ~/vm-share
```

`virt start` detects the kernel and boots it directly. Compressed kernels
(gzip/zboot — most distro kernels) are decompressed automatically at
import. If your root filesystem is not on `/dev/vda2`, pass `--root`
(check with `lsblk` in the guest).

After a kernel upgrade in the guest, repeat the copy + import.

### Shared folders

Share a host directory with the VM:

```
virt start myvm --share ~/code
virt install myvm --share ~/code
```

Inside the VM, mount it:

```
mkdir -p /mnt/share
mount -t virtiofs share /mnt/share
```

For persistent mounting, add to `/etc/fstab`:

```
share /mnt/share virtiofs defaults 0 0
```

### Clipboard (copy/paste)

Clipboard sharing between macOS and the Linux guest works in GUI mode
(`virt install`). Install the SPICE agent inside the VM:

```
apt install spice-vdagent
systemctl enable spice-vdagentd
```

Copy/paste works after the next boot.

### Clone a VM (templates)

Keep a fully configured VM stopped — GUI installed, kernel imported —
and clone it for each new instance:

```
virt clone testrocky-i k3s-node1
virt clone testrocky-i k3s-node2
```

A clone copies the disk, the EFI variable store, imported kernel files,
and the config under a new name with a **fresh MAC** — everything else
(hardware, network mode) passes through unchanged. On APFS the disk copy
is a `clonefile`: instant even for a 100 GB template, and the blocks are
shared copy-on-write, so a clone costs no extra space until either VM
writes. Clones are independent full images — writing in a clone never
touches the template. `--description` overrides the default
`clone of <source>`.

**Guest identity is copied too.** There is no `virt-sysprep` on macOS, so
each clone starts with the template's machine-id and SSH host keys. For
clusters (k3s keys nodes off machine-id), reset them inside the clone on
first boot:

```
sudo rm -f /etc/machine-id /var/lib/dbus/machine-id
sudo systemd-machine-id-setup
sudo rm /etc/ssh/ssh_host_*
sudo dpkg-reconfigure openssh-server   # Debian/Ubuntu; Rocky/Fedora: systemctl restart sshd
sudo hostnamectl set-hostname <new-name>
```

### Headless console tips

The serial console passes ANSI escape codes transparently. ncurses apps
(vim, htop, tmux) work if `TERM` is set correctly:

```
export TERM=xterm-256color
```

The console defaults to 80x24. After resizing your terminal window, update
the guest:

```
stty rows 50 cols 120
```

For heavy interactive work (tmux sessions, development), SSH into the VM
over NAT is recommended:

```
apt install openssh-server
# then from macOS:
ssh user@192.168.64.x
```

### Other commands

```
virt list              # show all VMs, status, network, and description
virt set myvm --description "new purpose"
virt clone myvm node2  # clone a stopped VM under a new name (fresh MAC)
virt stop myvm         # graceful shutdown, then force kill
virt delete myvm       # remove VM (prompts for confirmation)
virt delete myvm --force
virt doctor            # diagnose host setup (entitlement, disk, DNS, VMs)
```

## Networking

Each VM gets a stable MAC address at create time, so its NAT IP is usually
stable across reboots — SSH config and `known_hosts` entries keep working.

`virt create --network bridge` puts the VM directly on your LAN (own IP
from your router) instead of behind Apple's NAT. **Requires virt to be
signed with a paid Developer account** — `com.apple.vm.networking` is a
restricted entitlement, and ad-hoc signed binaries are killed at launch.
Bridge mode fixes the NAT MTU problem below structurally.

### NAT mode: TLS works to some sites, stalls on others

Symptom: apt and SSH work, but Firefox/HTTPS stalls on some sites
("Performing TLS handshake" forever) while others load fine.

Cause (fully packet-captured, see docs/design/006): Apple's NAT strips the
DF bit from guest packets. Any hop with an MTU below 1500 between the
guest and the internet then fragments the packet instead of cleanly
rejecting it; fragments are lost, and the guest can never learn the path
MTU. Post-quantum TLS (ML-KEM, default in 2026-era distros) makes every
ClientHello big enough to trigger this. Note the low-MTU hop can be the
**host itself**: check `networksetup -getMTU en0` — a manually clamped
host interface (e.g. 1472, a leftover PPPoE tweak) fragments every
guest full-MSS packet right at the Mac. Sites that load fine are typically
served over QUIC/HTTP3, which probes path MTU instead of trusting DF.

Fix in the guest (NAT mode): lower the interface MTU.

```
# immediate, temporary:
sudo ip link set dev enp0s1 mtu 1400

# persistent (Ubuntu desktop / NetworkManager):
nmcli con show            # find the connection name
sudo nmcli con mod "Wired connection 1" 802-3-ethernet.mtu 1400
sudo nmcli con up "Wired connection 1"
```

## Debugging

Every VM logs lifecycle events (start, stop, failures, shutdown requests)
to `~/.virt/vms/<name>/vm.log`. If a boot misbehaves, look there first.

If the guest never shuts down and `virt stop` has to force-kill it, stop
also repairs the terminal the console was attached to (raw mode would
otherwise leave it without echo).

## Troubleshooting

### VM DNS not working

VM DNS relies on macOS's `mDNSResponder` listening on port 53. If another
process has grabbed that port, DNS silently breaks for all VMs.

Check what's on port 53:

```
sudo lsof -i :53 -n -P
```

You should see `mDNSResponder`. If you see something else (`dnsmasq`, `docker`,
`cloudflared`, etc.), stop it:

```
# Example for dnsmasq via Homebrew:
sudo brew services stop dnsmasq

# Then restart mDNSResponder:
sudo killall mDNSResponder
```

Known culprits: dnsmasq, Docker Desktop, Cloudflare WARP, Tailscale MagicDNS,
AdGuard Home, Pi-hole.

### No console output from `virt start`

With EFI boot, the guest kernel must be configured to use `console=hvc0`.
The recommended fix is direct kernel boot (`virt kernel-import`), which
sets the console from the host. Alternatively, boot the GUI
(`virt install myvm` without `--iso`), log in, and add `console=hvc0` to
every `linux` line in `/boot/grub/grub.cfg`.

### Ctrl-C doesn't work in headless mode

Stdin is wired directly to the VM, so Ctrl-C is sent to the guest. Use
`virt stop myvm` from another terminal to shut down.

### DHCP overwrites /etc/resolv.conf

If you manually set `nameserver 1.1.1.1` in `/etc/resolv.conf`, DHCP will
overwrite it on lease renewal. For a permanent override, add this to
`/etc/dhcp/dhclient.conf` inside the VM:

```
supersede domain-name-servers 1.1.1.1;
```

This is only needed if mDNSResponder cannot be restored as the DNS handler
on the host (see "VM DNS not working" above).
