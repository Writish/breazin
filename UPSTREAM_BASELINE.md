# Upstream baseline

## Pinned source

| Field | Value |
| --- | --- |
| Upstream | `https://github.com/palmier-io/palmier-pro.git` |
| Release | `v0.6.13` |
| Commit | `4ad06353ffaae0ea6e2cfc515e8f8920daa10d57` |
| Local annotated tag | `breazin-base/palmier-v0.6.13` |
| Audit date | 2026-07-21 |
| License | GPL-3.0; `LICENSE` SHA-256 `3972dc9744f6499f0f9b2dbf76696f2ae7ad8af9b23dde66d6af86c9dfb36986` |
| Upstream main observed | `2eec1ef27a5f13c5dbf7630a72140bc4ea1598e7` |

The release tag, pinned commit, and local annotated tag were independently resolved and matched before product changes began. `origin` is `Writish/breazin`; `upstream` remains the original project. Upstream is fetched for review only and is never merged automatically.

## Pristine baseline verification

Host: Apple Silicon macOS 26.5.1, Xcode 26.6 (17F113), Swift 6.3.3.

| Check | Result |
| --- | --- |
| `swift build` | Passed |
| `swift test` | Failed with 38 issues across 1,141 tests / 173 suites |
| Source-caused compile failures | None |
| Warnings | Existing MCP redundant `await`, HDR captured mutable state, and Convex static objects built for macOS 26.2 while linking for 26.0 |

The 38 test issues were all Metal/Core Image rendering assertions (HueCurves, Grain, Highlights/Shadows, ChromaKey, Vignette, Clarity, LUT, Levels, model/effect rendering, and compositor render cases). They reproduced before any Breazin change and are therefore tracked as an environment-sensitive upstream baseline rather than introduced regressions.

The investigation found two independent causes: Xcode's optional Metal Toolchain was not installed, and the upstream SwiftPM build plugin could silently discover zero kernel inputs (and percent-encode non-ASCII workspace paths). The Breazin plugin now uses an explicit kernel manifest, decoded filesystem paths, and the stable `Metal` toolchain alias. After installing Metal Toolchain build `17F109`, the complete renamed suite passed: **1,148 tests in 175 suites, 0 failures**.

`swift run` and the pristine upstream bundle were not used as automated gates because they open a GUI session. The renamed source and assembled Breazin application are validated separately by the repository build and bundle smoke checks.

## Deliberately retained upstream references

- GPL copyright and source provenance.
- `.palmier` and `io.palmier.project` read compatibility for existing user projects.
- The checksummed SigLIP model download host until identical artifacts are mirrored under a Breazin-controlled channel.
- Archived upstream marketing documentation under `docs/upstream/`; it is not current product documentation.

Any additional Palmier-branded runtime endpoint is a regression and must fail `scripts/ci/verify-branding.sh`.
