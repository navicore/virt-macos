# Design: required resources and VM descriptions

**Date**: 2026-09-24
**Status**: Implemented — decisions: memory ladder 1024/2048/4096/8192,
disk ladder 10/20/50 (suggestions only); `virt set` included; description
column truncated at 40 chars, `—` for legacy nils. Completions delivered
via `CompletionKind.custom` closure literals (the `@Completion` attribute
does not exist in argument-parser 1.3; the generated scripts call back
through the hidden `---completion` flag). Verified end to end.

## Intent

1. `virt create` requires explicit `--memory` and `--disk`, with sensible
   values offered by shell tab completion.
2. `virt create` requires a `--description`, decoupling the VM *name*
   (any criteria — "milford") from what it *is* ("medium size vm with
   rocky 10 os"). `virt list` shows a DESCRIPTION column.

Breaking change to `virt create` → release as **v0.2.0** (first tag to
exercise the release workflow's version-bump loop).

## A. Required memory + disk with completion values

### Create.swift

```swift
@Option(help: "Memory in MB", completion: .custom(memorySizes))
var memory: Int          // was: Int = 2048 — now required

@Option(help: "Disk size in GB", completion: .custom(diskSizes))
var disk: Int            // was: Int = 10 — now required
```

Completion candidates via ArgumentParser `@Completion` statics (supported
since 1.3.0, already our floor):

```swift
@Completion static func memorySizes(_ word: String) -> [String] {
  Self.filtered(word, values: [2048, 4096, 6144, 8192, 12288, 16384, 24576, 32768])
}
@Completion static func diskSizes(_ word: String) -> [String] {
  Self.filtered(word, values: [8, 16, 32, 64, 100, 128, 256])
}
```

Mechanics: the generated scripts (existing `virt completions zsh` etc.)
already query the binary's hidden `---complete` handler; `.custom`
candidates flow through with **no changes to Completions.swift**.
Completions are suggestions, not validation — any positive value remains
accepted. Existing `validate()` floors (memory ≥ 512, disk ≥ 1) stay.

Open: final value ladders (proposed above are 2–32 GB / 8–256 GB steps).
Optional same-treatment: `--cpus` (not requested).

### Docs

- README `virt create` example already passes `--disk 16 --cpus 2
  --memory 4096` — still valid; add a note that both are now required.

## B. Mandatory description

### VMConfig.swift

```swift
/// Human description of the VM's purpose. Optional in storage for
/// backward compatibility (nil = config predates descriptions);
/// required at `virt create`.
let description: String?
```

Synthesized Codable decodes optionals with `decodeIfPresent` — the exact
pattern `macAddress` uses (see `testLegacyConfigWithoutMACDecodes`), so
existing `config.json` files load unchanged with `description == nil`.
`withMAC` / `withKernelBoot` forward it; add `withDescription(_:)` if the
edit command below is adopted.

### Create.swift

`@Option(help: "Short description of the VM's purpose") var description: String`
— non-optional → required by ArgumentParser. Echoed in the post-create
summary block.

### List.swift

- Column order: `NAME CPUS MEMORY DISK STATUS DESCRIPTION` — description
  last (no padding concerns for the widest cell).
- Truncate at 40 chars with `…` to keep the table readable; `—` for
  legacy nil descriptions, `-` in the corrupt-config row as today.
- `rightAlign` gains a trailing `false`.

### Optional companion (open): `virt set <name> --description "..."`

Without it, a typo'd description is permanent (delete/recreate to fix).
A small `set` command re-writing config via `withDescription` is ~40
lines. Not requested — include or defer?

## Tests (VMConfigTests)

- `descriptionRoundTrip` — write/load with description.
- `legacyConfigWithoutDescriptionDecodes` — pre-description JSON decodes,
  `description == nil` (mirrors the MAC test).
- Command-level behavior (required-arg errors, list column) — no
  command-test harness exists today; cover by manual steps in the PR
  description rather than new harness.

## Migration

- Old `create` invocations missing `--memory`/`--disk`/`--description`
  now fail with ArgumentParser's clear "Missing expected argument" error.
  Acceptable at 0.1.0 → 0.2.0 for a personal tool.
- Existing VMs: load fine; list shows `—` until recreated (or `virt set`
  backfills them, if adopted).

## README

- Update create examples (`--description`), list sample output with the
  new column, mention required parameters.

## Sequencing

Single PR, two commits (A then B), tagged `v0.2.0` — the first release
demonstrating the tag → Version.swift bump-commit → signed artifact loop.

## Open questions

- Final value ladders for memory/disk completions.
- `virt set` description editor: include now or defer?
- Truncation width (40 proposed) and `—` vs empty for legacy nils.
