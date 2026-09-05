#!/usr/bin/env bash
# The repository's gate. One command, so there is no second one to forget.
#
# It runs the plugin's own suite and the checks over this repository's
# documents. They are separate files because the plugin is a deliverable that
# does not read `docs/`, and separate suites are the only way to keep it that
# way — but a person changing this repository runs one thing.
#
# Output is the two TAP streams in order. Exit 0 when both pass.
#
# Run: bash .claude/scripts/check.sh

set -u

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
STATUS=0

printf '# plugin suite\n'
bash "$ROOT/plugin/scripts/test.sh" || STATUS=1

# Found by glob rather than named, so a suite added here is run without editing
# this file — the failure a named list has is a suite that exists and is never
# invoked, which looks exactly like a suite that passes.
printf '\n# .claude/scripts suites\n'
for t in "$ROOT"/.claude/scripts/*.test.sh; do
  [ -e "$t" ] || continue
  bash "$t" || STATUS=1
done

printf '\n# docs\n'
bash "$ROOT/.claude/scripts/docs-check.sh" || STATUS=1

# The tree face of the commit-time guard. It runs here as well because the
# commit hook is wired by `core.hooksPath` and a clone where nobody set that
# has no hook at all; this is the face that does not depend on a local config.
echo "# secrets"
bash "$ROOT/.claude/scripts/secrets-check.sh" tree || STATUS=1

exit "$STATUS"
