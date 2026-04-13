#!/bin/bash
set -euo pipefail

# Worktreeを新規作成し、ローカルファイルをセットアップする。
#
# Usage:
#   worktree-setup.sh <base-branch> [--branch <new-branch>] [--from <source-dir>]
#
# 前提: git リポジトリ内（メインまたはworktree）から実行すること

# === 引数パース ===

usage() {
  echo "Usage: $(basename "$0") <base-branch> [--branch <new-branch>] [--from <source-dir>]"
  echo ""
  echo "  <base-branch>          worktreeのベースブランチ（ディレクトリ名の@以降）"
  echo "  --branch <name>        ベースから派生する新規ブランチ名"
  echo "  --from <path>          ファイルコピー元ディレクトリ（デフォルト: メインリポ）"
  exit 1
}

if [[ $# -lt 1 ]]; then
  usage
fi

base_branch="$1"
shift

new_branch=""
source_dir=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --branch)
      new_branch="$2"
      shift 2
      ;;
    --from)
      source_dir="$2"
      shift 2
      ;;
    *)
      echo "ERROR: 不明なオプション: $1"
      usage
      ;;
  esac
done

# === メインリポの特定 ===

git_common_dir=$(cd "$(git rev-parse --git-common-dir)" && pwd)

# .git/worktrees/xxx の場合は .git の親がメインリポ
if [[ "$git_common_dir" == */.git ]]; then
  main_repo=$(dirname "$git_common_dir")
else
  # メインリポの .git ディレクトリそのもの
  main_repo=$(dirname "$git_common_dir")
fi

repo_name=$(basename "$main_repo")
parent_dir=$(dirname "$main_repo")

# === source_dir のデフォルト解決 ===

if [[ -z "$source_dir" ]]; then
  source_dir="$main_repo"
fi

if [[ ! -d "$source_dir" ]]; then
  echo "ERROR: コピー元ディレクトリが存在しません: $source_dir"
  exit 1
fi

# === worktreeディレクトリ名の決定 ===

if [[ -n "$new_branch" ]]; then
  worktree_dir="${parent_dir}/${repo_name}@${new_branch}"
else
  worktree_dir="${parent_dir}/${repo_name}@${base_branch}"
fi

echo "=== Worktree Setup ==="
echo "メインリポ:     $main_repo"
echo "ベースブランチ: $base_branch"
if [[ -n "$new_branch" ]]; then
  echo "新規ブランチ:   $new_branch"
fi
echo "コピー元:       $source_dir"
echo "作成先:         $worktree_dir"
echo ""

# === 事前チェック ===

if [[ -d "$worktree_dir" ]]; then
  echo "ERROR: 既にディレクトリが存在します: $worktree_dir"
  exit 1
fi

# === ブランチの存在確認とworktree作成 ===

if [[ -n "$new_branch" ]]; then
  # 新規ブランチモード
  # ベースブランチがローカルになければリモートから取得
  if ! git show-ref --verify --quiet "refs/heads/$base_branch"; then
    echo ">> ローカルにブランチがないため、リモートからfetch..."
    if git ls-remote --exit-code --heads origin "$base_branch" >/dev/null 2>&1; then
      git fetch origin "$base_branch"
      git branch "$base_branch" "origin/$base_branch"
    else
      echo "ERROR: ブランチ '$base_branch' がローカルにもリモートにも見つかりません"
      exit 1
    fi
  fi
  echo ">> worktreeを作成 (新規ブランチ: $new_branch from $base_branch)..."
  git worktree add -b "$new_branch" "$worktree_dir" "$base_branch"
else
  # 既存ブランチモード
  if git show-ref --verify --quiet "refs/heads/$base_branch"; then
    echo ">> worktreeを作成 (ローカルブランチ: $base_branch)..."
    git worktree add "$worktree_dir" "$base_branch"
  elif git ls-remote --exit-code --heads origin "$base_branch" >/dev/null 2>&1; then
    echo ">> リモートブランチからworktreeを作成..."
    git fetch origin "$base_branch"
    git worktree add --track -b "$base_branch" "$worktree_dir" "origin/$base_branch"
  else
    echo "ERROR: ブランチ '$base_branch' がローカルにもリモートにも見つかりません"
    exit 1
  fi
fi

# === ファイルコピー ===

echo ""
echo ">> 設定ファイルをコピー..."
copied_files=()

# .claude/settings.json
if [[ -f "$source_dir/.claude/settings.json" ]]; then
  mkdir -p "$worktree_dir/.claude"
  cp "$source_dir/.claude/settings.json" "$worktree_dir/.claude/settings.json"
  copied_files+=(".claude/settings.json")
fi

# .claude/rules/ (workflow.local.md など bootstrap で生成されるルール一式)
if [[ -d "$source_dir/.claude/rules" ]]; then
  mkdir -p "$worktree_dir/.claude"
  cp -R "$source_dir/.claude/rules" "$worktree_dir/.claude/rules"
  copied_files+=(".claude/rules/")
fi

# .hq/ プロジェクト上書きルール類
for hq_override in pr.md code-review.md xcodebuild-config.md; do
  if [[ -f "$source_dir/.hq/$hq_override" ]]; then
    mkdir -p "$worktree_dir/.hq"
    cp "$source_dir/.hq/$hq_override" "$worktree_dir/.hq/$hq_override"
    copied_files+=(".hq/$hq_override")
  fi
done

# .env* (monorepo対応: 全階層を検索してディレクトリ構造を保持)
while IFS= read -r -d '' env_file; do
  # ./path/.envrc → path/.envrc
  rel_path="${env_file#./}"
  target_dir=$(dirname "$worktree_dir/$rel_path")
  mkdir -p "$target_dir"
  cp "$source_dir/$rel_path" "$worktree_dir/$rel_path"
  copied_files+=("$rel_path")
done < <(cd "$source_dir" && find . -name '.env*' \
  -not -path '*node_modules*' \
  -not -path '*/.git/*' \
  -not -path '*/.hq/*' \
  -not -path '*/vendor/*' \
  -not -path '*/build/*' \
  -not -name '.env.production*' \
  -not -name '.env.staging*' \
  -print0 2>/dev/null || true)

# === .hq/settings.json 生成 ===

default_branch=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/||' || echo "")
if [[ -n "$default_branch" && "$base_branch" != "$default_branch" ]]; then
  mkdir -p "$worktree_dir/.hq"
  # 既存の .hq/settings.json があればマージ、なければ新規作成
  if [[ -f "$worktree_dir/.hq/settings.json" ]]; then
    # 既にコピーされている場合、base_branchを追加
    tmp=$(mktemp)
    # 閉じ } を除去 → 末尾空行を除去 → 最終行にカンマ追加
    sed -e '$d' "$worktree_dir/.hq/settings.json" \
      | sed -e '/^[[:space:]]*$/d' -e '$s/$/,/' > "$tmp"
    echo "  \"base_branch\": \"$base_branch\"" >> "$tmp"
    echo "}" >> "$tmp"
    mv "$tmp" "$worktree_dir/.hq/settings.json"
  else
    echo "{\"base_branch\": \"$base_branch\"}" > "$worktree_dir/.hq/settings.json"
  fi
  copied_files+=(".hq/settings.json (base_branch: $base_branch)")
fi

# === 完了レポート ===

echo ""
echo "=== セットアップ完了 ==="
echo "Worktree: $worktree_dir"
echo ""

if [[ ${#copied_files[@]} -gt 0 ]]; then
  echo "コピー/生成したファイル:"
  for f in "${copied_files[@]}"; do
    echo "  $f"
  done
  echo ""
fi

echo "次のステップ:"
echo "  cd $worktree_dir"
echo "  claude  # Claude Codeを起動"
