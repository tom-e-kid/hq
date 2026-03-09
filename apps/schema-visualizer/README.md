# Schema Visualizer

`schema.yaml` をパースしてインタラクティブな ER 図を描画するスタンドアロン React アプリ。

## 起動

```bash
cd apps/schema-visualizer
bun install
bun run dev
```

デフォルトで `docs/schema.yaml` を読み込む。`?schema=` クエリパラメータで別ファイルを指定可能。

```
http://localhost:5173/                    → docs/schema.yaml
http://localhost:5173/?schema=schema.example.yaml → apps/schema-visualizer/schema.example.yaml
```

YAML ファイルの検索順: `apps/schema-visualizer/` → `docs/` → `SCHEMA_DIR`（Vite カスタムミドルウェア）。

外部プロジェクトの YAML を読み込む場合は `SCHEMA_DIR` 環境変数でディレクトリを指定する:

```bash
SCHEMA_DIR=~/dev/src/github.com/tom-e-kid/chunk/docs bun run dev
# → http://localhost:5173/?schema=schema-20260309-164352.yaml
```

## 操作

- **テーブルをクリック** — 関連テーブル・リレーションを強調（再クリックで解除）
- **ホイールスクロール** — ズーム（カーソル中心）
- **ドラッグ** — パン
- **カテゴリボタン** — フィルタ表示

## Input 仕様 — `chunk-schema/v1`

ビジュアライザは以下のフォーマットに準拠した YAML ファイルを入力とする。

### トップレベル

```yaml
format: chunk-schema/v1 # 必須。フォーマット識別子
database: postgresql # 必須。データベース種別

categories: [...] # 必須。カテゴリ定義の配列
tables: [...] # 必須。テーブル定義の配列
relations: [...] # 必須。リレーション定義の配列
```

### categories

テーブルのグルーピング。ビジュアライザは配列順にカラム（列）を割り当てる。

```yaml
categories:
  - id: AU # 必須。一意な短縮 ID（ビジュアライザの色分け・レイアウトに使用）
    label: Auth # 必須。表示名
    description: 認証基盤 # 必須。説明文
```

### tables

```yaml
tables:
  - id: AU-01 # 必須。"カテゴリID-連番" 形式（表示用）
    name: user # 必須。テーブル名（relations での参照キー）
    category: AU # 必須。所属カテゴリ ID
    columns: [...] # 必須。カラム定義の配列
    pk: [col1, col2] # 任意。複合 PK（単一 PK はカラムレベルで指定）
    unique: # 任意。複合 UNIQUE 制約
      - [col1, col2]
    indexes: # 任意。インデックス
      - columns: [col1]
    foreign_keys: # 任意。複合 FK（単一 FK はカラムレベルで指定）
      - columns: [col1, col2]
        references: { table: target, columns: [ref1, ref2] }
        on_delete: CASCADE
```

### columns

```yaml
columns:
  - name: id # 必須。カラム名
    type: text # 必須。データ型（text, integer, boolean, timestamp, jsonb）
    pk: true # 任意。主キー（デフォルト: false）
    unique: true # 任意。UNIQUE 制約（デフォルト: false）
    nullable: true # 任意。NULL 許可（デフォルト: false = NOT NULL）
    default: uuid_auto # 任意。デフォルト値（uuid_auto, now, リテラル）
    fk: # 任意。単一カラム FK
      table: user #   参照先テーブル名
      column: id #   参照先カラム名
      on_delete: CASCADE #   削除時動作（CASCADE / SET_NULL）
```

ビジュアライザでのカラム表示:

| 条件           | ドットインジケータ色 |
| -------------- | -------------------- |
| `pk: true`     | 黄 (`#fbbf24`)       |
| `fk` あり      | 青 (`#38bdf8`)       |
| `unique: true` | 紫 (`#a78bfa`)       |
| `type: jsonb`  | 緑 (`#4ade80`)       |
| その他         | 暗色 (`#1e3050`)     |

### relations

テーブル間のリレーション。ビジュアライザのエッジ描画に使用。

```yaml
relations:
  - from: account # 必須。FK を持つ側のテーブル名
    to: user # 必須。参照先テーブル名
    type: CASCADE # 必須。CASCADE = カテゴリ色実線、SET_NULL = グレー破線
    composite: true # 任意。複合 FK の場合 true
    column: invited_by # 任意。同一テーブル間に複数 FK がある場合の特定用
```

### 規約まとめ

| 項目   | 単一                                        | 複合                                       |
| ------ | ------------------------------------------- | ------------------------------------------ |
| PK     | カラムに `pk: true`                         | テーブルに `pk: [col1, col2]`              |
| FK     | カラムに `fk: { table, column, on_delete }` | テーブルに `foreign_keys: [...]`           |
| UNIQUE | カラムに `unique: true`                     | テーブルに `unique: [[col1, col2]]`        |
| INDEX  | —                                           | テーブルに `indexes: [{ columns: [col] }]` |

- `nullable` はデフォルト NOT NULL。NULL 許可の場合のみ `nullable: true` を明示
- `default` の特殊値: `uuid_auto`（自動 UUID 生成）、`now`（現在時刻）
