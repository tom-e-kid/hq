#!/usr/bin/env bash
# Suite for docs-check.sh, and the coverage check over `.claude/scripts`.
#
# The checks in docs-check.sh carry positive controls of their own, and those
# controls answer a narrower question than this file does: they prove a
# predicate still fires on input handed straight to it. What they cannot see is
# the input never arriving — a path that stopped matching, a directory that
# moved — because the predicate is then asked about nothing and answers
# nothing, which is what a passing run also looks like.
#
# So this suite runs docs-check.sh THE WAY IT IS ACTUALLY INVOKED: a fixture
# tree with the same shape, a copy of the script at the same place inside it,
# and the exit code read from outside. Every case is a tree that differs from a
# compliant one in exactly one way.
#
# Output is TAP. Exit 0 when every check passes.
#
# Run: bash .claude/scripts/docs-check.test.sh

set -u

HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

N=0
FAILED=0
ok() { N=$((N + 1)); printf 'ok %d - %s\n' "$N" "$1"; }
not_ok() { # <name> <detail>
  N=$((N + 1))
  FAILED=$((FAILED + 1))
  printf 'not ok %d - %s\n  ---\n  detail: %s\n  ...\n' "$N" "$1" "$2"
}
check() { # <name> <expected> <actual>
  if [ "$2" = "$3" ]; then ok "$1"; else not_ok "$1" "expected [$2], got [$3]"; fi
}

SEC=$(printf '\302\247')

# A tree docs-check.sh passes on. Every case below starts from one of these and
# changes one thing, so a case that goes red names that one thing.
mk_tree() { # <dir>
  local d=$1
  mkdir -p "$d/docs" "$d/.claude/scripts" \
    "$d/plugin/scripts" "$d/plugin/commands" "$d/plugin/agents"
  cat >"$d/docs/design.md" <<'EOF'
# design

## 0. 要旨
## 1. 用語
## 2. 目標
## 3. 設計原則
## 4. アーキテクチャ
### 4.1 入力の統治 — 層 1 と層 2
### 4.2 出力の検証 — 柱 A と柱 B
## 5. 憲法
## 6. モジュール構成
## 7. 記録と評価指標 — telemetry
## 8. 構築の進め方

**成果物の節は 5 つで、任意のものは無い。**

| 群 | 節 | 何のためにあるか |
|---|---|---|
| 導入 | Summary | 何をしようとしているか |
| 判定 | Requirements | 満たすべき成果と確かめ方 |
| 根拠 | Notes | 調査で分かった事実 |
| 決定 | Editable surface | 触ってよい範囲 |
| 下限 | Floor | どんな実装でも通る検査 |
EOF
  printf 'REQUIRED_SECTIONS="Summary|Requirements|Notes|Editable surface|Floor"\n' \
    >"$d/plugin/scripts/plan-gate.sh"
  printf 'notes\n' >"$d/docs/postmortems.md"
  printf 'guide, see %s 設計原則\n\n## リリース運用\n\nand %s リリース運用 resolves here\n\n## plugin 開発の参照先\n' \
    "$SEC" "$SEC" >"$d/AGENTS.md"
  printf '# a script\n' >"$d/plugin/scripts/a.sh"
  printf 'a command, see %s Context\n' "$SEC" >"$d/plugin/commands/a.md"
  printf 'an agent\n' >"$d/plugin/agents/a.md"
  cp "$HERE/docs-check.sh" "$d/.claude/scripts/docs-check.sh"
}

run_in() { # <dir> — exit code of docs-check.sh there
  ( bash "$1/.claude/scripts/docs-check.sh" >/dev/null 2>&1 )
  printf '%s' "$?"
}

# --- the compliant tree, which every other case is measured against ----------

CLEAN="$TMP/clean"
mk_tree "$CLEAN"
check "a compliant tree passes" 0 "$(run_in "$CLEAN")"

# --- a citation by number is refused, in both spellings ----------------------

SPACED="$TMP/spaced"
mk_tree "$SPACED"
printf 'see %s 4.1 for this\n' "$SEC" >>"$SPACED/plugin/scripts/a.sh"
check "a numbered citation is refused" 1 "$(run_in "$SPACED")"

# The space is not part of the citation. A reader writing it closed up means
# the same thing, and a predicate that requires the space refuses one spelling
# and waves the other through — which is the whole failure it exists to stop.
TIGHT="$TMP/tight"
mk_tree "$TIGHT"
printf 'see %s4.1 for this\n' "$SEC" >>"$TIGHT/plugin/scripts/a.sh"
check "a numbered citation with no space after the sign is refused" 1 \
  "$(run_in "$TIGHT")"

# Every numbered citation is refused, wherever it points. There is nowhere in
# this tree whose numbering is fixed, so there is no address a number can
# safely name — the exemption that used to exist belonged to frozen versions,
# and there are none.
NUMBERED="$TMP/numbered-anywhere"
mk_tree "$NUMBERED"
printf 'the four articles live elsewhere %s 5\n' "$SEC" >>"$NUMBERED/AGENTS.md"
check "a numbered citation is refused wherever it points" 1 "$(run_in "$NUMBERED")"

# --- a name that answers to no heading is refused ----------------------------

UNKNOWN="$TMP/unknown"
mk_tree "$UNKNOWN"
printf 'see %s 実在しない節 for this\n' "$SEC" >>"$UNKNOWN/AGENTS.md"
check "a citation naming no heading is refused" 1 "$(run_in "$UNKNOWN")"

# --- moving a directory does not turn the sweep off --------------------------
#
# The case the positive controls inside docs-check.sh cannot reach: they hand a
# predicate its input directly, so they keep passing when the input stops
# arriving. A file set written out as paths fails exactly here — rename the
# directory and every predicate is asked about nothing, which is what a clean
# tree answers too.

MOVED="$TMP/moved"
mk_tree "$MOVED"
mv "$MOVED/plugin/scripts" "$MOVED/plugin/scriptz"
printf 'see %s 4.1 for this\n' "$SEC" >>"$MOVED/plugin/scriptz/a.sh"
check "a citation under a renamed directory is still refused" 1 "$(run_in "$MOVED")"

# The sweep follows the tree, so the anchors are what says it read the right
# tree at all. Without them an empty answer would be indistinguishable from a
# sweep that found nothing because it was pointed somewhere else.
GONE="$TMP/gone"
mk_tree "$GONE"
rm "$GONE/docs/design.md"
check "the design document missing is reported" 1 "$(run_in "$GONE")"

# The document-mention sweep is rooted at a path rather than derived, so it has
# the failure the citation sweep no longer has, and needs its own guard.
WHOLE="$TMP/whole"
mk_tree "$WHOLE"
mv "$WHOLE/plugin" "$WHOLE/plugin-gone"
check "the plugin directory missing is reported" 1 "$(run_in "$WHOLE")"

# --- the plugin naming a document is refused ---------------------------------

NAMES="$TMP/names"
mk_tree "$NAMES"
printf '# see docs/design.md for why\n' >>"$NAMES/plugin/scripts/a.sh"
check "a plugin script naming a document is refused" 1 "$(run_in "$NAMES")"

# --- a name or a path holding a space is not silently dropped ----------------
#
# Both are the same defect: a list walked with word splitting hands the
# predicate less than it was given, and less is what a clean tree also gives.
# One shows up in the data (a section name with a space becomes two names, and
# the first answers for every citation starting with it), the other in the
# environment (a checkout under a path with a space leaves no readable file to
# sweep at all). Neither turns anything red on its own.

FRAGMENT="$TMP/fragment"
mk_tree "$FRAGMENT"
printf 'see %s 開発の参照先 for this\n' "$SEC" >>"$FRAGMENT/plugin/commands/a.md"
check "a citation naming part of a spaced section name is refused" 1 \
  "$(run_in "$FRAGMENT")"

SPACED_PATH="$TMP/with space"
mk_tree "$SPACED_PATH"
printf 'see %s 4.1 for this\n' "$SEC" >>"$SPACED_PATH/plugin/scripts/a.sh"
check "a numbered citation under a path holding a space is refused" 1 \
  "$(run_in "$SPACED_PATH")"

check "and such a tree otherwise passes" 0 "$(mk_tree "$TMP/with space clean"; \
  run_in "$TMP/with space clean")"

# --- the design document's section table is compared, not trusted ------------
#
# The document names the plan's sections while explaining what each is for, and
# the gate enforces the same list. Two statements of one fact: the rule is that
# a machine compares them or one of them goes, and the explanation cannot be
# written without the names.

TABLE_BAD="$TMP/table-bad"
mk_tree "$TABLE_BAD"
sed -i.bak 's/| 決定 | Editable surface |/| 決定 | Editable surfaces |/' \
  "$TABLE_BAD/docs/design.md"
check "a section renamed in the document alone is reported" 1 "$(run_in "$TABLE_BAD")"

GATE_BAD="$TMP/gate-bad"
mk_tree "$GATE_BAD"
sed -i.bak 's/|Floor"/|Floors"/' "$GATE_BAD/plugin/scripts/plan-gate.sh"
check "a section renamed in the gate alone is reported" 1 "$(run_in "$GATE_BAD")"

# --- every script here has a test beside it ----------------------------------
#
# The design principle behind the plugin's own suite — one test file per script,
# checked mechanically rather than remembered — stops at `plugin/scripts`,
# because the check that enforces it is handed that directory and no other.
# This is the same predicate over the directory it cannot see.
#
# `release.sh` is the one script exempted, and it is named here rather than
# filtered by a pattern: it predates this suite, it acts on the remote (merge,
# push, tag, Release), and every one of its preconditions is already exercised
# by its own `--dry-run`. A pattern would quietly exempt the next script too.

missing_tests() { # <dir> — scripts with no adjacent test file
  local f base out=""
  for f in "$1"/*.sh; do
    [ -e "$f" ] || continue
    case "$f" in *.test.sh) continue ;; esac
    base=$(basename "$f" .sh)
    [ "$base" = release ] && continue
    [ -f "$1/$base.test.sh" ] || out="$out$base.sh "
  done
  printf '%s' "${out% }"
}

check "every script here has a test file beside it" "" "$(missing_tests "$HERE")"

# Positive control. An empty answer is what a covered directory returns, and it
# is also what a broken loop returns.
PROBE="$TMP/probe"
mkdir -p "$PROBE"
printf '#\n' >"$PROBE/covered.sh"
printf '#\n' >"$PROBE/covered.test.sh"
printf '#\n' >"$PROBE/uncovered.sh"
check "a script with no test is reported" "uncovered.sh" "$(missing_tests "$PROBE")"

printf '1..%d\n' "$N"
if [ "$FAILED" -gt 0 ]; then
  printf '# %d of %d checks failed\n' "$FAILED" "$N"
  exit 1
fi
printf '# all %d checks passed\n' "$N"
