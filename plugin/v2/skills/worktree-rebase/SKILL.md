---
name: worktree-rebase
description: Worktreeのベースブランチをupstreamに同期し、作業ブランチをrebaseする
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

1. worktreeディレクトリ名の `@` 以降からベースブランチを特定
2. 未コミット変更があればstash
3. ベースブランチのupstreamをfetch & ベースブランチを更新
4. 作業ブランチがベースと異なれば、ベースブランチにrebase
5. stashがあれば復元

## エラー時

- rebaseコンフリクト: スクリプトが中断メッセージを出力する。ユーザに状況を伝え、手動解消を案内する
- stash popコンフリクト: 同上
