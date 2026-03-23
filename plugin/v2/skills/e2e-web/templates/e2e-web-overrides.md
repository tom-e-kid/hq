# e2e-web Overrides

## Dev Server

<!-- How to start the dev server on the agent port (4321).
     Examples:
       bun run dev --port 4321
       PORT=4321 npm run dev
       AUTH_URL=http://localhost:4321 bun run dev --port 4321
-->

```bash
<dev server command>
```

## DB Preparation

<!-- Idempotent command to prepare test data. "none" if no DB.
     Examples:
       cd apps/web && bun run db:seed test@example.com test-org test-project
       npx prisma db seed
-->

```bash
<seed command or "none">
```

## Authentication

<!-- Test credentials and login method. "none" if public app.
     Examples:
       | Setting   | Value              |
       |-----------|---------------------|
       | Email     | test@example.com   |
       | Password  | test1234           |
       | Method    | email + magic link |
-->

<credentials or "none">
