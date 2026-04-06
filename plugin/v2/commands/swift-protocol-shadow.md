---
name: swift-protocol-shadow
description: Detect protocol default implementation shadowing caused by signature mismatches in Swift
argument-hint: <directory>
allowed-tools: Read, Glob, Grep, Bash(grep:*), Agent, Write, TaskCreate, TaskUpdate
---

# SWIFT-PROTOCOL-SHADOW — Detect Protocol Default Implementation Shadowing

Statically analyze Swift source code in the specified directory to detect **protocol default implementation shadowing** — where a conforming type intends to override a default implementation but has a subtly different signature, resulting in two coexisting methods instead of an override.

## Execution Policy

**Fully autonomous** — execute all steps (0 through 5) without pausing for user confirmation. Make all decisions independently. Only stop to ask the user if `$ARGUMENTS` is missing or ambiguous.

**Progress tracking** — use Claude Code's task UI (`TaskCreate` / `TaskUpdate`) to show progress. At the start of execution, create all steps as tasks:

| Task subject | activeForm |
|---|---|
| Initialize .hq/protocol-shadow/ | Initializing output directory |
| Collect protocol definitions | Collecting protocols |
| Analyze conforming types | Analyzing conforming types |
| Self-review results | Reviewing results |
| Generate final report | Generating final report |

Set each task to `in_progress` when starting and `completed` when done. Update the subject with counts as they become available (e.g., "Collect protocol definitions — 8 protocols found").

## Background

In Swift, overriding a protocol's default implementation does not require the `override` keyword. If the signature differs even slightly, the compiler silently accepts both methods — the conforming type's method **does not satisfy the protocol requirement**, and the default implementation is used instead. This is especially common during Swift 6 `@MainActor @Sendable` migration work.

## Arguments

- `$ARGUMENTS` (directory): Path to the target directory (e.g., `Sources`, `.`)

## Output Directory

All intermediate results and the final report are written to `.hq/protocol-shadow/`.

```
.hq/protocol-shadow/
├── protocols/        # Step 1: Protocol definitions (structured data)
├── conformances/     # Step 2-3: Conforming types + signatures + comparison results
├── findings/         # Step 2-3: Detected mismatches
├── review.md         # Step 4: Self-review results
└── report.md         # Step 5: Final report
```

## Procedure

### Step 0: Initialization

1. Remove `.hq/protocol-shadow/` if it exists to start fresh
2. Create `protocols/`, `conformances/`, `findings/` subdirectories

```bash
rm -rf .hq/protocol-shadow
mkdir -p .hq/protocol-shadow/{protocols,conformances,findings}
```

### Step 1: Protocol Collection (Collector Agent)

If the target directory contains many Swift files, split the work across multiple Agents running in parallel. For small file counts, a single Agent is sufficient.

Pass the following instructions to each Agent:

> **Role: Collector**
>
> Collect protocol definitions from the assigned Swift files and write them to `.hq/protocol-shadow/protocols/`.
>
> **Target files**: `<list of assigned files>`
>
> **Steps**:
> 1. Find `protocol <Name>` declarations and extract `func` / `var` requirements from the body
> 2. Search the same file and the entire project for `extension <ProtocolName>` to extract default implementations (`func` / `var` definitions)
> 3. **Only write out protocols that have default implementations**
> 4. If `typealias` indirectly defines a closure type, record the expanded type as well
>
> **Output**: `.hq/protocol-shadow/protocols/<ProtocolName>.md`
>
> **Format**:
> ```markdown
> ---
> name: <ProtocolName>
> file: <relative path>
> line: <line number>
> ---
>
> ## Requirements
>
> | member | line | signature |
> |--------|------|-----------|
> | <name> | <N> | `<full signature>` |
>
> ## Default Implementations
>
> | member | line | constraint | signature |
> |--------|------|------------|-----------|
> | <name> | <N> | `<where clause or "none">` | `<full signature>` |
>
> ## Type Aliases
>
> | name | expansion | file | line |
> |------|-----------|------|------|
> | <alias> | `<expanded type>` | <file> | <N> |
> ```
>
> **Important**: Record signatures verbatim — include `@MainActor`, `@Sendable`, `@escaping`, `Optional`, etc. exactly as written.

After all Agents complete, verify the file count in `protocols/`.

### Step 2-3: Conforming Type Discovery + Signature Comparison (Analyzer Agent)

Read `protocols/` files and launch **one Analyzer Agent per protocol** (max 3 in parallel).

Pass the following instructions to each Agent:

> **Role: Analyzer**
>
> Discover conforming types for the protocol and compare their signatures against the defaults.
>
> **Input**: Read `.hq/protocol-shadow/protocols/<ProtocolName>.md` to learn the protocol name, requirements, and default implementations.
>
> **Steps**:
> 1. Search the **entire project** (not limited to `$ARGUMENTS`) for conforming types:
>    - `class/struct/enum <TypeName>: ... <ProtocolName>` (direct conformance)
>    - Inheritance chain (indirect — if a parent class conforms, subclasses are also in scope)
>    - `extension <TypeName>: <ProtocolName>` conformance
> 2. For each conforming type, check whether a member with the **same name** as a default implementation exists
> 3. If a same-named member is found, **Read the actual file** and compare parameter type signatures:
>    - Comparison points: `@MainActor`, `@Sendable`, `@escaping`, `Optional` vs non-Optional, parameter labels, return type
>    - Expand `typealias` before comparison
> 4. Write results
>
> **Output 1**: `.hq/protocol-shadow/conformances/<ProtocolName>.md`
>
> **Conformances format**:
> ```markdown
> ---
> protocol: <ProtocolName>
> conforming_types: <count>
> ---
>
> ## <TypeName>
>
> - file: <relative path>
> - conformance: <direct | inherited | extension>
> - line: <conformance declaration line>
>
> ### Overrides
>
> | member | line | signature | matches_default |
> |--------|------|-----------|-----------------|
> | <name> | <N> | `<full signature>` | yes / **NO** |
>
> (If no same-named members exist: "Overrides: none — uses all defaults")
> ```
>
> **Output 2**: Only when mismatches are found — `.hq/protocol-shadow/findings/<NNN>.md`
>
> **Findings format**:
> ```markdown
> ---
> protocol: <ProtocolName>
> method: <member name>
> type: <TypeName>
> file: <relative path>
> line: <line number>
> ---
>
> - protocol requirement: `<requirement signature>` (<file>:<line>)
> - default impl: `<default signature>` (<file>:<line>)
> - type impl: `<type signature>` (<file>:<line>)
> - diff: <specific description of the difference>
> - impact: <description of the impact>
> ```
>
> Number findings files from `001` sequentially. Check existing files before writing to avoid collisions with other Agents.
>
> **Important**: Never guess signatures — always Read the actual source file to verify.

### Step 4: Self-Review (Reviewer Agent)

After all Analyzer Agents complete, launch a single Reviewer Agent.

> **Role: Reviewer**
>
> Verify the preceding steps' results and check for missed detections or false positives.
>
> **Input**: Read all files under `.hq/protocol-shadow/` — `protocols/`, `conformances/`, `findings/`
>
> **Verification items**:
>
> 1. **Coverage verification**
>    - Run `grep -r "^protocol "` on the target directory and count actual protocol declarations
>    - Compare against the number of files in `protocols/`
>    - Protocols without default implementations are correctly excluded, but verify none with defaults were missed
>    - If any are missing, collect and analyze them, then write additional findings
>
> 2. **Findings verification**
>    - Read each file in `findings/` and open the referenced file path and line number with the Read tool
>    - Confirm the documented signature matches the actual file content
>    - Correct or dismiss any findings that don't match
>
> 3. **Spot checks**
>    - Pick up to 3 conforming types from `conformances/` that show no mismatches (all `matches_default: yes`)
>    - Read the actual files to confirm there are truly no mismatches
>    - Add findings if any were missed
>
> 4. **Inheritance chain verification**
>    - Verify that parent protocol default implementations are also checked for each protocol in `protocols/`
>    - Example: if `ChildProtocol: ParentProtocol`, default implementations from `ParentProtocol` must also be compared
>
> **Output**: `.hq/protocol-shadow/review.md`
>
> **Review format**:
> ```markdown
> ---
> date: <YYYY-MM-DD>
> protocols_expected: <grep count>
> protocols_collected: <files in protocols/>
> protocols_with_defaults: <count of protocols that have defaults>
> findings_count: <files in findings/>
> spot_checks: <number of spot checks performed>
> ---
>
> ## Coverage Verification
>
> <results>
>
> ## Findings Verification
>
> | finding | verified | notes |
> |---------|----------|-------|
> | 001.md | OK / NG | <details> |
>
> ## Spot Checks
>
> | type | protocol | result | notes |
> |------|----------|--------|-------|
> | <TypeName> | <ProtocolName> | OK / **MISSED** | <details> |
>
> ## Inheritance Chain Verification
>
> <results>
>
> ## Additional Findings
>
> <Any new issues discovered during review. Also added to findings/>
> ```

### Step 5: Final Report

1. Read `findings/` and `review.md`
2. Report results to the user
3. Write `report.md` with the final report

Report format:

```markdown
## Findings

### Warning: Signature Mismatch — <method name>

- **Protocol**: `<ProtocolName>` (<file>:<line>)
  - Requirement: `func foo(completion: (() -> Void)?)`
- **Default implementation**: <file>:<line>
  - Signature: `func foo(completion: (() -> Void)?)`
- **Conforming type**: `<TypeName>` (<file>:<line>)
  - Signature: `func foo(completion: (@MainActor @Sendable () -> Void)?)`
- **Diff**: `@MainActor @Sendable` added to `completion` parameter
- **Impact**: The conforming type's method does not satisfy the protocol requirement; the default implementation is used instead
```

If no mismatches are found, report: "No issues detected."

## Notes

- Full type inference is only possible with the compiler. This command uses text-based heuristic analysis. Note in the results that false positives and false negatives are possible.
- When `typealias` indirectly defines a closure type, expand it before comparison.
- Max 3 Agents running in parallel. If `protocols/` has 4+ files, batch in groups of 3 — wait for completion before launching the next batch.
- Ensure `.hq/protocol-shadow/` is not committed if it's not in `.gitignore`.
