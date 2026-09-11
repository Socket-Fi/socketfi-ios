# SocketFi — Project Context & Codex Handoff

> Persistent engineering context for Codex CLI / IDE agents.
> Consolidated: 2026-08-28
> Repository code/tests/deployment config override historical notes here when they conflict.

## 0. Codex operating rules

Read this file before architecture-level work, plus root and nearest `AGENTS.md`.

- Inspect existing implementation before changing architecture.
- Never weaken authorization to make an integration/test pass.
- Preserve PUBLIC/TESTNET separation; never silently fall back across networks.
- Prefer backwards-compatible SDK/API changes.
- For contract changes, test success, unauthorized access, replay, malformed signatures/proofs, boundaries, state transitions, and regressions.
- Events/indexers are observational; on-chain state/authorization is authoritative.
- Distinguish owner authority from delegated/session authority.
- Verify historical proposals against current code before implementing them.

## 1. Product definition

SocketFi is **embedded smart-account infrastructure for Stellar/Soroban**. It lets fintech and consumer applications embed self-custodial programmable accounts without seed-phrase-first UX.

There are two product layers plus a supporting developer control plane:

1. **Infrastructure:** Soroban contracts, Factory, SDKs, hosted auth, API/orchestration, sessions, recovery, transaction preparation, indexer/history, automation.
2. **Consumer/reference app:** `socketfi.app`, which demonstrates and consumes the infrastructure through wallet/account UX, assets, deposits, transfers, DeFi, history, and automation.
3. **Developer control plane:** `console.socket.fi` and `console-api.socket.fi`, which onboard developers and manage application projects, allowed origins, client credentials, and project paymasters used to integrate the infrastructure.

The developer console supports the infrastructure product; it is not a third end-user product. The SDK/platform is the reusable product, and the consumer app is a direct user experience and reference consumer.

## 2. Core goals

- Passkey-first embedded account UX.
- Self-custodial authorization.
- Existing Stellar-wallet compatibility.
- EVM-wallet compatibility.
- Soroban-native custom-account authorization.
- Scoped delegation for repetitive/background actions without unrestricted authority.
- Recovery while preserving account address/assets.
- Application-friendly SDK/API abstractions.
- Explicit trust boundaries between client, SocketFi services, application backend, and smart account.

## 3. Smart-contract architecture

Canonical packages:

```text
Factory
Account
Shared
Upgrade
```

### Factory
- Deploy/initialize Account contracts.
- Deterministic deployment.
- Creation replay protection / canonical registration.
- Deployment configuration.
- Publish approved/latest Account WASM hash/version.

**Invariant:** Factory publication does not let Factory silently replace Account code. Adoption remains account-owner authorized.

### Account
Implements Soroban `CustomAccountInterface` / `__check_auth` and owns owner authentication, Soroban invocation authorization, scoped concurrent sessions, signer rotation, guardian-assisted recovery, emergency pause/unpause, guardian lifecycle, owner-authorized upgrades/migrations, and TTL/liveness management.

An Account has **one active owner signer method at a time**. Sessions are delegated authorities, not additional owners.

### Shared
Reusable interfaces, types/errors/events, authentication helpers, WebAuthn/P-256, Ed25519, secp256k1/EVM, BLS utilities, invocation/token helpers, hashing/serialization, storage and validation.

### Upgrade
Approved-WASM checks, authorization, versioning, migration guards, compatibility patterns and upgrade/migration events.

## 4. Owner signer model

| User method | Cryptography | Role |
|---|---|---|
| Passkey | P-256 / secp256r1 via WebAuthn | Passkey-first ownership |
| Stellar wallet | Ed25519 | Existing Stellar wallet controls Account |
| EVM wallet | secp256k1 | MetaMask/Rabby/etc. controls Account |

Proof of possession/control must be verified before installing a signer.

### Passkey
WebAuthn-compatible P-256. Validation includes RP-ID binding/hash and the WebAuthn-defined authentication data. Do not describe this merely as "signing SHA-256": WebAuthn constructs authenticator data plus client-data hashing and P-256 signs the defined bytes. Inspect current client/contract code for exact preimage representation.

### Stellar
Ed25519, not Ed448. The wallet signs the implemented Stellar/SocketFi authorization payload/preimage.

### EVM
secp256k1 with the implemented Ethereum-compatible signed-message hashing/domain behavior, recovery-ID validation and address recovery. Cryptographically this ownership is chain-independent unless application policy adds a chain constraint.

### Rotation
Signer rotation atomically replaces the owner signer and changes/increments the session epoch so old delegated authority cannot survive ownership change.

## 5. Soroban authorization

`CustomAccountInterface::__check_auth` must conceptually determine credential mode, verify signer/delegate, validate the authorization context/invocation tree, enforce pause state, distinguish owner vs session authority, enforce session constraints, verify the signature, atomically update usage/spend where required, and refresh appropriate TTL after successful use.

Frontend state, API assertions, events and indexer records never replace contract authorization.

## 6. Sessions / delegated authorization

Sessions provide narrowly scoped execution without repeated owner prompts. Multiple sessions may coexist; creating one must not revoke unrelated sessions.

Policy constraints may include delegate identity, allowed contracts/functions, assets, destinations, spend/value limits, usage limits, expiration ledger, and account session epoch.

Invalidation includes individual revocation, expiry, usage/spend exhaustion, global epoch invalidation, signer rotation, and recovery.

Conceptual policy hierarchy:
- global SocketFi safety constraints;
- project/application configuration;
- user/session grant.

The frontend must not invent unlimited authority beyond project/global bounds. Sessions must never authorize privileged account administration such as upgrades/migrations. Verify current code for the full sensitive-operation denylist.

Session events can be indexed for history/pagination/UI; on-chain policy state remains authoritative.

## 7. Guardian recovery / emergency protection

Recovery is separate from normal owner auth and uses guardian BLS public keys, guardian proof of possession, aggregate BLS recovery authority/key, a domain-separated recovery payload, aggregate BLS recovery signature, and proof of possession for the replacement owner signer.

Recovery must not require the lost/compromised current signer. Successful recovery preserves account address/assets, atomically installs the replacement signer, and globally invalidates prior sessions via epoch change.

Guardians support emergency pause and controlled unpause. Guardian removal/lifecycle has delay/protection concepts; inspect current implementation for exact thresholds/timing.

## 8. Upgrade model

1. Factory publishes approved Account WASM/version.
2. Account checks it.
3. Owner authorizes adoption.
4. Account updates WASM.
5. Versioned migration runs if needed.

Factory cannot silently replace auth logic; sessions cannot upgrade/migrate; storage stays compatible or is explicitly migrated.

## 9. TTL

Soroban TTL is part of protocol availability/security. Account instance state is refreshed on successful authorized activity according to implementation. Persistent/session/guardian records need deliberate TTL rules. Inspect current constants/tests before changing TTL values.

## 10. SDK / monorepo

Active work has used a pnpm-style workspace with `apps/*` and `packages/*`, historically under `socketfi-sdk-v3/socketfi-sdk`.

### `@socketfi/react`
Known frontend surface includes `useSocketFi()` and flows/APIs discussed or used such as authentication, `requestTransaction(...)`, and `readContract(...)`. API names have evolved: inspect current exports rather than assuming an old name.

### `@socketfi/server`
Backend direction/current usage includes local RS256 auth verification and transaction preparation/orchestration such as `verifyAuth(...)` and `prepareTransaction(...)`. Confirm actual current exports.

### React Native
`@socketfi/react-native` has been part of the intended mobile SDK surface. Verify current package completeness before relying on it.

## 11. Hosted authentication / BYOI

SocketFi supports hosted auth while remaining broadly auth-agnostic.

- Passkey is the native/core ownership path.
- Full/Light hosted-auth modes have been part of product design/implementation.
- RP-ID/domain binding is security-critical; `socket.fi` has historically been used for hosted passkey context.
- Apps may retain Google/GitHub/email/Auth0/etc.; SocketFi can map a stable external identity to a wallet.
- Hosted auth is optional.
- Managed/email/social onboarding should permit upgrade to a personal passkey and rotation out of a managed signer where applicable.

Keep **login authentication** separate from **transaction authorization**. A valid application login never implies unrestricted transaction authority.

### 11.1 Deferred web-direct passkey flow

Direct, same-page WebAuthn authentication and transaction authorization for the
browser-based `socketfi-app` is a future implementation. It is not part of the
currently supported native integration, which is limited to registered iOS and
Android applications, and it must not be enabled by representing a browser as a
native application.

The existing challenge, verification, smart-account creation, Soroban
transaction preparation, and signing pipeline should be reused. The future web
entry flow should be additive and isolated so existing hosted authentication and
iOS/Android native request contracts remain unchanged. Before implementation:

- decide the permanent application origin and RP ID; `socketfi.app` cannot use
  passkeys scoped to `socket.fi`, while a reviewed origin such as
  `app.socket.fi` can use `socket.fi` as its RP ID;
- add an explicit registered web-application model with exact origins,
  networks, RP IDs, and contract/function invocation allowlists;
- bind authorization to the request's validated HTTP `Origin`, rather than a
  caller-supplied project or origin value;
- retain Redis-backed, single-use, expiring flow state and exact
  account/network/operation binding;
- implement browser-native WebAuthn in the React SDK/application behind a
  controlled rollout, without removing hosted authentication; and
- add native regression coverage plus web tests for RP/origin mismatch,
  replay, expiry, network mismatch, unregistered projects, and disallowed
  invocations before TESTNET rollout.

The current Paktly iOS adapter is an architectural reference for the request
lifecycle, not evidence that browser support exists. Its native transaction
path also depends on a non-empty server-side invocation allowlist and verified
physical-device integration tests.

## 12. Server trust / JWT

Production architecture uses asymmetric signed assertions, especially RS256, so customer backends can verify SocketFi auth locally using public keys.

Validate signature, expiry, issuer/audience where implemented, project/tenant binding, identity/wallet binding and revocation/session semantics.

Historical design also explored transaction approval tokens asserting that a wallet approved a specific transaction/hash. Treat this as a design concept unless current code exposes it publicly.

Never expose server private signing keys to frontend packages.

## 13. API layer

The API orchestrates services; it does not replace smart-contract authorization. Responsibilities observed/discussed include hosted auth, account/session coordination, transaction preparation/direct flows, Blend integration, CCTP workers, automation, BLS/recovery coordination and network-specific RPC access.

Historical development default: `http://localhost:3200`, with envs such as `VITE_SOCKETFI_DIRECT_API_URL` / `VITE_SERVER_DIRECT_URL`. Development defaults are not production assumptions.

### 13.1 Developer console control plane

The workspace now includes two independent repositories nested under `socketfi-web/`:

- `socketfi-dev-portal-web`: the React console intended for `console.socket.fi`;
- `socketfi-dev-portal-server`: the Express/Prisma API intended for `console-api.socket.fi/api/v1`.

The current implemented console flow is email OTP authentication, developer profile onboarding, project creation/list/update/archive, exact allowed-origin storage, one-time client-secret display, client-secret rotation, complete client-key rotation, and project paymaster display. Project types are currently React or React Native.

The portal server persists developer accounts, profiles, projects, project origins, hashed client credentials, hashed opaque refresh tokens, OTP records, and audit logs in PostgreSQL. Creating a project also calls the core SocketFi API's paymaster-creation route and stores the returned public key. This makes project creation a cross-service transaction that needs authentication, idempotency, rollback/reconciliation, and explicit network binding.

Important current limitations to preserve in planning and public claims:

- usage analytics, global domain management, organization settings, and social OAuth are placeholders or disabled in the console UI;
- the Advanced API route is not active;
- project records have no explicit PUBLIC/TESTNET field;
- console access tokens are symmetric JWTs and are not the platform's historical RS256/JWKS customer-verification assertions;
- the browser currently stores both access and refresh tokens in `localStorage`;
- no automated test scripts exist in either portal repository.

Treat the portal as a control plane. A portal login or project credential does not itself authorize a smart-account transaction. Allowed origins and project credentials must align with hosted-auth/API allowlists, and all project/paymaster configuration must stay explicitly network-scoped before production use.

## 14. Consumer application / tenants

Known hosts:
- PUBLIC/mainnet: `socketfi.app`
- TESTNET: `testnet.socketfi.app`

Frontend tenant model:

```ts
type SocketFiNetwork = "PUBLIC" | "TESTNET";
type SocketFiTenant = {
  id: "mainnet" | "testnet";
  network: SocketFiNetwork;
  hostname: string;
  appName: string;
  apiUrl: string;
  explorerUrl: string;
};
```

Environment concepts include `VITE_MAINNET_HOST`, `VITE_TESTNET_HOST`, `VITE_SOCKETFI_DIRECT_API_URL`, and network-specific explorer config. Hostname determines tenant/network context; never cross PUBLIC and TESTNET implicitly.

Consumer capabilities include account creation/auth, all three signer modes, receive/deposit links/QR, balances/transfers, history, DeFi, session/account management and automation.

## 15. Automation

Publicly showcased strategies:
- Dollar-Cost Averaging (DCA)
- Portfolio Rebalancing
- Asset Distributions

Automation must execute through explicit bounded session authority, not a backend holding unrestricted owner power. Policies should cover intended contracts/functions/value/usage/expiry.

Historical work encountered Soroban `Auth, InvalidAction` during signed automation simulation. Diagnose preimage, invocation scope, policy and signature construction; never bypass authorization.

## 16. DeFi/integrations

Blend integration exists/has existed in the consumer/API. A historical runtime issue showed installed `@blend-capital/blend-sdk` lacked `Pool.load`; verify current dependency before assuming this remains unresolved.

CCTP worker/integration work has also existed. Third-party failures must remain isolated from core account authorization.

## 17. History indexer / Sorograph

Separate history/indexing infrastructure has included:
- `socketfi-history-indexer`;
- TypeScript/tsx;
- PostgreSQL + Prisma;
- development port `4015`;
- endpoint pattern `/v1/wallets/:address/transactions?network=TESTNET&limit=...&offset=...`;
- network-specific checkpoints;
- PUBLIC and TESTNET support.

Sorograph/RPC data is used for wallet history/metrics. Historical operational issues included RPC 504/AbortError and incomplete asset metadata. A PUBLIC checkpoint has been manually advanced to current ledger during recovery. Treat these as historical incidents, not permanent architecture.

Published wallet/user/transaction/raw-volume figures are snapshots and must never be hardcoded as current state.

## 18. Deposit routing concept

A prior architecture for exchange/centralized deposits used a server-side routing layer rather than only an SDK helper: API + SDK helpers + dashboard/webhooks, with an app-scoped Stellar `G...` router account and memo-based mapping to smart-account destinations.

Security requirements include validating project/router/memo/asset/destination, reconciliation/retries/indexing, and restricting forwarding. Verify implementation status before treating this as live functionality.

## 19. Security invariants

1. Exactly one active owner signer method.
2. New/replacement signers prove possession/control.
3. Authentication methods cannot be confused/substituted.
4. Sessions only exercise explicitly delegated authority.
5. Sessions cannot upgrade/migrate the Account.
6. Rotation invalidates old sessions globally.
7. Recovery invalidates old sessions globally.
8. Recovery requires valid aggregate BLS authorization plus replacement-signer proof.
9. Recovery does not require the lost current signer.
10. Factory cannot silently replace Account code.
11. Pause restrictions are enforced on-chain.
12. Events/indexers are never authorization sources.
13. Spend/usage accounting is atomic with authorized execution.
14. Expired/revoked/wrong-epoch sessions fail closed.
15. PUBLIC and TESTNET are explicitly separated.
16. Client-supplied project/policy data cannot grant authority beyond trusted bounds.
17. Server signing secrets never ship to clients.
18. Upgrade/migration preserves state compatibility or explicitly migrates it.
19. TTL changes cannot silently destroy critical account availability.
20. Integration failures are not solved by weakening account auth.

## 20. Testing expectations

For Account/Factory changes, use existing contract tests as the primary style reference. Cover as applicable:
- initialization and duplicate initialization;
- deterministic deployment/replay protection;
- each signer type;
- malformed/wrong signatures;
- signer proof-of-possession failure;
- wrong signer/type;
- WebAuthn RP-ID validation represented by implementation;
- EVM recovery ID/address mismatch;
- session allow/deny contract/function cases;
- spend/usage exact boundaries;
- expiry ledger boundaries;
- individual/global revocation;
- epoch invalidation after rotation/recovery;
- pause/unpause;
- guardian authorization/threshold/lifecycle;
- BLS recovery malformed/insufficient/wrong-domain proofs;
- replacement signer proof;
- forbidden session upgrades;
- approved/unapproved WASM;
- migration/version guards;
- TTL behavior where testable;
- replay of signed authorization material;
- atomicity on failed execution.

Never broaden production authorization merely to make tests pass.

## 21. Repository boundaries

SocketFi has adjacent consumers/integrations. Do not assume a file belongs to the core SDK merely because it references SocketFi. AutoLayer, for example, consumes SocketFi but is a separate product/repository.

Within the SDK workspace, `apps/api` has been a key server surface. Inspect the current tree before workspace-wide assumptions.

## 22. Product positioning

> **SocketFi is embedded smart-account infrastructure for Stellar, enabling applications to give users programmable self-custodial accounts controlled by passkeys, existing Stellar wallets, or EVM wallets, with scoped automation and recovery built in.**

The major product components are best described as **Infrastructure** and **Consumer Application / Reference App**, not two unrelated features.

## 23. Demo/ecosystem context

SocketFi V2 demonstrations emphasize:
- embedded smart-account infrastructure;
- SDK integration;
- passkey / Stellar / EVM account creation and management;
- automation strategies;
- consumer app as a demonstration of the infrastructure.

`ContributeFi` has also been used as a SocketFi ecosystem/application launch initiative. Do not conflate it with the core protocol.

## 24. Historical issues to re-check

- Blend SDK incompatibility around `Pool.load`.
- Indexer RPC 504 / abort failures.
- Partial/missing asset metadata.
- PUBLIC indexer checkpoint catch-up/reset.
- Signed automation simulation `Auth, InvalidAction`.
- SDK method naming/API evolution.

Reproduce against the current branch/dependencies before fixing.

## 25. Details requiring repository verification

Do not invent:
- exact package/version inventory;
- exact public SDK signatures;
- REST endpoint inventory;
- JWT claims/JWKS endpoints;
- exact hosted-auth Full/Light behavior;
- exact WebAuthn challenge/preimage serialization;
- exact Stellar authorization preimage;
- exact EVM prefix/domain construction;
- BLS curve/library/serialization details;
- guardian thresholds/removal delays;
- TTL constants;
- deployed Factory/Account IDs;
- current RPC URLs;
- automation policy schemas;
- DB schemas;
- production env names;
- current release versions.

## 26. Decision hierarchy

When sources conflict:
1. explicit current user instruction;
2. current repository code + tests + deployment/config;
3. nearest `AGENTS.md`;
4. root `AGENTS.md`;
5. this handoff's confirmed architecture/invariants;
6. historical proposals/notes.

If an apparent conflict affects authentication, recovery, session authority, upgrades, assets or production deployment, stop and inspect rather than guessing.

## 27. Recommended root `AGENTS.md` pointer

Add this near the top of the root `AGENTS.md` if it is not already present:

```md
## SocketFi project context

Before architecture-level changes or work spanning multiple packages/apps, read
`SOCKETFI_CONTEXT.md`. It contains the cross-workspace product architecture,
smart-account security invariants, authentication model, SDK/API boundaries,
network model, automation context, and historical implementation decisions.

Repository code and tests remain authoritative when they conflict with historical
notes in that file.
```

## 28. Source basis for this handoff

This document consolidates long-running SocketFi project discussions plus previously uploaded SocketFi technical material, including the protocol README, Account contract README, threat model, SDK/API/auth discussions, consumer code excerpts, indexer logs, and integration/debugging history.

It intentionally labels uncertain or historically proposed behavior instead of presenting it as current implementation.

---

**Codex reminder:** understand the existing flow first. SocketFi controls assets through a Soroban custom account. Authentication, sessions, recovery and upgrades are security boundaries. Do not simplify those boundaries without an explicit protocol-level decision.
