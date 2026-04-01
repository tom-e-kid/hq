#!/bin/bash
set -euo pipefail

# Worktreeのベースブランチをupstreamに同期し、
# 作業ブランチがあればその上にrebaseする。
#
# 前提: worktreeディレクトリ名が <repo>@<base_branch> の規約に従うこと

worktree_dir=$(basename "$(git rev-parse --show-toplevel)")

if [[ "$worktree_dir" != *@* ]]; then
  echo "ERROR: worktree内ではありません（ディレクトリ名に @ が含まれていません）"
  exit 1
fi

base_branch="${worktree_dir#*@}"
current_branch=$(git rev-parse --abbrev-ref HEAD)

# ベースブランチのupstream取得
upstream=$(git rev-parse --abbrev-ref "${base_branch}@{upstream}" 2>/dev/null || echo "")
if [[ -z "$upstream" ]]; then
  echo "ERROR: ベースブランチ '$base_branch' にupstreamが設定されていません"
  exit 1
fi

remote="${upstream%%/*}"

echo "=== Rebase Worktree ==="
echo "ベースブランチ: $base_branch"
echo "upstream:       $upstream"
echo "作業ブランチ:   $current_branch"
echo ""

# 未コミット変更があればstash
stashed=false
if ! git diff --quiet || ! git diff --cached --quiet; then
  echo ">> 未コミット変更をstash..."
  git stash
  stashed=true
fi

# fetch
echo ">> $remote をfetch..."
git fetch "$remote"

# ベースブランチを更新
echo ">> $base_branch → $upstream に更新..."
if [[ "$current_branch" == "$base_branch" ]]; then
  # ベースブランチ上にいる場合はそのままrebase
  if ! git rebase "$upstream"; then
    echo ""
    echo "ERROR: rebaseでコンフリクトが発生しました"
    echo "  git rebase --continue  (コンフリクト解消後)"
    echo "  git rebase --abort     (中止)"
    [[ "$stashed" == true ]] && echo "  ※ stashあり: 解消後に git stash pop"
    exit 1
  fi
else
  # ベースブランチがupstreamのfast-forward先であることを確認
  if ! git merge-base --is-ancestor "$base_branch" "$upstream"; then
    echo "WARNING: $base_branch はupstream ($upstream) に対してfast-forwardできません"
    echo "  ベースブランチに独自のコミットがある可能性があります"
    echo "  手動で確認してください: git log $upstream..$base_branch"
    exit 1
  fi

  # 作業ブランチ上の場合はポインタを移動
  git branch -f "$base_branch" "$upstream"

  # 作業ブランチをベースブランチにrebase
  echo ">> $current_branch を $base_branch にrebase..."
  if ! git rebase "$base_branch"; then
    echo ""
    echo "ERROR: rebaseでコンフリクトが発生しました"
    echo "  git rebase --continue  (コンフリクト解消後)"
    echo "  git rebase --abort     (中止)"
    [[ "$stashed" == true ]] && echo "  ※ stashあり: 解消後に git stash pop"
    exit 1
  fi
fi

# stash復元
if [[ "$stashed" == true ]]; then
  echo ">> stashを復元..."
  if ! git stash pop; then
    echo ""
    echo "WARNING: stash popでコンフリクトが発生しました。手動で解消してください。"
    exit 1
  fi
fi

echo ""
echo "=== 完了 ==="
