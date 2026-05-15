# SPM CI Pipeline — Design

**Status:** Approved (pending written review)
**Scope:** GitHub Actions CI for the NATS chat client Swift package.
**Out of scope:** project initialization (handled by a separate job), release automation, code coverage upload, DocC build, pre-commit hooks, branch-protection configuration.

References:
- Project design: `docs/superpowers/specs/2026-05-15-nats-chat-client-design.md`
- Apple swift-format: `github.com/apple/swift-format` (bundled with Xcode 16)

**Revision history:**
- 2026-05-15 — initial design used Nick Lockwood's `SwiftFormat` with Airbnb's vendored config. Reverted to Apple's `swift-format` after first CI run because Airbnb's config tracks SwiftFormat's `main` branch and uses options (`--type-blank-lines consistent`) not present in any released SwiftFormat. Apple's `swift-format` is bundled with Xcode, so version drift is governed by `XCODE_VERSION`.

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
        │ swift-format  │               │ xcodebuild test      │
        │ lint --strict │               │   (library on sim)   │
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

    - name: Select Xcode
      run: sudo xcode-select -s /Applications/Xcode_${{ env.XCODE_VERSION }}.app

    - name: Lint with swift-format
      shell: bash
      run: |
        paths=()
        [ -d Sources ] && paths+=(Sources)
        [ -d Tests ] && paths+=(Tests)
        if [ ${#paths[@]} -eq 0 ]; then
          echo "::notice::No Swift sources to lint yet (Sources/Tests not present)."
          exit 0
        fi
        xcrun swift-format lint --strict --recursive "${paths[@]}"
```

Choices:
- **Tool:** Apple's [`swift-format`](https://github.com/apple/swift-format), bundled with Xcode. No `brew install` step — version is governed by `XCODE_VERSION`.
- **`xcrun swift-format`** rather than bare `swift-format` so the binary resolved is from the selected Xcode toolchain, even if PATH ordering changes on the runner.
- **`lint --strict --recursive Sources Tests`** — `--strict` promotes lint diagnostics to errors (non-zero exit). Restricting to `Sources Tests` avoids walking docs, scripts, and vendored dependencies under `.build`.
- **Empty-tree guard.** Before project init lands, `Sources/` and `Tests/` don't exist; rather than failing on missing paths, the step emits a GitHub Actions notice and exits 0. Once project init merges, both directories appear and lint runs for real.
- **Rules in `.swift-format`.** Config lives at the repo root in JSON form, auto-discovered by `swift-format`. See §6.

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

## 6. `.swift-format` config

JSON file at the repo root. Apple's `swift-format` auto-discovers `.swift-format` in the current directory or any ancestor.

```json
{
  "version": 1,
  "lineLength": 120,
  "indentation": { "spaces": 4 },
  "tabWidth": 4,
  "respectsExistingLineBreaks": true,
  "lineBreakBeforeControlFlowKeywords": false,
  "lineBreakBeforeEachArgument": true,
  "indentConditionalCompilationBlocks": false,
  "rules": {
    "AllPublicDeclarationsHaveDocumentation": false,
    "AlwaysUseLowerCamelCase": true,
    "AmbiguousTrailingClosureOverload": true,
    "NoLeadingUnderscores": false,
    "OrderedImports": true,
    "UseLetInEveryBoundCaseVariable": true,
    "UseShorthandTypeNames": true,
    "UseSingleLinePropertyGetter": true,
    "UseSynthesizedInitializer": true,
    "UseTripleSlashForDocumentationComments": true,
    "ValidateDocumentationComments": false
  }
}
```

Rationale for the deltas from default:
- **`lineLength: 120`** — defaults to 100; 120 reduces noisy wraps on Swift's verbose generics.
- **`AllPublicDeclarationsHaveDocumentation: false`** and **`ValidateDocumentationComments: false`** — DocC validation is a separate hardening pass, not v1 scope.
- **`OrderedImports: true`** — small, mechanical, prevents merge-conflict noise.
- Everything else stays at Apple's recommended defaults.

This is a v1 config — intentionally small. Tighten over time once the codebase exists.

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
- **Local parity.** Developers running `xcrun swift-format lint --strict --recursive Sources Tests` locally with the same Xcode version see the same result as CI. No pre-commit hook is added in this spec.

## 9. Files added to the repo

| Path | Purpose |
|---|---|
| `.github/workflows/ci.yml` | The two-job workflow (Sections 3-5) |
| `.swift-format` | swift-format JSON config (Section 6) |
