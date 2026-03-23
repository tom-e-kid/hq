---
description: "Collect requirement information and organize work item estimates with risks and blockers"
argument-hint: [topic or supplementary information (optional)]
---

# estimate

Starting from the session context, investigate the codebase and produce a structured work estimate.

## Arguments

- `$ARGUMENTS`: Topic name or supplementary information (optional). The primary input source is the context within the session.

## Procedure

### 1. Context Review and Information Gathering

Understand the requirements from the session context (conversation history, shared materials).

**If a previous estimate exists:**
If a prior estimate result is included in the context, treat it as the base.

- Carry over existing item numbers and sizes
- Append new items with sequential numbers at the end
- Mark changed or removed items with `(changed)` or `(removed)` in the notes column

**Check information channels:**
First, check whether a `## Information Channels` section exists in `$GIT_ROOT/CLAUDE.md`.

- **If present:** Follow the tools and methods described there to retrieve external references in the context
- **If absent (fallback):** Use the following generic methods:
  - Document URLs → fetch via WebFetch
  - GitHub Issue / PR numbers → fetch via `gh` command (if available)
  - Other references (IDs, numbers, paths, etc.) → ask via AskUser to confirm retrieval method

> **Parallelize:** If multiple external references exist, fetch them simultaneously using sub-agents

**If information is insufficient:**
Use AskUser to clarify missing information. Assess whether the following are covered:

- What to achieve (objective / goal)
- What changes are needed (functional requirements)
- Constraints and assumptions

### 2. Understanding Project Structure and Defining Scope

Investigate the project structure and clarify the scope of the estimate.

**Project structure investigation:**

- Understand the tech stack from directory structure and key configuration files
- Understand architectural patterns (layer structure, module separation)
- Check for existing coding conventions and shared foundations

**Scope definition:**
Clarify the estimation target based on user intent and project structure.

```
## Scope
- Target: <scope (e.g., entire frontend, API layer only, specific module)>
- Exclusions: <explicitly excluded items>
- Assumptions: <preconditions>
```

Confirm the scope with the user before proceeding.

### 3. Extracting and Organizing Requirements

Extract requirements from gathered information based on the confirmed scope.

**Extraction perspectives:**

- New features (new components, new data models)
- Changes to existing features (display changes, property additions, behavior changes)
- API / interface changes (endpoint additions/changes, data structure changes)
- Breaking changes (removal or replacement of existing behavior)
- Items determined to be out of scope

Present the organized results to the user and confirm there are no misalignments.

### 4. Codebase Impact Analysis

Identify existing code affected by each extracted requirement.

**Investigation approach:**

- Use Agent (Explore) to comprehensively investigate the impact scope

> **Parallelize:** If requirements have no dependencies on each other, investigate simultaneously using sub-agents

- Investigate from perspectives appropriate to the project structure:
  - Related model / data layer
  - Related UI / presentation layer
  - Related service / business logic layer
  - Impact on shared foundations (protocols, utilities, configuration)
  - Side effects on existing logic

### 5. Work Item Breakdown and Estimation

Structure work items from requirements and impact analysis results.

**Category classification:**

- **Foundation**: Shared components, interfaces, etc. that are prerequisites for other work
- **New Features**: Implementation of new components and data structures
- **Existing Modifications**: Changes to existing code (group items with common patterns)
- **Other**: Items that don't fit the above categories

**Item format:**

| #   | Item      |   Pattern    | Design | Impl  | Test  | Notes   |
| --- | --------- | :----------: | :----: | :---: | :---: | ------- |
| X-X | Item name | - / see #X-X | S/M/L  | S/M/L | S/M/L | Details |

**Size criteria:**

- S: 1 day
- M: 3 days
- L: 5 days

**Guidelines:**

- Estimate design, implementation, and test independently
- For modifications with a common pattern, estimate as "design one, roll out horizontally"
- For rollout items, set Pattern to `see #X-X` referencing the origin item, and set Design to `-` (no design cost)
- Origin items have Pattern set to `-`
- Note dependencies on other items in the notes column

### 6. Identifying Risks and Blockers

Identify risks from the following perspectives:

- **Unconfirmed specs**: Items that are undecided or need confirmation in the materials
- **Technical risk**: Areas with high implementation difficulty or requiring technical validation
- **External dependencies**: Waiting on other teams, waiting for external service spec finalization
- **Breaking changes**: Changes that affect existing user behavior
- **Uncertain impact scope**: Areas that could not be fully identified in the codebase investigation

Link each risk to the affected work item numbers.

### 7. Summary Output

Display the estimate results in a structured format.

Produce the summary in the user's language using the following structure.
Calculate totals by summing S=1, M=3, L=5 days across design, implementation, and test for each item.

```
## Estimate Summary

### Overview
- Topic: <topic name>
- Scope: <target scope>
- Work items: N
- Total estimate: X days (X weeks) — Design: X days / Impl: X days / Test: X days
- Risks: N

### Assumptions
- ...

### Work Item List
(Category-based tables)

### Estimate by Category
| Category | Items | Days | Weeks |
|----------|-------|------|-------|
| Foundation | N | X days | X weeks |
| ... | ... | ... | ... |
| **Total** | **N** | **X days** | **X weeks** |

### Risks and Blockers
| # | Description | Affected Items | Mitigation |
|---|-------------|----------------|------------|
| R-1 | ... | X-X | ... |

### Codebase Structure Notes
- List of affected file paths and modules
```

Incorporate user feedback (adjusting assumptions, resizing items, adding/removing items).
Re-run steps 4–6 as needed.

### 8. Save Estimate

Save the complete estimate to `.hq/estimates/<unique>.md` under the project root.

The goal is that a new session starting from this file alone can continue the estimation discussion without loss of context.

After saving, notify the user with the file path.

## Notes

- Estimates are "rough" and intended to be refined after detailed design
- Not everything needs to be covered in a single investigation. Document uncertain areas as risks and refine in subsequent investigations
- All output must be in the language used by the user
