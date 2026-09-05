#!/usr/bin/env bash
# Checks over this repository's documents. Run from `.claude/scripts/check.sh`
# together with the plugin's own suite; that entry point is the gate, this is
# one half of it.
#
# WHY THIS IS NOT IN THE PLUGIN'S SUITE. Everything here reads `docs/`, and the
# plugin is a deliverable that does not reach into `docs/` — a rule with
# a check of its own below. A suite inside `plugin/scripts/` that reached
# into `docs/` would be the first violation of it.
#
# Output is TAP. Exit 0 when every check passes.
#
# Run: bash .claude/scripts/docs-check.sh

set -u

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
DESIGN="$ROOT/docs/design.md"
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

printf 'TAP version 13\n'

# --- every cross-reference into the design document names its target ---------
#
# A reference carries the section's NAME, not its number. A number is a
# position, and positions move: remove a section and every citation of the
# numbers after it points somewhere else, still resolving, with nothing to
# read as broken.
#
# Two predicates, because they fail in different directions — a number cannot
# be resolved at all, and a name can be resolved and still be wrong. Citations
# led by an ASCII letter are a module definition's own sections, not the design
# document's, and are out of scope for both.
#
# The section sign is held in a variable and never written literally below.
# Otherwise the patterns in this file would read as citations and the checks
# would report themselves.

SEC=$(printf '\302\247')

# THE FILE SET FOLLOWS THE TREE. A written list is a second statement of the
# layout: rename a directory and the list stops matching, every predicate is
# asked about nothing, and nothing is also what a clean run answers.
#
# Nothing is pruned but `.git`. Every markdown and shell file in the tree is
# one a reader can land in, so every one of them has to resolve.
sweep_files() { # → one path per line
  find "$ROOT" \
      -name .git -prune -o \
      -type f \( -name '*.md' -o -name '*.sh' \) -print 2>/dev/null \
    | sort
}

SWEPT=$(sweep_files)

# Named anchors rather than a count: a floor number passes a sweep that lost
# everything but one file, and it has to be edited every time the tree grows.
anchors_missing() { # → the anchors the sweep did not return
  local a out=""
  for a in "$ROOT/AGENTS.md" "$DESIGN"; do
    printf '%s\n' "$SWEPT" | /usr/bin/grep -qxF "$a" || out="$out$a "
  done
  printf '%s' "${out% }"
}
check "the sweep returned the documents it is anchored on" "" "$(anchors_missing)"

# Section names come from the headings themselves — the number, the trailing
# ` — subtitle`, and nothing else stripped. Writing the list here instead would
# be a second copy of the very thing being checked.
#
# Both documents that carry cited sections, because the convention is not the
# design document's alone: AGENTS.md has sections and other files cite them by
# the same notation. Resolving against one of the two would refuse the other's
# citations as dangling.
section_names() { # → one name per line
  /usr/bin/grep -E '^#{2,3} [0-9]+(\.[0-9]+)?\.? ' "$DESIGN" \
    | sed -E 's/^#+ [0-9]+(\.[0-9]+)?\.? //; s/ —.*$//'
  /usr/bin/grep -E '^## [^0-9]' "$ROOT/AGENTS.md" 2>/dev/null \
    | sed -E 's/^## //; s/ —.*$//'
}

SECTION_NAMES=$(section_names)
SECTION_N=$(printf '%s\n' "$SECTION_NAMES" | /usr/bin/grep -c .)
check "the section-name extraction found the headings" yes \
  "$([ "$SECTION_N" -ge 9 ] && echo yes || echo "no ($SECTION_N)")"

# A citation is followed by whatever prose comes next, with no space to end it
# in Japanese, so resolution is by PREFIX. That only decides anything while no
# name is a prefix of another; if one were, citing the shorter name would
# excuse a section that does not exist.
PREFIX_CLASH=""
while IFS= read -r a; do
  [ -n "$a" ] || continue
  while IFS= read -r b; do
    [ -n "$b" ] || continue
    [ "$a" = "$b" ] && continue
    case "$b" in "$a"*) PREFIX_CLASH="$PREFIX_CLASH[$a]<[$b] " ;; esac
  done <<INNER
$SECTION_NAMES
INNER
done <<OUTER
$SECTION_NAMES
OUTER
check "no section name is a prefix of another" "" "$PREFIX_CLASH"

# Every list below is walked a line at a time. Splitting on whitespace loses
# any name or path that holds a space — a section named `plugin 開発の参照先`
# becomes `plugin`, which then answers for every citation starting with it, and
# a checkout under a path with a space leaves the sweep with no readable files
# at all. Both fail the same way: the predicate is asked about less than it was
# handed, and reports clean.
resolves() { # <token> — 0 when some section name starts it
  local n
  while IFS= read -r n; do
    [ -n "$n" ] || continue
    case "$1" in "$n"*) return 0 ;; esac
  done <<EOF
$SECTION_NAMES
EOF
  return 1
}

# The space after the sign is not part of the citation — a reader who writes it
# closed up means the same thing, and a predicate that requires it refuses one
# spelling and waves the other through.
#
# A citation into a frozen version is left alone. Those documents are never
# renumbered, so the number is a stable address there; this is the one place a
# numbered citation still says what it meant when it was written.
#
# THE EXEMPTION IS THE CITATION'S, NOT THE LINE'S. A line-wide one waves through
# every numbered citation is reported. There is nowhere in this tree whose
# numbering is fixed, so there is no citation a number can safely address.
numeric_refs() { # <file>… — citations that name a section by number
  local f hit
  for f in "$@"; do
    [ -f "$f" ] || continue
    while IFS= read -r hit; do
      [ -n "$hit" ] || continue
      printf '%s:%s\n' "$f" "$hit"
    done <<EOF
$(/usr/bin/grep -nE "$SEC[[:space:]]*[0-9]" "$f" 2>/dev/null)
EOF
  done
}

unresolved_refs() { # <file>… — named citations no heading answers
  local f ref out=""
  for f in "$@"; do
    [ -f "$f" ] || continue
    # A bracket expression holding multibyte characters splits into bytes under
    # BSD grep and truncates the token mid-character. Cutting at the ASCII
    # space keeps whole characters, and the trailing prose is harmless because
    # resolution is by prefix. Digit-led tokens belong to the check above.
    while IFS= read -r ref; do
      ref=${ref#"$SEC"}
      ref=${ref# }
      [ -n "$ref" ] || continue
      case "$ref" in [A-Za-z0-9]*) continue ;; esac
      resolves "$ref" || out="$out$(basename "$f"): $ref
"
    done <<EOF
$(/usr/bin/grep -oE "$SEC ?[^ ]*" "$f" 2>/dev/null)
EOF
  done
  printf '%s' "$out"
}

# The swept list is newline-delimited and passed one path at a time, for the
# reason in the comment above resolves().
swept_numeric_refs() {
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    numeric_refs "$f"
  done <<EOF
$SWEPT
EOF
}
swept_unresolved_refs() {
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    unresolved_refs "$f"
  done <<EOF
$SWEPT
EOF
}

check "no cross-reference cites a section by number" "" "$(swept_numeric_refs)"
check "every cross-reference names a section that exists" "" "$(swept_unresolved_refs)"

# Positive control for both. Neither can tell "nothing to report" from "read
# nothing": the file list is a glob, the extraction is a grep, and an empty
# answer is what a passing run looks like.
REF_FIX="$TMP/refs.md"
printf 'see %s 4.2 for this, %s 実在しない節 for that, %s Context is fine.\n' \
  "$SEC" "$SEC" "$SEC" >"$REF_FIX"
check "a numeric reference is reported" 1 \
  "$(numeric_refs "$REF_FIX" | /usr/bin/grep -c . || true)"
check "an unknown section name is reported" 1 \
  "$(unresolved_refs "$REF_FIX" | /usr/bin/grep -c . || true)"
printf '%s 設計原則に従う\n' "$SEC" >"$REF_FIX"
check "a name that resolves is not reported" "" "$(unresolved_refs "$REF_FIX")"

# --- the plan's section list is stated twice, so it is compared --------------
#
# The design document names the sections while saying what each is for, and the
# plan gate enforces the list. The explanation cannot be written without the
# names, so the copy stays and this is the comparison that keeps it honest —
# the rule being that a fact written twice is either compared by a machine or
# reduced to one statement.
#
# The gate is the side that decides; the document is the side that can rot, and
# only the document is this suite's business.

PLAN_GATE="$ROOT/plugin/scripts/plan-gate.sh"

doc_plan_sections() { # → the names in the 節 column, one per line
  awk -F'|' '/成果物の節は/{t=1} t && /^\|/{print $3} t && /^$/ && seen{exit} t && /^\|/{seen=1}' \
    "$DESIGN" 2>/dev/null \
    | tr '/' '\n' | sed 's/^ *//; s/ *$//' \
    | /usr/bin/grep -v '^節$' | /usr/bin/grep -v '^-*$' | /usr/bin/grep -v '^$' \
    | sort
}

gate_plan_sections() { # → the names the enum holds, one per line
  /usr/bin/grep -m1 '^REQUIRED_SECTIONS=' "$PLAN_GATE" 2>/dev/null \
    | sed 's/^REQUIRED_SECTIONS="//; s/".*//' \
    | tr '|' '\n' | sed '/^$/d' | sort
}

DOC_SECTIONS=$(doc_plan_sections)
check "the document's section table was read at all" yes \
  "$([ "$(printf '%s\n' "$DOC_SECTIONS" | /usr/bin/grep -c .)" -ge 5 ] && echo yes || echo no)"
check "the document and the plan gate agree on the sections" \
  "$(gate_plan_sections | tr '\n' ' ')" "$(printf '%s\n' "$DOC_SECTIONS" | tr '\n' ' ')"

# --- the plugin does not reach into docs/ -----------------------------------
#
# The plugin is what ships; `docs/` is why it is shaped that way. A pointer
# into a document from a script is a pointer nobody updates, and a check inside
# the plugin that reads one makes the deliverable depend on a file it does not
# carry.
#
# The names come from the directory listing, so a document added later is
# covered without editing this. Both spellings are matched — with the directory
# and without — because a citation drops the directory as often as not.
# `DESIGN.md` is matched too: that is where the design document lived before it
# moved here, and a pointer to the old path is as dead as one to the new.
#
# A generic name in `docs/` would collide with the fixture paths the plugin's
# own suites use (`docs/a.md` and the like, inside throwaway repositories).
# Nothing collides today; the answer if one ever does is to rename the fixture,
# since the fixture is the side that can be anything.

doc_names() { # → one document name per line
  ls "$ROOT/docs" | /usr/bin/grep '\.md$'
  printf 'DESIGN.md\n'
}

doc_mentions() { # <directory> — lines in it that name one of those documents
  local n
  while IFS= read -r n; do
    [ -n "$n" ] || continue
    /usr/bin/grep -rn -- "$n" "$1" 2>/dev/null || true
  done <<EOF
$(doc_names)
EOF
}

DOC_N=$(doc_names | /usr/bin/grep -c .)
check "the document list was read at all" yes \
  "$([ "$DOC_N" -ge 2 ] && echo yes || echo "no ($DOC_N)")"

check "the directory the document sweep reads exists" yes \
  "$([ -d "$ROOT/plugin" ] && echo yes || echo no)"
check "nothing under plugin names a document in docs/" "" \
  "$(doc_mentions "$ROOT/plugin")"

# Positive control. The sweep above returns nothing on a tree that complies and
# would return nothing just as quietly if the names stopped being read or the
# pattern stopped matching. One fixture line per spelling.
MENTION_FIX="$TMP/plugin-fixture"
mkdir -p "$MENTION_FIX"
printf '# see DESIGN.md for why\n' >"$MENTION_FIX/a.sh"
printf '# see docs/design.md for why\n' >"$MENTION_FIX/b.sh"
printf '# see postmortems.md for why\n' >"$MENTION_FIX/c.sh"
check "a script naming a document is reported, in either spelling" 3 \
  "$(doc_mentions "$MENTION_FIX" | /usr/bin/grep -c . || true)"

# --- scope -------------------------------------------------------------------
#
# Everything here is a question about the text: does a reference resolve, does
# the plugin reach outside itself. Whether the design document is still TRUE of
# the tree is a different question and not decidable from the text, so it is
# not attempted here. It belongs at the moment a change is proposed, which is
# where `hq:pr` asks it.

printf '1..%d\n' "$N"
if [ "$FAILED" -gt 0 ]; then
  printf '# %d of %d checks failed\n' "$FAILED" "$N"
  exit 1
fi
printf '# all %d checks passed\n' "$N"
