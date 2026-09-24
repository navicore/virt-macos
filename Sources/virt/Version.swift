// Single source of truth for the virt version.
//
// Rewritten by the release workflow from the pushed vX.Y.Z tag
// (.forgejo/workflows/release.yml) — do not hand-edit.

/// Semantic version (`X.Y.Z`), reported by `virt --version`.
enum VirtVersion {
  static let current = "0.1.0"
}
