#!/bin/bash
set -euo pipefail

# Worktreeブランチをメインブランチ(origin/HEAD)にリベースし、
# 作業ブランチがあればその上にリベースする。
# リベース後、worktreeブランチのリモートが乖離していれば --force-with-lease でプッシュ。
#
# 前提: worktreeディレクトリ名が <repo>@<branch> の規約に従うこと

worktree_dir=$(basename "$(git rev-parse --show-toplevel)")

if [[ "$worktree_dir" != *@* ]]; then
  echo "ERROR: worktree内ではありません（ディレクトリ名に @ が含まれていません）"
  exit 1
fi

worktree_branch="${worktree_dir#*@}"
current_branch=$(git rev-parse --abbrev-ref HEAD)

# メインブランチをorigin/HEADから取得
main_ref=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null || echo "")
if [[ -z "$main_ref" ]]; then
  echo "ERROR: origin/HEAD が設定されていません"
  echo "  git remote set-head origin --auto で設定してください"
  exit 1
fi
main_branch="${main_ref#refs/remotes/origin/}"

echo "=== Rebase Worktree ==="
echo "メインブランチ:     $main_branch"
echo "worktreeブランチ:   $worktree_branch"
echo "作業ブランチ:       $current_branch"
echo ""

# 未コミット変更があればstash
stashed=false
if ! git diff --quiet || ! git diff --cached --quiet; then
  echo ">> 未コミット変更をstash..."
  git stash
  stashed=true
fi

# fetch
echo ">> origin をfetch..."
git fetch origin

# worktreeブランチをメインブランチにリベース
if [[ "$current_branch" == "$worktree_branch" ]]; then
  # worktreeブランチ上にいる場合はそのままrebase
  echo ">> $worktree_branch を origin/$main_branch にrebase..."
  if ! git rebase "origin/$main_branch"; then
    echo ""
    echo "ERROR: rebaseでコンフリクトが発生しました"
    echo "  git rebase --continue  (コンフリクト解消後)"
    echo "  git rebase --abort     (中止)"
    [[ "$stashed" == true ]] && echo "  ※ stashあり: 解消後に git stash pop"
    exit 1
  fi
else
  # 作業ブランチ上にいる場合、まずworktreeブランチを更新してからリベース
  echo ">> $worktree_branch を origin/$main_branch に更新..."

  # worktreeブランチのリベースをdetachedで実行
  prev_worktree=$(git rev-parse "$worktree_branch")
  git checkout --quiet "$worktree_branch"
  if ! git rebase "origin/$main_branch"; then
    echo ""
    echo "ERROR: $worktree_branch のrebaseでコンフリクトが発生しました"
    echo "  git rebase --continue  (コンフリクト解消後)"
    echo "  git rebase --abort     (中止)"
    echo "  ※ 元のブランチ: $current_branch"
    [[ "$stashed" == true ]] && echo "  ※ stashあり: 解消後に git stash pop"
    exit 1
  fi

  git checkout --quiet "$current_branch"

  # 作業ブランチをworktreeブランチにリベース
  echo ">> $current_branch を $worktree_branch にrebase..."
  if ! git rebase "$worktree_branch"; then
    echo ""
    echo "ERROR: $current_branch のrebaseでコンフリクトが発生しました"
    echo "  git rebase --continue  (コンフリクト解消後)"
    echo "  git rebase --abort     (中止)"
    [[ "$stashed" == true ]] && echo "  ※ stashあり: 解消後に git stash pop"
    exit 1
  fi
fi

# worktreeブランチのリモート同期
worktree_upstream=$(git rev-parse --abbrev-ref "${worktree_branch}@{upstream}" 2>/dev/null || echo "")
if [[ -n "$worktree_upstream" ]]; then
  local_hash=$(git rev-parse "$worktree_branch")
  remote_hash=$(git rev-parse "$worktree_upstream" 2>/dev/null || echo "")
  if [[ "$local_hash" != "$remote_hash" ]]; then
    echo ">> $worktree_branch を $worktree_upstream に --force-with-lease でpush..."
    if ! git push --force-with-lease origin "$worktree_branch"; then
      echo ""
      echo "ERROR: リモートが更新されているためpushできませんでした"
      echo "  他の人がpushした可能性があります"
      echo "  git fetch origin && git log origin/$worktree_branch で確認してください"
      exit 1
    fi
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
