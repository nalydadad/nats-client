# SPM CI Pipeline Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Land a GitHub Actions CI pipeline that gates PRs on SwiftFormat lint (Airbnb config) and on iOS Simulator test/build of the library and demo target.

**Architecture:** Single `.github/workflows/ci.yml` with two parallel jobs on `macos-15`: `format` (SwiftFormat `--lint`) and `ios` (`xcodebuild test` for the library + `xcodebuild build` for the demo, sharing one simulator boot). One vendored `.swiftformat` config at the repo root. Xcode pinned to 16.2.

**Tech Stack:** GitHub Actions, SwiftFormat (Nick Lockwood), xcodebuild, xcbeautify, Swift Package Manager.

**Spec:** `docs/superpowers/specs/2026-05-15-spm-ci-pipeline-design.md`

**Known sequencing:** This plan only adds CI files. It does **not** create `Package.swift`, library/demo targets, or schemes — those land via a separate project-initialization job. Until that job merges, the `ios` job will fail because schemes `ChatClient` and `ChatClientDemo` don't exist. The `format` job will pass (nothing to lint). Do not attempt to "fix" the missing-scheme failure inside this plan; it resolves itself once project init lands.

**Files this plan creates:**

| Path | Responsibility |
|---|---|
| `.swiftformat` | Vendored Airbnb SwiftFormat config; defines what `swiftformat --lint` enforces |
| `.github/workflows/ci.yml` | Two-job GitHub Actions workflow |

---

## Task 1: Vendor `.swiftformat`

**Files:**
- Create: `.swiftformat`

- [ ] **Step 1: Write the file**

Create `.swiftformat` at the repository root with the following contents, copied verbatim from `github.com/airbnb/swift@master/Sources/AirbnbSwiftFormatTool/airbnb.swiftformat`:

```
# Exclude checkout directories for common package managers
--exclude Carthage,Pods,.build

# options
--swift-version 6.3
--language-mode 5
--self remove # redundantSelf
--import-grouping testable-bottom # sortedImports
--trailing-commas multi-element-lists # trailingCommas
--trim-whitespace always # trailingSpace
--indent 2 #indent
--ifdef no-indent #indent
--indent-strings true #indent
--wrap-arguments before-first # wrapArguments
--wrap-parameters before-first # wrapArguments
--wrap-collections before-first # wrapArguments
--wrap-conditions before-first # wrapArguments
--wrap-return-type never #wrapArguments
--wrap-effects never #wrapArguments
--closing-paren balanced # wrapArguments
--call-site-paren balanced # wrapArguments
--wrap-type-aliases before-first # wrapArguments
--allow-partial-wrapping false # wrapArguments
--func-attributes prev-line # wrapAttributes
--computed-var-attributes prev-line # wrapAttributes
--stored-var-attributes same-line # wrapAttributes
--complex-attributes prev-line # wrapAttributes
--type-attributes prev-line # wrapAttributes
--wrap-ternary before-operators # wrap
--wrap-string-interpolation preserve # wrap
--mark-struct-threshold 20 # organizeDeclarations
--mark-enum-threshold 20 # organizeDeclarations
--organize-types class,struct,enum,extension,actor,protocol # organizeDeclarations
--visibility-order beforeMarks,instanceLifecycle,open,public,package,internal,fileprivate,private # organizeDeclarations
--type-order nestedType,staticProperty,staticPropertyWithBody,classPropertyWithBody,swiftUIPropertyWrapper,instanceProperty,instancePropertyWithBody,staticMethod,classMethod,instanceMethod # organizeDeclarations
--sort-swiftui-properties first-appearance-sort #organizeDeclarations
--type-body-marks remove #organizeDeclarations
--extension-acl on-declarations # extensionAccessControl
--pattern-let inline # hoistPatternLet
--property-types inferred # redundantType, propertyTypes
--type-blank-lines consistent # blankLinesAtStartOfScope, blankLinesAtEndOfScope
--empty-braces spaced # emptyBraces
--ranges preserve # spaceAroundOperators
--operator-func no-space # spaceAroundOperators
--some-any disabled # opaqueGenericParameters
--else-position same-line # elseOnSameLine
--guard-else next-line # elseOnSameLine
--single-line-for-each convert # preferForLoop
--short-optionals always # typeSugar
--semicolons never # semicolons
--doc-comments preserve # docComments
--prefer-synthesized-init-for-internal-structs View,ViewBuilder # redundantMemberwiseInit

# Customized default modifier order to put `override` after access control
--modifier-order private,fileprivate,internal,package,public,open,private(set),fileprivate(set),internal(set),package(set),public(set),open(set),override,final,dynamic,optional,required,convenience,indirect,isolated,nonisolated,nonisolated(unsafe),lazy,weak,unowned,unowned(safe),unowned(unsafe),static,class,borrowing,consuming,mutating,nonmutating,prefix,infix,postfix,async # modifierOrder

# We recommend a max width of 100 but _strictly enforce_ a max width of 130
--max-width 130 # wrap

# rules
--rules anyObjectProtocol
--rules blankLinesBetweenScopes
--rules consecutiveSpaces
--rules consecutiveBlankLines
--rules duplicateImports
--rules extensionAccessControl
--rules environmentEntry
--rules hoistPatternLet
--rules indent
--rules markTypes
--rules organizeDeclarations
--rules redundantParens
--rules redundantReturn
--rules redundantSelf
--rules redundantType
--rules redundantPattern
--rules redundantGet
--rules redundantFileprivate
--rules redundantRawValues
--rules redundantEquatable
--rules sortImports
--rules sortDeclarations
--rules strongifiedSelf
--rules trailingCommas
--rules trailingSpace
--rules linebreakAtEndOfFile
--rules typeSugar
--rules wrap
--rules wrapMultilineStatementBraces
--rules wrapArguments
--rules wrapAttributes
--rules wrapEnumCases
--rules wrapSwitchCases
--rules singlePropertyPerLine
--rules braces
--rules redundantClosure
--rules redundantInit
--rules redundantVoidReturnType
--rules redundantOptionalBinding
--rules redundantInternal
--rules redundantPublic
--rules redundantVariable
--rules unusedArguments
--rules spaceInsideBrackets
--rules spaceInsideBraces
--rules spaceAroundBraces
--rules spaceInsideParens
--rules spaceAroundParens
--rules spaceAroundOperators
--rules enumNamespaces
--rules blockComments
--rules docComments
--rules docCommentsBeforeModifiers
--rules spaceAroundComments
--rules spaceInsideComments
--rules blankLinesAtStartOfScope
--rules blankLinesAtEndOfScope
--rules emptyBraces
--rules andOperator
--rules opaqueGenericParameters
--rules genericExtensions
--rules trailingClosures
--rules elseOnSameLine
--rules sortTypealiases
--rules preferForLoop
--rules conditionalAssignment
--rules wrapMultilineConditionalAssignment
--rules wrapFunctionBodies
--rules wrapPropertyBodies
--rules void
--rules blankLineAfterSwitchCase
--rules consistentSwitchCaseSpacing
--rules semicolons
--rules propertyTypes
--rules blankLinesBetweenChainedFunctions
--rules preferCountWhere
--rules swiftTestingTestCaseNames
--rules redundantSwiftTestingSuite
--rules modifiersOnSameLine
--rules noForceTryInTests
--rules noForceUnwrapInTests
--rules redundantThrows
--rules redundantAsync
--rules noGuardInTests
--rules testSuiteAccessControl
--rules validateTestCases
--rules redundantMemberwiseInit
--rules redundantBreak
--rules redundantTypedThrows
--rules preferFinalClasses
--rules simplifyGenericConstraints
--rules redundantEmptyView
--rules redundantViewBuilder
```

- [ ] **Step 2: Verify the file is present and non-empty**

Run: `wc -l .swiftformat && head -5 .swiftformat`

Expected: line count ≈ 150; first lines match the `# Exclude checkout directories...` comment and `--exclude Carthage,Pods,.build`.

- [ ] **Step 3: Commit**

```bash
git add .swiftformat
git commit -m "Vendor Airbnb SwiftFormat config

Pulled verbatim from github.com/airbnb/swift@master/Sources/
AirbnbSwiftFormatTool/airbnb.swiftformat. Bumps will be deliberate
re-vendoring with a diff review."
```

---

## Task 2: Create CI workflow with `format` job

**Files:**
- Create: `.github/workflows/ci.yml`

- [ ] **Step 1: Verify the workflow directory does not yet exist**

Run: `ls .github/workflows/ 2>&1 || echo "absent"`

Expected: `absent` (or the directory is empty). If a `ci.yml` already exists, stop and ask before proceeding.

- [ ] **Step 2: Create the workflow file with the `format` job**

Create `.github/workflows/ci.yml`:

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
  format:
    runs-on: macos-15
    steps:
      - uses: actions/checkout@v4

      - name: Install SwiftFormat
        run: brew install swiftformat

      - name: Lint with SwiftFormat
        run: swiftformat --lint .
```

- [ ] **Step 3: Validate YAML parses**

Run: `python3 -c "import yaml, sys; yaml.safe_load(open('.github/workflows/ci.yml')); print('ok')"`

Expected: `ok`. If a `YAMLError` is raised, fix indentation/quoting and re-run before continuing.

- [ ] **Step 4: Commit**

```bash
git add .github/workflows/ci.yml
git commit -m "Add CI workflow with SwiftFormat lint job

Two-trigger workflow (pull_request, push to main, workflow_dispatch)
on macos-15. Concurrency group cancels stale PR runs. format job
installs SwiftFormat via brew and runs swiftformat --lint against
the vendored config."
```

---

## Task 3: Add `ios` job to the workflow

**Files:**
- Modify: `.github/workflows/ci.yml`

- [ ] **Step 1: Append the `ios` job**

Append the following job under `jobs:` in `.github/workflows/ci.yml`, after the existing `format` job. The resulting `jobs:` block should contain both:

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
        run: xcodebuild -resolvePackageDependencies -scheme "$LIBRARY_SCHEME"

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

- [ ] **Step 2: Validate YAML parses and both jobs are present**

Run:
```bash
python3 -c "
import yaml
doc = yaml.safe_load(open('.github/workflows/ci.yml'))
jobs = list(doc['jobs'].keys())
assert jobs == ['format', 'ios'], f'unexpected jobs: {jobs}'
assert doc['jobs']['ios']['runs-on'] == 'macos-15'
print('ok')
"
```

Expected: `ok`.

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/ci.yml
git commit -m "Add ios job to CI workflow

xcodebuild test for the library scheme and xcodebuild build for the
demo scheme against an iOS Simulator destination, sharing one
simulator boot. SwiftPM dependencies cached on Package.resolved
hash. On failure, the xcresult bundle is uploaded for local
inspection."
```

---

## Task 4: Push and observe first CI run

**Files:** none (no edits; this task verifies behavior on the runner).

- [ ] **Step 1: Push the branch**

Run: `git push -u origin HEAD`

Expected: push succeeds, branch is set up to track origin. (`HEAD` resolves to the current branch name, so this command is invariant to which branch the plan is executed on.)

- [ ] **Step 2: Confirm a workflow run was triggered**

Use the GitHub MCP `pull_request_read` tool with `method: get_check_runs` on the open PR (or `list_workflow_runs` if no PR yet). Expect at least one check run created for commit HEAD within ~30 s.

If no check run appears after ~60 s: re-check `on:` triggers in `ci.yml` and verify the file is on the pushed branch.

- [ ] **Step 3: Categorize the result**

Wait for completion (notifications via the existing PR subscription). Expected outcomes:

- `format` — **pass** if the repo contains no Swift files yet, or only Swift files that match the Airbnb config. **Action: none if green.** If red, capture the failing rule from the log; do not commit auto-format fixes here without user confirmation.
- `ios` — **expected to fail** until the project-init job lands (`xcodebuild` will not find the `ChatClient` or `ChatClientDemo` schemes). **Action: none.** Note this in a PR comment so a reviewer is not surprised.

- [ ] **Step 4: Post a brief PR comment documenting expected red `ios` job**

Only if `ios` fails for the expected "no schemes" reason. Use the GitHub MCP `add_issue_comment` tool to post:

> The `ios` job is expected to fail on this PR until the project-init PR lands and the `ChatClient` / `ChatClientDemo` schemes exist. The `format` job is the meaningful signal until then.

If `ios` fails for a different reason (e.g., Xcode version not available, brew failure on the format job), open a follow-up rather than fixing in-line — the user should decide the next move.

---

## Acceptance criteria

When this plan is complete:

- `.swiftformat` exists at the repo root with Airbnb's verbatim config.
- `.github/workflows/ci.yml` exists with two jobs (`format`, `ios`) wired per the spec.
- A workflow run is visible on the PR's head commit.
- `format` is green (or its failure is a real lint issue, not a workflow misconfiguration).
- `ios` may be red pending project init; that's known and documented.
- Branch is pushed; PR is updated.

Configuring `format` and `ios` as required status checks under branch protection is **not** part of this plan — that's a one-time GitHub UI step the user owns after the first green run on `main`.
