---
name: worktree-setup
description: 新規worktreeを作成し、ローカルファイルをセットアップする
allowed-tools: Bash(bash *scripts/worktree-setup.sh*)
---

## Context

- Main repo root: !`git rev-parse --show-toplevel`
- Existing worktrees: !`git worktree list`
- Default branch: !`git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null || echo "not set"`

## Instructions

ユーザの要求からブランチ名を特定し、[scripts/worktree-setup.sh](scripts/worktree-setup.sh) を実行する。

### 新規ブランチでworktreeを作成

```bash
bash "${CLAUDE_SKILL_DIR}/scripts/worktree-setup.sh" <base-branch> --branch <new-branch>
```

### 既存ブランチでworktreeを作成

```bash
bash "${CLAUDE_SKILL_DIR}/scripts/worktree-setup.sh" <base-branch>
```

### 引数の解決ルール

ユーザがブランチ名だけ伝えた場合:
1. そのブランチがローカルまたはリモートに存在するか確認
2. 存在する → 既存ブランチとして `<base-branch>` に使用
3. 存在しない → 新規ブランチ名と解釈し、ベースブランチをユーザに確認（デフォルト: リモートHEADブランチ）

### スクリプト完了後

`.claude/settings.local.json` について案内する:
- メインリポに `.claude/settings.local.json` が存在する場合、その内容を参考に新worktree用の設定が必要か確認する
- 絶対パスが含まれるため自動コピーは行わない。ユーザの判断を仰ぐ

## エラー時

- worktreeディレクトリが既に存在: スクリプトが中断する
- ブランチがローカル・リモート両方に存在しない: スクリプトが中断する
