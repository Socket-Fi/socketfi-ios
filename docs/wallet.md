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
| Native signing | `/api/native/transactions/start`, `/api/tx/transaction-intents/init`, `/api/tx/transaction-intents/sign-and-submit` |

The Swift client owns only the address and integer ScVal encodings required by
these two operations. Fixtures in `SocketFiWalletTests` were generated with the
repository's Stellar JS SDK. Contract code, WASM, API endpoint schemas, hosted auth,
and Paktly's project permissions are unchanged. This adds no runtime dependencies.

## Deployment

Deploy the updated `socketfi-sdk/apps/api/configs/well-known-projects.json`.
The SocketFi iOS project gains only `transfer` on these Testnet token contracts:

- XLM: `CDLZFC3SYJYDZT7K67VZ75HPJVIEUVNIXF47ZG2FB2RMQQVU2HHGCYSC`
- USDC: `CBIELTK6YBZJU5UP2WWQEUCYKLPU6AUNZ2BQ4WWFEIE3USCIHMXQDAMA`

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
does not embed an indexer API key; account history currently opens the explorer.

## Validation in the Linux workspace

- `node --test test/well-known-projects.test.js test/project-username.test.js`
  in the SDK API: passed.
- `node scripts/generate-api-spec.js` and the corresponding `--check`: passed
  after refreshing the registry documentation and source digest.
- `pnpm --filter @socketfi/api test:direct-integration`: stopped by pnpm's
  existing ignored-build policy for esbuild/scarf; the exact underlying Node test
  command above passed. The incidental pnpm workspace edit was removed.
- Swift/Xcode compilation and XCTest execution could not run here: neither
  Xcode nor a Swift compiler is installed. The tests are added, not claimed passed.
- No transactions, deployments, commits, or pushes were performed.
