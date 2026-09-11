# Native wallet implementation and rollout

## Source relationships

| Native implementation | Existing SocketFi source |
| --- | --- |
| Wallet view and tokens | `socketfi-app/src/pages/socketfi-wallet/WalletScreen.tsx` |
| Receive address / deposit link | `socketfi-app/src/components/SendModal.tsx`, `PublicDepositPage.tsx` |
| Withdraw transfer arguments | `SendModal.tsx` → token `transfer(from, to, i128 amount)` |
| Swap quote and arguments | `AquariusSwapModal.tsx` → router `swap_chained(wallet, chain, tokenIn, u128 amount, u128 minimum)` |
| Token balances/prices | API `GET /api/wallet/tokens` |
| Project permissions | API `GET /.well-known/socketfi-projects/:clientId` |
| Quote | API `POST /api/aquarius-swap/quote` |
| Indexed history | API `GET /api/wallet/history` → account-indexer `/v1/wallets/:address/history` |
| Native signing | `/api/native/transactions/start`, `/api/tx/transaction-intents/init`, `/api/tx/transaction-intents/sign-and-submit` |

The Swift client owns only the address and integer ScVal encodings required by
these two operations. Fixtures in `SocketFiWalletTests` were generated with the
repository's Stellar JS SDK. Contract code, WASM, API endpoint schemas, hosted auth,
and Paktly's project permissions are unchanged. This adds no runtime dependencies.

## Deployment

Deploy the updated `socketfi-sdk/apps/api/configs/well-known-projects.json`.
The SocketFi iOS project permits TESTNET token `transfer` calls, including
custom assets, through a transfer-only contract wildcard. Other functions and
PUBLIC remain denied. Simulation, exact owner authorization, and contract
validation are unchanged.

The registry is loaded at startup. For the checked-in Docker Compose deployment,
rebuild the image and recreate the API service from the API deployment directory:

```sh
docker build -t socketfi-api .
docker compose up -d --no-deps --force-recreate socketfi-api
```

The project's paymaster must already exist and have adequate Testnet fee funds.
The current API does not return a pre-approval fee estimate; the UI states that
fees are handled by the project paymaster without claiming that they are zero.
No client secret belongs in the iOS app.

Swaps require the actual Aquarius Testnet router in the server environment as
`AQUARIUS_TESTNET_ROUTER_CONTRACT_ID`, a working Testnet liquidity route, and an
explicit registry rule for that same contract with `functions: ["swap_chained"]`
and `network: "TESTNET"`. Do not substitute the PUBLIC router or use a wildcard.
The live quote service returned HTTP 502 with that configuration missing during
the 2026-09-09 implementation check. No swap was signed or submitted.

PUBLIC remains unregistered. Enabling it requires a separate reviewed project,
bundle/client configuration, network-specific permissions, and release testing.

## Validation before release

Regenerate with `xcodegen generate` on macOS, then run the build/test commands in
`CONTRIBUTING.md`. The new GitHub Actions workflow runs simulator tests on PRs.
Simulator checks do not prove physical-device passkey or payment success.

Exercise these on a physical Testnet device:

1. Existing-session restore and fresh signup/signin; confirm balance lookup uses
   the internal username, not the project display name.
2. Empty funded/unfunded wallets, fresh balances, a missing price, RPC failure,
   offline refresh, expiry, and return from the background.
3. QR scanning and copying/sharing both the C address and deposit link. Complete
   a deposit on the public deposit page and pull to refresh the native balance.
4. XLM and USDC withdrawal to a supported G/C recipient; compare full address,
   exact amount and network in the review; verify confirmation and balance change.
5. Invalid checksum, same-account recipient, insufficient balance, excessive
   precision, missing trustline, and unavailable project permissions.
6. Passkey cancellation followed by retry, rapid double taps, expired review,
   network rejection, and a connection loss during submission. Unknown outcomes
   must remain unresolved after relaunch and must never trigger automatic retries.
7. Once configured, swaps in both directions, slippage limits, expired quote,
   minimum-output failure, and successful RPC confirmation. A new quote always
   requires a new review; it must never be silently accepted on the user's behalf.
8. VoiceOver, large Dynamic Type, light/dark mode, compact screens, decimal-pad
   input, scrolling with the keyboard, and sheet dismissal during signing.

Read APIs and prices are observational. API and smart-account authorization remain
authoritative; the client never grants itself permissions. Token lists remain the
existing watched-token list, not a claim to discover every asset on the account.
The portfolio USD total is an estimate derived from API market prices. The app
does not embed an indexer API key; account history uses the authenticated API
proxy below. Explorer links supplement indexed history.

## Transaction authority

EVM authentication saves the WalletConnect session topic and verified owner
address in the existing device-only Keychain session. A withdrawal reuses that
exact session and owner; it never opens the authentication catalogue or selects
another saved wallet. Legacy sessions without this binding require one fresh
sign-in. Passkey accounts continue to use the native passkey transaction flow.
Stellar signing is explicitly unavailable until its adapter is implemented.

## Indexed history deployment

Deploy the additive `socketfi-sdk` history route and configure these variables
in the API server environment (never in the iOS app or a `VITE_` variable):

- `SOCKETFI_HISTORY_API_URL`: account-indexer base URL reachable from the API
  container, without `/v1`; use HTTPS across untrusted networks.
- `SOCKETFI_HISTORY_API_KEY`: an active key from the indexer’s `APP_API_KEYS`.

The proxy calls `/v1/wallets/:address/history` with explicit network, limit, and
opaque cursor. It validates the login token, native registration, signed wallet
mapping, and current database account mapping. Only display metadata is returned;
raw indexed XDR, authorization entries, and upstream credentials are excluded.

The native Transactions tab refreshes on entry, pull-to-refresh, and foreground
return. Pagination preserves separate indexed events sharing the same hash,
retains loaded data on errors, and rejects cursor cycles and mismatched accounts
or networks. Amounts use exact strings; missing metadata stays visible without
inventing prices. Indexed status cannot resolve an uncertain submission by itself.

Validate after deployment with an existing Testnet login: history must show
indexed account events, load older pages when available, and open full details
and the correct network explorer. The opt-in physical-device test
`testLiveIndexedHistoryAndTransactionDetails` uses
`TEST_RUNNER_SOCKETFI_LIVE_HISTORY=1` with Xcode. The unavailable-service test is
intended for an undeployed/unconfigured proxy, not a healthy live history service.

Backend checks from `socketfi-sdk/apps/api`:

```sh
node --test test/well-known-projects.test.js test/project-username.test.js test/wallet-history.test.js
node scripts/generate-api-spec.js --check
```

No database migration, contract update, WASM artifact, or new dependency is
required. API deployment is required before real indexed history can load.
