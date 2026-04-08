# Swift-Protocol-Shadow Flow

`/swift-protocol-shadow <directory>` statically analyzes Swift source code to detect **protocol default implementation shadowing** — where a conforming type's method has a subtly different signature from the protocol default, causing the default to silently win at runtime.

```
Step 0: Initialization
│  Clean .hq/protocol-shadow/
│  Create protocols/, conformances/, findings/
│
Step 1: Protocol Collection (Collector Agents — parallel)
│  ┌─────────────────────────────────────────────┐
│  │  Scan Swift files for protocol declarations  │
│  │  Extract requirements + default impls        │
│  │  Write protocols/<ProtocolName>.md           │
│  │  (only protocols with default impls)         │
│  └─────────────────────────────────────────────┘
│
Step 2-3: Conforming Type Discovery + Comparison (Analyzer Agents — parallel, max 3)
│  ┌─────────────────────────────────────────────┐
│  │  One agent per protocol                      │
│  │  Find all conforming types (direct,          │
│  │    inherited, extension)                     │
│  │  Compare signatures against defaults         │
│  │  → conformances/<Protocol>.md                │
│  │  → findings/<NNN>.md (mismatches only)       │
│  └─────────────────────────────────────────────┘
│
Step 4: Self-Review (Reviewer Agent)
│  ┌─────────────────────────────────────────────┐
│  │  Coverage: grep count vs collected count     │
│  │  Findings verification: read actual files    │
│  │  Spot checks: verify "no mismatch" types     │
│  │  Inheritance chain: parent protocol defaults  │
│  │  → review.md                                 │
│  └─────────────────────────────────────────────┘
│
Step 5: Final Report
   Compile findings + review → report.md
   Report to user
```

## Key Design Decisions

- **Fully autonomous** — no user confirmation between steps. Runs all 6 steps end-to-end and reports the final result. Only asks the user if the directory argument is missing.
- **Heuristic analysis** — text-based static analysis without the compiler. False positives/negatives are possible and noted in the report.
- **Multi-agent pipeline** — Collector → Analyzer → Reviewer stages with parallelism within each stage (max 3 concurrent agents).
- **Self-review** — a dedicated Reviewer Agent verifies coverage, validates findings against actual source, and performs spot checks to catch missed detections.
- **Signature-exact comparison** — `@MainActor`, `@Sendable`, `@escaping`, `Optional` differences are all checked. `typealias` expansions are resolved before comparison.
- **Swift 6 migration focus** — particularly targets shadowing introduced by `@MainActor @Sendable` annotation changes.
