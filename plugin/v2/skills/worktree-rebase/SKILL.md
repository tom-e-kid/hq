---
name: worktree-rebase
description: Worktreeブランチをメインブランチ(origin/HEAD)にリベースし、リモートも同期する
allowed-tools: Bash(bash *scripts/worktree-rebase.sh*)
---

## Context

- Worktree root: !`git rev-parse --show-toplevel`
- Current branch: !`git rev-parse --abbrev-ref HEAD`
- Git status: !`git status --short`

## Instructions

[scripts/worktree-rebase.sh](scripts/worktree-rebase.sh) を実行する。

```bash
bash "${CLAUDE_SKILL_DIR}/scripts/worktree-rebase.sh"
```

スクリプトが自動で以下を行う:

1. `origin/HEAD` からメインブランチを特定（例: `develop`）
2. ディレクトリ名の `@` 以降からworktreeブランチを特定（例: `develop_design_editor`）
3. 未コミット変更があればstash
4. worktreeブランチをメインブランチにrebase
5. worktreeブランチのリモートが乖離していれば `--force-with-lease` でpush
6. 作業ブランチがworktreeブランチと異なれば、作業ブランチもrebase
7. stashがあれば復元

## エラー時

- rebaseコンフリクト: スクリプトが中断メッセージを出力する。ユーザに状況を伝え、手動解消を案内する
- stash popコンフリクト: 同上
- `origin/HEAD` 未設定: `git remote set-head origin --auto` の実行を案内する
