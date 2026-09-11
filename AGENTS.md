# SocketFi Workspace Instructions

## Scope and precedence

This directory is a workspace containing several independent SocketFi repositories. It is not a single buildable monorepo and does not currently have a usable root Git worktree. Run package-manager, build, test, and Git commands from the repository they belong to.

These instructions apply throughout the workspace. Read a repository's own `AGENTS.md` before changing files there; the closest `AGENTS.md` takes precedence when it is more specific. At audit time, additional instructions exist in:

- `socketfi-app/AGENTS.md`
- `socketfi-sdk/AGENTS.md`

## SocketFi project context

Before architecture-level changes or work spanning multiple repositories, read
`SOCKETFI_CONTEXT.md`. It records the product model, smart-account architecture,
security invariants, authentication and recovery design, SDK/API boundaries,
network model, automation context, and historical implementation decisions.

Current repository code, tests, and deployment configuration remain authoritative
when they conflict with historical notes in that file.

Do not edit `.agents/` or `.codex/` as application source. They are workspace tooling directories and were empty at the time of this audit.

## Product and trust model

SocketFi is Stellar/Soroban smart-account infrastructure. The repositories collectively contain contracts, hosted authentication and API services, published SDKs, the wallet/DeFi application, an account-history indexer, an integration example, a developer console and its API, and the public marketing site.

Preserve these invariants across every repository:

- Authentication is not transaction authorization. A valid login, token, wallet connection, or signature does not by itself permit an arbitrary account action.
- The Soroban account contract is the final authorization boundary. Client and server checks supplement it; they do not replace it.
- Keep TESTNET and PUBLIC configuration, contract IDs, RPC/Horizon endpoints, caches, signatures, and persisted data explicitly separated. Fail closed for unknown networks.
- Bind signed challenges and delegated policies to the exact operation, account, network, nonce, expiry, and relevant origin/client. Preserve replay protection and session epochs.
- Never weaken WebAuthn origin/RP-ID/challenge validation, Stellar ed25519 verification, EVM secp256k1 recovery, BLS proof-of-possession, guardian quorum, callback allowlists, or CORS policy for convenience.
- Use atomic integer strings, `bigint`, or an established decimal library for token amounts and fees. Do not use JavaScript floating point for authoritative financial arithmetic.
- Simulate and assemble Soroban transactions before signing; do not mutate an assembled transaction after signing. Do not report success until the authoritative RPC confirms it.
- Never submit, deploy, fund, migrate, rotate keys/signers, publish packages, or exercise PUBLIC-network state unless the user explicitly requests that external action.

## Workspace map

| Path | Role | Tooling |
| --- | --- | --- |
| `socketfi-smart-account/` | Rust `no_std` Soroban account, factory, access, shared crypto/types, and upgrade-governance code | Cargo/Soroban Makefiles, but Cargo manifests are absent in this checkout |
| `socketfi-sdk/` | pnpm workspace: hosted auth, CommonJS API, and published React, React Native, and server SDKs | pnpm |
| `socketfi-app/` | Main React 18/TypeScript wallet and DeFi application | pnpm, Vite, ESLint |
| `socketfi-account-indexer/` | Express/Prisma/PostgreSQL dual-network account history and metrics service | README documents npm; both npm and pnpm lockfiles exist |
| `socketfi-react-integration-reference/` | React 19 client plus Express example consuming published SocketFi SDK packages | npm workspaces |
| `socketfi-web/` | Public React 18/TypeScript marketing, developer, security, and legal site | npm, Vite, ESLint |
| `socketfi-web/socketfi-dev-portal-web/` | Independent React 18 developer console for accounts, projects, origins, credentials, and paymasters | npm, Vite, ESLint |
| `socketfi-web/socketfi-dev-portal-server/` | Independent Express/TypeScript/Prisma API backing the developer console | npm, PostgreSQL, Prisma, ESLint |

The two developer-portal repositories are nested physically under `socketfi-web/`, but each has its own `.git` directory and release history. They are not part of the marketing site's Vite build. Run Git and package commands from the exact repository being changed.

There is no root install, test, lint, or build command. Never run one package manager across all eight repositories.

## Standard workflow

1. Identify the owning repository and read its README, manifest, config, closest `AGENTS.md`, relevant source, and tests.
2. Run `git -C <repository> status --short` before editing. Each child repository has independent history, and existing modifications belong to the user.
3. Trace cross-repository consumers before changing an endpoint, contract interface/event, public SDK export, storage format, environment variable, network default, or error shape.
4. Make the smallest coherent change. Do not opportunistically clean up copies, backups, generated assets, lockfiles, or neighboring repositories.
5. Add or update focused tests when a harness exists. If no harness exists, say so and use the narrowest available static/build check.
6. Run validation from the affected repository/package. Report exactly what ran and distinguish pre-existing failures from regressions.
7. Review the repository-local diff and status. Do not claim workspace-wide validation when only one package was checked.

## Secrets, configuration, and generated files

- Treat all `.env` files, API keys, seed phrases, signer/paymaster secrets, passkey assertions, BLS material, JWTs, session secrets, signed XDR, and authorization entries as sensitive. Do not print them in commands, logs, diffs, fixtures, or summaries.
- Prefer `.env.example` and source-level variable names for configuration discovery. Some repositories currently contain tracked `.env` files; their presence is not permission to expose or duplicate their values.
- Any variable prefixed with `VITE_` is shipped to the browser. It cannot securely hold an indexer API key, application secret, signer secret, or other server credential. Route privileged calls through an authenticated backend instead of adding new browser secrets.
- Do not regenerate or replace checked-in WASM in `public/wasm/` as a side effect. A contract artifact update requires an explicit contract source/version and reproducible build provenance.
- Ignore `.git/`, `node_modules/`, `dist/`, `target/`, coverage output, `.expo/`, and other generated caches during source audits. Do not hand-edit them.
- Files and directories named `backup`, `* copy*`, `*-backup`, or `*-working-*` are not automatically active code. Trace imports and routing before using or changing them.
- Do not add or update dependencies unless required. Touch only the lockfile for the repository's selected package manager and never normalize multiple lockfiles incidentally.

## Cross-repository contracts

The usual dependency direction is:

```text
socketfi-smart-account
  -> socketfi-sdk API and published packages
  -> socketfi-dev-portal-server project registration/credential orchestration
  -> socketfi-app and socketfi-react-integration-reference
  -> socketfi-web links and public presentation

socketfi-dev-portal-web
  -> socketfi-dev-portal-server
  -> socketfi-sdk API paymaster/project registration boundary

factory/account events
  -> socketfi-account-indexer parsers and Prisma data
  -> app/web history and metrics consumers
```

When a boundary changes:

- Contract method, event, auth payload, or error changes require checking the SDK API, published package types, app calls, integration reference, indexer parsers, and relevant docs.
- API route or response changes require checking hosted auth, all three SDK packages, the main app, the integration server/client, generated API spec, and tests.
- Published SDK changes must preserve package exports and ESM/CJS behavior. The main app currently depends on published `@socketfi/react`; the integration reference depends on published `@socketfi/react` and `@socketfi/server`. Sibling source edits do not automatically affect those consumers unless deliberately linked or released.
- Network/contract/asset changes require checking every duplicated configuration location. Do not assume a sibling repository shares runtime configuration.
- Maintain backward compatibility by default. Prefer additive changes or an explicit deprecation/migration path for public endpoints, hooks, components, types, contract methods, events, and persisted schemas.

## Repository-specific guidance

### `socketfi-account-indexer/`

Purpose and layout:

- `src/index.ts` starts Express, Prisma, the wallet registry, and one worker each for TESTNET and PUBLIC.
- `src/api/` contains API-key middleware and history/metrics routes.
- `src/indexer/` parses factory events and transaction envelopes and drives ledger polling.
- `src/services/` owns RPC access, wallet discovery, token metadata, and DEX pricing.
- `src/config/` validates environment configuration and curated assets; `src/db/` owns the Prisma client.
- `prisma/schema.prisma` is the database source of truth; `prisma/migrations/` contains append-only migration history.

The README uses npm and `package-lock.json`, but a `pnpm-lock.yaml` is also present. Follow the documented npm flow for ordinary work and do not reconcile or regenerate the second lockfile unless dependency-management cleanup is explicitly in scope.

Useful commands:

```bash
cd socketfi-account-indexer
npm run lint
npm run build
npx prisma validate
npx prisma generate
```

Database commands such as `npm run db:migrate` and `npm run db:push` mutate configured state. Run them only when the task requires it and after confirming the target database. Do not edit an applied migration; add a new migration. Preserve cursor semantics, fee-bump and standard-envelope parsing, BigInt string serialization, API-key protection on `/v1`, and the unauthenticated `/health` endpoint. There is no automated test script in the manifest.

### `socketfi-app/`

This is the main Vite React/TypeScript product application. Read its local `AGENTS.md` first.

- `src/App.tsx` and `src/routes/` define navigation and access control.
- `src/context/StatesContext.tsx` carries broad wallet/application state.
- `src/pages/` contains wallet, DeFi, sessions, automations, settings, auth, and explorer flows.
- `src/components/` and `src/components/ui/` contain product and reusable UI.
- `src/client/` and `src/services/` contain API, CCTP, session/automation, and Soroban execution clients.
- `src/wallet-kit/`, `src/evm/`, and `src/storage/` own wallet adapters and browser persistence.
- `src/config/` and `src/utils/` contain tenant, network, contract, asset, and formatting configuration.
- `backup/` and files named `copy` or `.patch` are reference artifacts, not production entry points unless an import proves otherwise.

Use pnpm only:

```bash
cd socketfi-app
pnpm typecheck
pnpm lint
pnpm build
```

The current `tsconfig.json` has `strict: false`; preserve compatibility and improve types locally, but do not claim repository-wide strict mode. Avoid transaction side effects during render, clean up listeners, handle popup/redirect cancellation, and keep visible network/action/amount details in approval flows. No test script is defined.

### `socketfi-react-integration-reference/`

This npm-workspace example intentionally shows an end-to-end integration:

- `client/src/` is a React/Vite UI using `@socketfi/react` for authentication and transfers.
- `server/index.js` uses `@socketfi/server`, holds the paymaster, prepares/submits signed transactions, polls RPC confirmation, and exposes testnet Friendbot support.
- `docs/` contains README media only.

Use npm from the repository root:

```bash
cd socketfi-react-integration-reference
npm install
npm run dev
```

There are no lint, test, or production-build scripts. Do not invent a passing validation command. Keep paymaster and application secrets server-only, validate backend transaction inputs against an application allowlist, and do not broaden permissive example CORS without explaining the trust impact. Friendbot is TESTNET-only. Changes to the example should remain clear and minimal rather than introducing production framework complexity.

### `socketfi-sdk/`

Read the extensive local `AGENTS.md`; it contains the detailed auth, policy, transaction, financial, API, logging, testing, and release rules for this repository.

Active pnpm workspace members are only `apps/*` and `packages/*`:

- `apps/auth/`: Vite React hosted OAuth/passkey and transaction-approval UI.
- `apps/api/`: CommonJS Express/Mongoose/Redis API, Swagger, auth, smart-account, paymaster, CCTP, NEAR, Aquarius, Blend, session, automation, and deposit routes.
- `packages/react/`: published browser React SDK.
- `packages/react-native/`: published React Native/Expo SDK.
- `packages/server/`: published TypeScript server SDK.
- `docs/` and `projects/`: API audit/spec documentation.

`apps-functional-cctp/` contains large parallel copies of the API/auth code and is excluded from `pnpm-workspace.yaml`. Treat it as an experimental/archive tree. Do not mirror changes into or out of it unless the task explicitly names it and the differences have been reviewed. Likewise, inspect `* copy*.js` files but do not treat them as canonical runtime modules without import evidence.

Use pnpm from `socketfi-sdk/` and scope validation:

```bash
pnpm --filter @socketfi/auth lint
pnpm --filter @socketfi/auth build
pnpm --filter @socketfi/react typecheck
pnpm --filter @socketfi/react build
pnpm --filter @socketfi/react-native typecheck
pnpm --filter @socketfi/react-native build
pnpm --filter @socketfi/server typecheck
pnpm --filter @socketfi/server build
pnpm --filter @socketfi/api test:direct-integration
pnpm --filter @socketfi/api docs:api:check
```

The root `build:api` script delegates to an API `build` script that does not exist; do not use it as validation until the manifests are corrected. The API's direct-integration test is currently the only explicit test script. `docs:api` rewrites `projects/socketfi-api-spec.md`; use `docs:api:check` for non-mutating validation.

Before changing package exports, test both intended import modes and inspect the packed contents. Publishing is an external/destructive action and requires explicit approval. Keep hosted-auth callback/origin validation and API project allowlisting aligned.

### `socketfi-smart-account/`

This repository contains five `#![no_std]` Soroban Rust trees:

- `account/`: custom-account auth, signer rotation, guardians, recovery, session policy, migration, and validation.
- `factory/`: deterministic deployment, creation proof validation, registry, and approved implementation state.
- `shared/`: errors, events, key/auth types, BLS and WebAuthn helpers, constants, and TTL utilities.
- `upgrade/`: voter snapshots, proposal storage, voting, cancellation, and execution.
- `access/`: access-control contract/module.

Every contract directory has a Makefile with `build`, `test`, `fmt`, and `clean` targets, but no `Cargo.toml` or `Cargo.lock` exists anywhere in this checkout. `cargo metadata` therefore fails. Do not report contract builds/tests as available until the intended manifests/workspace configuration are restored or supplied. Once available, run checks from each affected contract directory, typically:

```bash
make fmt
make test
```

Contract changes require adversarial tests for authorization failure, replay, expiry/ledger boundaries, pause/recovery, signer and session-epoch invalidation, guardian uniqueness/quorum, upgrade voter snapshots, TTL behavior, and cross-network/domain separation. Preserve `no_std`, stable error discriminants, event formats, storage keys, deterministic serialization, and explicit authorization. Do not regenerate public WASM elsewhere without a reproducible release task.

### `socketfi-web/`

This npm/Vite React site owns public product content:

- `src/pages/HomePage.tsx` presents the embedded infrastructure and SocketFi App product model.
- `src/pages/DevelopersPage.tsx` explains SDK integration, the reference app, and the developer console.
- `src/pages/SecurityPage.tsx` presents the public trust and authorization model.
- `src/pages/LegalPage.tsx` owns privacy and terms content; it requires qualified legal review before launch.
- `src/components/SiteLayout.tsx` owns shared navigation/footer and public CTAs.
- `src/config/site.ts` is the source of truth for public app, console, documentation, repository, and package links.

Use npm:

```bash
cd socketfi-web
npm run typecheck
npm run lint
npm run build
```

There is no test script. Preserve public URLs, accessibility, responsive behavior, legal copy, and static deployment routing. Do not describe developer-console placeholders (usage analytics, global domains, organization settings, or OAuth providers) as available features until their implementation is verified.

### `socketfi-web/socketfi-dev-portal-web/`

This is an independent npm/Vite React console, despite being nested under `socketfi-web/`:

- `src/App.jsx` routes projects, project detail, usage, domains, settings, and legal pages.
- `src/pages/DevelopersPortalLayout.jsx` owns OTP authentication bootstrap and the authenticated dashboard shell.
- `src/lib/api.js` calls `VITE_API_URL`, defaulting to `https://console-api.socket.fi/api/v1`.
- `src/lib/auth.js` currently persists access and refresh tokens in `localStorage`.
- Project creation supports React and React Native, allowed origins, client credentials, and a project paymaster.
- Usage, domains, settings, Google OAuth, and GitHub OAuth are currently placeholders or disabled; the Advanced API route is commented out.

Use npm from this repository:

```bash
cd socketfi-web/socketfi-dev-portal-web
npm run lint
npm run build
```

There is no test or typecheck script and the source is JavaScript/JSX. Never log returned credentials or secrets. Treat changes to token storage, refresh behavior, credential display/rotation, allowed origins, and API base URL as security-sensitive. The repository contains checked-in WASM under `public/wasm/`; do not regenerate it incidentally.

### `socketfi-web/socketfi-dev-portal-server/`

This independent API owns developer-console data and orchestration:

- `src/routes/` exposes health, OTP/account, refresh/logout, project CRUD, archive, and credential-rotation routes under `/api/v1`.
- `src/services/account.service.ts` owns email OTP onboarding.
- `src/services/token.service.ts` owns short-lived JWT access tokens and opaque hashed refresh tokens.
- `src/services/project.service.ts` owns project/origin persistence, one-time client-secret issuance, rotation, and a call to the SDK API paymaster-creation endpoint.
- `prisma/schema.prisma` is authoritative for developer accounts, profiles, projects, origins, credentials, refresh tokens, OTPs, and audit logs.
- `src/config/env.ts` requires PostgreSQL and JWT configuration and controls CORS, OTP expiry, and SMTP.

Use npm; both npm and pnpm lockfiles exist, but the Dockerfile and README select npm:

```bash
cd socketfi-web/socketfi-dev-portal-server
npm run typecheck
npm run lint
npm run build
npx prisma validate
```

Do not run migrations, seed, or Docker Compose against an existing environment without confirming the database target. Do not print OTPs, raw client secrets, refresh tokens, SMTP credentials, or JWT material. Project records currently do not carry an explicit PUBLIC/TESTNET field; do not assume network separation exists. Paymaster provisioning crosses into `https://api.socket.fi` by default and must be authenticated, idempotent, network-bound, and reconciled before this flow is considered production-safe. Treat the current HS256-style shared-secret access JWT as portal-local authentication, not the SDK platform's historical RS256/JWKS customer-verification design.

## Validation and completion report

Choose the smallest relevant validation set from the sections above. Networked integration checks may require services and credentials; never substitute production credentials or PUBLIC state just to make a check pass. If dependencies are missing, do not install or rewrite lockfiles unless installation is within scope.

At completion, report:

- repositories and files changed;
- behavior and security/trust-boundary impact;
- public API, contract, schema, environment, migration, artifact, or release implications;
- exact lint, typecheck, test, build, and documentation commands run and their results;
- checks not run and why;
- remaining risks or follow-up work.
