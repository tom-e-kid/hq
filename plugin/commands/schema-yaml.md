# schema-yaml: docs/schema-*.md → docs/schema-*.yaml

スキーマドキュメント（`.md`）をベースに、`chunk-schema/v1` 準拠の YAML を生成する。

## 入出力

- **入力**: 引数でファイルパスを指定可能。省略時は `docs/schema-YYYYMMDD-HHMMSS.md` のうち最新日時のファイルを自動選択する
- **出力**: 入力ファイルと同名で拡張子を `.yaml` に変えたファイル（例: `docs/schema-20260309-164352.md` → `docs/schema-20260309-164352.yaml`）

## 手順

1. 入力ファイルを特定する（引数指定 or `docs/schema-*.md` の最新）
2. 入力ファイルを読み込み、テーブル構造・リレーション情報を抽出する
3. `${CLAUDE_PLUGIN_ROOT}/apps/schema-visualizer/README.md` の「Input 仕様 — chunk-schema/v1」(L29-124) をフォーマット仕様として参照する
4. プロジェクト内の Drizzle schema 定義ファイルでカラムの nullable/default 等の詳細をクロスチェックする
5. `chunk-schema/v1` フォーマットに準拠した YAML を出力ファイルに上書き生成する

## フォーマット仕様の参照先

**`${CLAUDE_PLUGIN_ROOT}/apps/schema-visualizer/README.md` の L29-124 に定義された `chunk-schema/v1` 仕様に厳密に従うこと。**

仕様の要点（詳細は README.md を参照）:
- トップレベル: `format`, `database`, `categories`, `tables`, `relations`
- categories: `id`, `label`, `description`
- tables: `id`, `name`, `category`, `columns`, `pk`(複合), `unique`(複合), `indexes`, `foreign_keys`(複合)
- columns: `name`, `type`, `pk`, `unique`, `nullable`, `default`, `fk`
- relations: `from`, `to`, `type`, `composite`, `column`

## YAML 生成ルール

### nullable の判定

- schema.ts で `.notNull()` が付いていない AND PK でもないカラム → `nullable: true`
- `nullable` のデフォルトは NOT NULL（`false`）なので、NOT NULL のカラムには `nullable` を書かない

### default の判定

- `.$defaultFn(() => crypto.randomUUID())` → `default: uuid_auto`
- `.defaultNow()` → `default: now`
- `.default(値)` → `default: "値"` （文字列・数値・boolean をそのまま）

### FK の判定

- 単一カラム FK: `.references(() => table.column, { onDelete: 'xxx' })` → カラムレベル `fk:`
- 複合 FK: `foreignKey({ columns: [...], foreignColumns: [...] })` → テーブルレベル `foreign_keys:`
- `on_delete` の値: `cascade` → `CASCADE`, `set null` → `SET_NULL`

### PK の判定

- 単一 PK: `.primaryKey()` → カラムレベル `pk: true`
- 複合 PK: `primaryKey({ columns: [...] })` → テーブルレベル `pk: [col1, col2]`

### relations セクション

- 入力 .md のリレーション図と schema.ts の FK 定義の両方を照合して生成する
- 各 relation は FK を持つ側のテーブルが `from`、参照先が `to`
- `type`: `CASCADE` または `SET_NULL`
- 同一テーブル間に複数の FK がある場合は `column:` で特定する
- 複合 FK の場合は `composite: true` を付与する

## YAML スタイルガイド

- カテゴリごとにコメント区切りを入れる: `# ── AU - Auth ──────...`
- flow style の fk: `fk: { table: user, column: id, on_delete: CASCADE }`
- relations はコメントでグループ分け: `# AU → user`, `# TN → organization` 等
- インデントは 2 スペース

## 注意事項

- 入力 .md の情報が schema.ts と矛盾する場合は schema.ts を正とする
- 入力 .md に記載がないが schema.ts に存在するテーブル/カラムがあれば追加する
- indexes は schema.ts の `index().on(column)` から導出する（schema.md にない場合も schema.ts を参照）
