# {{project_name}}

{{one-line project description}}

## Commands

| Action  | Command | Note |
|---------|---------|------|
| install |         |      |
| dev     |         |      |
| build   |         |      |
| test    |         |      |
| lint    |         |      |
| format  |         |      |

## Notes

<!-- Project-specific rules Claude cannot infer from code. Examples:
- Use bun only — npm/pnpm/yarn are forbidden, even for one-off scripts.
- All API responses must include `trace_id` in headers.
- The `legacy/` directory is frozen — do not modify.
-->

<!-- BEGIN HQ — managed by hq:bootstrap. Manual edits in this section are overwritten on re-run. -->
## HQ

### Verification

Untested code is a guess. After every change:

- Run/build the code, trigger the changed feature, check for errors.
- **UI** → interact with the element. **API** → make the call. **Data** → query the DB. **Config** → restart and verify.

### Build

{{build_pointer}}

### Test Strategy

{{test_strategy}}

<!-- END HQ -->
