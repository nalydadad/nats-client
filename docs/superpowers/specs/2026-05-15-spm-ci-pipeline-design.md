# SPM CI Pipeline — Design

**Status:** Approved (pending written review)
**Scope:** GitHub Actions CI for the NATS chat client Swift package.
**Out of scope:** project initialization (handled by a separate job), release automation, code coverage upload, DocC build, pre-commit hooks, branch-protection configuration.

References:
- Project design: `docs/superpowers/specs/2026-05-15-nats-chat-client-design.md`
- Airbnb SwiftFormat config: `github.com/airbnb/swift/blob/master/Sources/AirbnbSwiftFormatTool/airbnb.swiftformat`

---

## 1. Goals

1. Block PRs and post-merge commits on a formatting violation or a failing iOS test/build.
2. Validate the library and the SwiftUI demo target both compile and run on iOS Simulator, since the package targets iOS only.
3. Keep PR feedback under five minutes on a warm cache.
4. Pin a single Xcode version so CI is deterministic; bump deliberately.

## 2. Architecture

Single workflow file at `.github/workflows/ci.yml`. Two jobs run in parallel on `macos-15`:

```
            on: pull_request, push to main, workflow_dispatch
                                  │
                ┌─────────────────┴─────────────────┐
                ▼                                   ▼
        ┌───────────────┐               ┌──────────────────────┐
        │ format        │               │ ios                  │
        │ swiftformat   │               │ xcodebuild test      │
        │ --lint        │               │   (library on sim)   │
        │ (~1 min)      │               │ xcodebuild build     │
        │               │               │   (demo on sim)      │
        │               │               │ (~3-5 min, 1 boot)   │
        └───────────────┘               └──────────────────────┘
```

- **Runner:** `macos-15`.
- **Xcode:** `16.2` (pinned; one env var).
- **Wall-clock PR feedback:** ≈ slowest job, 3-4 min warm / 4-5 min cold.
- **Required status checks:** `format`, `ios` (configured manually in branch protection — out of scope here).

## 3. Triggers and workflow shape

```yaml
name: CI

on:
  pull_request:
  push:
    branches: [main]
  workflow_dispatch:

concurrency:
  group: ci-${{ github.ref }}
  cancel-in-progress: true

env:
  XCODE_VERSION: "16.2"
  LIBRARY_SCHEME: "ChatClient"
  DEMO_SCHEME: "ChatClientDemo"
  IOS_DESTINATION: "platform=iOS Simulator,name=iPhone 16,OS=latest"

jobs:
  format: { runs-on: macos-15, steps: [...] }
  ios:    { runs-on: macos-15, steps: [...] }
```

Choices:
- **Concurrency** keyed on `github.ref` with `cancel-in-progress: true` so a new push to a PR cancels the stale run.
- **Single top-level `env` block** holds Xcode version, scheme names, and the iOS destination. Renaming a scheme or bumping Xcode is one line.
- **No matrix.** Single pinned Xcode + single iOS destination.
- **No `permissions:` block.** Neither job writes to the repo or posts comments; the default read-only token is sufficient.

## 4. Job: `format`

```yaml
format:
  runs-on: macos-15
  steps:
    - uses: actions/checkout@v4

    - name: Install SwiftFormat
      run: brew install swiftformat

    - name: Lint with SwiftFormat
      run: swiftformat --lint .
```

Choices:
- **Tool:** Nick Lockwood's [`SwiftFormat`](https://github.com/nicklockwood/SwiftFormat), not Apple's `swift-format`. The two are not interchangeable — different binaries, different config formats, different rule names.
- **`brew install swiftformat`** rather than relying on the preinstalled runner version. The Airbnb config targets `--swift-version 6.3` and uses recent rules (`redundantEquatable`, `swiftTestingTestCaseNames`, `redundantMemberwiseInit`); the preinstalled binary can lag a release. Cold install ≈ 30 s on `macos-15`.
- **`--lint`** runs in check mode — no files modified; exits non-zero on any deviation. This is the gate.
- **Path `.`** — the vendored config excludes `Carthage,Pods,.build`, so repo-wide scanning is correct. No need to enumerate `Sources Tests`.
- **No Xcode selection step.** SwiftFormat is a standalone Swift CLI; it does not need Xcode selected.

## 5. Job: `ios`

```yaml
ios:
  runs-on: macos-15
  steps:
    - uses: actions/checkout@v4

    - name: Select Xcode
      run: sudo xcode-select -s /Applications/Xcode_${{ env.XCODE_VERSION }}.app

    - name: Cache SwiftPM dependencies
      uses: actions/cache@v4
      with:
        path: |
          .build
          ~/Library/Caches/org.swift.swiftpm
          ~/Library/Developer/Xcode/DerivedData/**/SourcePackages
        key: spm-${{ runner.os }}-xcode${{ env.XCODE_VERSION }}-${{ hashFiles('**/Package.resolved') }}
        restore-keys: |
          spm-${{ runner.os }}-xcode${{ env.XCODE_VERSION }}-

    - name: Resolve packages
      run: xcodebuild -resolvePackageDependencies -scheme ${{ env.LIBRARY_SCHEME }}

    - name: Test library on iOS Simulator
      run: |
        set -o pipefail
        xcodebuild test \
          -scheme "$LIBRARY_SCHEME" \
          -destination "$IOS_DESTINATION" \
          -resultBundlePath TestResults-library.xcresult \
          | xcbeautify --renderer github-actions

    - name: Build demo on iOS Simulator
      run: |
        set -o pipefail
        xcodebuild build \
          -scheme "$DEMO_SCHEME" \
          -destination "$IOS_DESTINATION" \
          | xcbeautify --renderer github-actions

    - name: Upload test results on failure
      if: failure()
      uses: actions/upload-artifact@v4
      with:
        name: TestResults-library.xcresult
        path: TestResults-library.xcresult
```

Choices:
- **`actions/cache`** keyed on `Package.resolved` hash. Cold: ~5-6 min; warm: ~2-3 min.
- **Explicit `xcodebuild -resolvePackageDependencies`** before test/build so resolution errors surface as a distinct step.
- **`xcbeautify` with `--renderer github-actions`** surfaces test failures as inline PR annotations. Preinstalled on `macos-15`; no install step needed.
- **`set -o pipefail`** prevents `xcodebuild` failures from being swallowed by `xcbeautify` exiting 0.
- **`-resultBundlePath` plus conditional artifact upload.** Successful runs skip the upload; failures upload the `.xcresult` for local inspection.
- **One simulator destination** for both library tests and demo build, so the sim boots once.
- **Demo build is the last step** — if the library tests fail, demo build is skipped.
- **`xcodebuild build` (not `test`) for the demo.** It's an app target with no test bundle; we only verify it compiles and links.

## 6. `.swiftformat` config

Vendored verbatim from `airbnb/swift@master` (`Sources/AirbnbSwiftFormatTool/airbnb.swiftformat`) at the repo root. We do not fetch live — bumps are deliberate, performed by re-vendoring the upstream file and reviewing the diff.

Notable settings inherited from Airbnb:
- **2-space indent, 130-char max width.**
- **`--swift-version 6.3`, `--language-mode 5`** — matches Xcode 16.2's Swift compiler. If we ever downgrade Xcode, this value must come down too.
- **Test-target rules** (`noForceTryInTests`, `noForceUnwrapInTests`, `noGuardInTests`, `testSuiteAccessControl`) — SwiftFormat scopes them automatically by detecting test files.
- **Opt-in rule list** — only rules listed under `--rules ...` execute; anything not listed is off.

Excerpt of the first ~25 lines (full file is ~150 lines and lives at `.swiftformat`):

```
# Exclude checkout directories for common package managers
--exclude Carthage,Pods,.build

--swift-version 6.3
--language-mode 5
--self remove
--import-grouping testable-bottom
--trailing-commas multi-element-lists
--trim-whitespace always
--indent 2
--ifdef no-indent
--indent-strings true
--wrap-arguments before-first
--wrap-parameters before-first
--wrap-collections before-first
...
```

## 7. Project-side assumptions

The project-initialization job is responsible for the package itself, but this CI design assumes:

1. **`Package.swift`** declares **iOS only** in `platforms`. If macOS support is added later, a separate macOS job should be added to this workflow.
2. **Library scheme name:** `ChatClient` (matches `LIBRARY_SCHEME` env var).
3. **Demo scheme name:** `ChatClientDemo` (matches `DEMO_SCHEME` env var).
4. **The demo target** builds as an iOS app via `xcodebuild` against an iOS Simulator destination; it is not buildable via `swift build` because SPM cannot produce an `.app` bundle.
5. Schemes are checked in as shared schemes under `.swiftpm/xcode/xcshareddata/xcschemes/` (or via Xcode's "Shared" checkbox) so CI can reference them by name.

If any of these names change at init time, the workflow's env vars are the only thing that needs to be updated.

## 8. Operational notes

- **Runner image drift.** GitHub updates `macos-15` images on a rolling basis. Preinstalled tools (xcbeautify, brew formulae) can move. Xcode is pinned explicitly; the Swift toolchain pin is implicit (via Xcode).
- **Xcode path assumption.** `sudo xcode-select -s /Applications/Xcode_16.2.app` assumes that exact version is preinstalled. If GitHub removes 16.2 before we bump, the select step fails. Bump within ~6 months of GitHub adding a newer Xcode.
- **Cache invalidation.** The SwiftPM cache key includes `Package.resolved` hash and Xcode version. Before the first resolve, the hash is empty and the restore-keys fallback may pick up older entries — acceptable for v1.
- **Branch protection.** Configure `format` and `ios` as required status checks on `main` after the first successful CI run. Outside this workflow.
- **Local parity.** Developers running `swiftformat --lint .` locally against the same binary version see the same result as CI. No pre-commit hook is added in this spec.

## 9. Files added to the repo

| Path | Purpose |
|---|---|
| `.github/workflows/ci.yml` | The two-job workflow (Sections 3-5) |
| `.swiftformat` | Vendored Airbnb config (Section 6) |
