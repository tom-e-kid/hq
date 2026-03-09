# schema-md: Drizzle schema.ts → docs/schema.md

Drizzle ORM の schema 定義ファイルを読み込み、構造化された DB スキーマドキュメントを生成する。

## 入出力

- **入力**: プロジェクト内の Drizzle schema 定義（`pgTable` 等を含む `.ts` ファイル）
- **出力**: `docs/schema.md`

まず Drizzle の schema 定義ファイルを特定する。典型的なパス:
- `src/db/schema.ts`（単一ファイル）
- `src/db/schema/*.ts`（分割構成）
- `apps/*/src/db/schema.ts`（モノレポ）

見つからない場合はユーザーに確認する。

## Step 1: スキーマ解析

schema 定義ファイルから以下を抽出する:

- テーブル名（`pgTable('table_name', ...)` の第1引数）
- カラム定義（名前、型、制約チェーン）
- PK（`.primaryKey()` / `primaryKey({ columns: [...] })`）
- FK（`.references(() => table.column, { onDelete: '...' })` / `foreignKey({ ... })`）
- UNIQUE（`.unique()` / `unique().on(...)`)
- INDEX（`index().on(...)`）
- DEFAULT（`.default(value)` / `.defaultNow()` / `.$defaultFn(...)`）

## Step 2: カテゴリ分類

全テーブルをドメイン的に意味のあるカテゴリにグルーピングする。

**分類の方針:**
- schema.ts 内のコメント区切り（`// --- xxx ---` 等）をヒントにする
- FK の依存関係グラフから、密結合なテーブル群をまとめる
- 共通パターン（同じ親テーブルへの FK、共通カラム構成）を持つテーブル群をまとめる
- 1カテゴリあたり 1〜10 テーブル程度が適切。多すぎれば分割、少なすぎれば統合を検討する

**各カテゴリに付与する属性:**
- **ID**: 英大文字 2 文字の短縮 ID（例: `AU`, `TN`, `MD`）。ドメインを端的に表す略語を選ぶ
- **ラベル**: 英語の短い名称（例: `Auth`, `Tenant`, `Master`）
- **説明**: 日本語の1行説明

## Step 3: テーブル ID 採番

各テーブルに `カテゴリID-連番` 形式の ID を振る（例: `AU-01`, `TN-02`）。

連番ルール:
- カテゴリ内で親テーブルを先、子テーブルを後にする（FK 依存順）
- 中間テーブルは両端のテーブルの後に配置する
- ゼロパディング 2 桁（01〜99）

## Step 4: docs/schema.md 生成

以下の固定フォーマットで出力する。

---

### 出力フォーマット

````markdown
# DB Schema

## 概要

（1〜2文でスキーマ全体を要約。テーブル総数、カテゴリ数、使用 ORM、DB を含める）

### テーブル ID 体系

各テーブルにはカテゴリプレフィックス + 連番の ID を付与し、議論・参照時の共通言語とする。

| プレフィックス | カテゴリ | テーブル数 | 説明 |
| --- | --- | --- | --- |
| XX | Label | N | 日本語説明 |
（全カテゴリ分の行）

## カテゴリ別テーブル一覧

| ID | テーブル名 | 概要 |
| --- | --- | --- |
| **XX - Label** | | |
| XX-01 | table_name | 日本語の簡潔な概要 |
（全テーブル分。カテゴリごとに太字ヘッダ行で区切る）

## 理解のポイント

（スキーマを読み解く上で重要な設計パターンを解説する。以下のような観点:）
（- ドメイン固有の構造やユニーク制約の意図）
（- 共通パターン（共通カラム構成を持つテーブル群 等））
（- マルチテナントやスコープ構造）
（- FK の on_delete 戦略の使い分け（CASCADE vs SET NULL の意図））
（※ テーブル ID を括弧で参照する。例: `chunk_type（MD-06）`）

## 各カテゴリ詳細

---

### XX - Label

（カテゴリの補足説明があれば1〜2行で記載）

#### XX-01: table_name

| カラム | 型 | 制約 |
| --- | --- | --- |
| column_name | type | 制約情報 |

- **PK**: `(col1, col2)`（複合 PK の場合）
- **UNIQUE**: `(col1, col2)`（複合 UNIQUE の場合）
- **INDEX**: `col1`（インデックスがある場合）
- 補足事項（設計意図の説明が必要な場合）

（カテゴリごとに `---` で区切る）

---

## リレーション図

```
parent_table (XX-01)
 ├─< child_table (XX-02)        fk_column → parent.id
 ├──○ nullable_ref (XX-03)      fk_column → parent.id   SET NULL
 └── required_ref (XX-04)       fk_column → parent.id   CASCADE
```

（主要な親テーブルを起点にツリーを構成する。全 FK 関係を網羅する）

凡例: ─< 1:N (CASCADE)  ──○ N:1 (SET NULL)  ── N:1 (CASCADE)
````

---

### 制約欄の表記規約

| schema.ts の記述 | 制約欄の表記 |
|---|---|
| `.primaryKey()` | `PK` |
| `.$defaultFn(() => crypto.randomUUID())` | `PK, UUID auto` |
| `.notNull()` | `NOT NULL` |
| （`.notNull()` なし、PK でもない） | （空欄 = nullable） |
| `.unique()` | `UNIQUE` |
| `.default(value)` | `DEFAULT value` |
| `.defaultNow()` | `DEFAULT now()` |
| `.$onUpdate(() => new Date())` | `auto update`（DEFAULT と併記） |
| `.references(() => t.id, { onDelete: 'cascade' })` | `FK → t(id) CASCADE` |
| `.references(() => t.id, { onDelete: 'set null' })` | `FK → t(id) SET NULL` |

NOT NULL + DEFAULT + FK 等が重なる場合はカンマ区切りで併記する。

### 日本語記述ルール

- テーブル概要・カテゴリ説明・理解のポイント: 日本語
- カラム制約: 英語略語（PK, FK, NOT NULL, UNIQUE, CASCADE, SET NULL, DEFAULT）
- 外部ライブラリ由来のテーブルがあれば公式ドキュメントへのリンクを補足する
