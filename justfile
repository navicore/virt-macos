# virt — manage Linux VMs on macOS via Virtualization.framework

prefix := env_var_or_default("PREFIX", "/usr/local")

# Debug build + codesign (day-to-day dev)
dev:
    swift build
    codesign --entitlements virt.entitlements --force -s - .build/debug/virt

# Release build + codesign
build:
    swift build -c release
    codesign --entitlements virt.entitlements --force -s - .build/release/virt

# CLT-only machines (the CI mini) ship swift-testing's macro plugin but the
# Swift Build backend never passes it to the compiler when Testing comes
# from the CLT layout — full Xcode adds it automatically. Load it explicitly
# ONLY when Xcode is absent and the CLT plugin exists, so Xcode machines are
# untouched (mixing the CLT plugin with Xcode's Testing module would be a
# version-mismatch hazard).
test-plugin-flag := if shell("test ! -d /Applications/Xcode.app -a -f /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib && echo yes || echo no") == "yes" {
  '-Xswiftc -load-resolved-plugin -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib\#\#TestingMacros'
} else {
  ""
}

# Run unit tests
test:
    swift test {{test-plugin-flag}}

# Format all sources in place
fmt:
    swift format --in-place --recursive Sources Tests Package.swift

# Check formatting without modifying
fmt-check:
    swift format lint --recursive --strict Sources Tests Package.swift

# Lint (warnings are errors)
lint:
    swiftlint lint --strict

# Install signed release binary to PREFIX/bin.
# Deliberately does NOT depend on `build` so `sudo just install` never
# compiles as root (which would leave root-owned files in .build/).
# Run `just build` first, like the classic `make; sudo make install` split.
install:
    @test -f .build/release/virt || { echo "error: .build/release/virt missing — run 'just build' first" >&2; exit 1; }
    install -d {{prefix}}/bin
    install .build/release/virt {{prefix}}/bin/virt
    codesign --entitlements virt.entitlements --force -s - {{prefix}}/bin/virt

# Remove installed binary
uninstall:
    rm -f {{prefix}}/bin/virt

# Package the signed release binary into dist/ (used by release.yml).
# Deliberately does NOT depend on `build` — run `just build` first
# (same split as install).
dist VERSION:
    @install -d dist
    tar czf dist/virt-{{VERSION}}-aarch64-apple-darwin.tar.gz -C .build/release virt
    shasum -a 256 dist/virt-{{VERSION}}-aarch64-apple-darwin.tar.gz > dist/virt-{{VERSION}}-aarch64-apple-darwin.tar.gz.sha256

# Remove build artifacts
clean:
    swift package clean

# Quick code stats (requires scc)
stats:
    @echo "=== LOC ==="
    @scc Sources Tests --no-cocomo
    @echo ""
    @echo "=== Largest Swift source files (top 15) ==="
    @scc Sources Tests --by-file --no-cocomo -s lines -i swift | head -15

# Run all CI checks — this is what developers should run before pushing
ci: fmt-check lint test build
    @echo "Safe to push - CI will pass."
