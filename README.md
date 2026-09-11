<!-- Native account creation -->

Create account opens a dedicated username screen with an editable suggestion of
at most 16 characters. Spaces normalize to underscores. Validation follows the
API's 3–30 character username rules; availability is checked on Continue before
the passkey prompt. The supplied username becomes the passkey display identity;
the API retains its existing UUID-suffixed internal identity. This requires no
backend change. Test a taken username and retry with a new name on a device.

# SocketFi iOS

This is the native SwiftUI implementation of the SocketFi app. It is intentionally
separate from the React web app and from the customer integration reference.

Authentication is passkey-first and uses the existing native SocketFi
API protocol:

1. Start native auth.
2. Request WebAuthn options.
3. Perform registration/assertion with `AuthenticationServices`.
4. Verify with SocketFi, including the create-wallet proof when required.
5. Persist the session in a device-only Keychain item.
6. Restore the account on app launch.

Onboarding offers native passkeys and a WalletConnect EVM wallet catalogue.
Every EVM sign-in attempt permits a fresh wallet selection, including MetaMask
and Trust Wallet. The Stellar option remains visible with its availability stated.
Check compact phones, large text, dark mode, and keyboard presentation on device.

## Xcode setup

The repository includes an XcodeGen specification at `project.yml`. Generate an
iOS 17 application target from it, or include `Sources/SocketFiApp` and
`Sources/SocketFiNativeKit` in an equivalent Xcode target. The local
`SocketFiNativeKit` package can also be linked by customer applications.
Configure separate Testnet and Production
schemes with distinct values for:

- `SocketFiAPIBaseURL`
- `SocketFiClientID`
- `SocketFiApplicationID` (the bundle identifier)
- `SocketFiNetwork`
- `SocketFiRPID`

The entitlements enable `webcredentials:socket.fi`. Testnet uses the public
Console-generated project identifier `sf_client_live_e5fr319q79wpcojnx7s7zlhwu41w`, bundle ID
`fi.socket.socketfi.testnet`, and Apple team `GC29BX444D` (the same team as
Paktly). Client IDs are public identifiers, not secrets. Never commit client
secrets, production credentials, API keys or wallet secrets.

In Xcode, select the `SocketFi` target, choose your Apple Development Team under
Signing & Capabilities, and enable automatic signing. Your Apple account must
belong to the configured team and have provisioning access for
`fi.socket.socketfi.testnet`, with Associated Domains enabled.

The associated-domain file must be served by SocketFi at
`https://socket.fi/.well-known/apple-app-site-association` and include
`GC29BX444D.fi.socket.socketfi.testnet`. The example in `AssociatedDomains/`
contains only this app's entry; do not replace other apps' server entries.

Before device testing, deploy the SDK API's updated
`apps/api/configs/well-known-projects.json` and the marketing site's updated
`public/.well-known/apple-app-site-association`. Pushing source alone does not
confirm either deployment. Regenerate with `xcodegen generate`, open
`SocketFi.xcodeproj`, and run using the Testnet configuration. Reinstall the app
if iOS has cached an older domain association.

Production remains unregistered and its client ID remains a placeholder. The
Testnet registration enables native sign-in/sign-up and, after deploying the
wallet registry update, transfers on Testnet token contracts, including custom assets. The wildcard
permits only `transfer`; signature verification, simulation, and contract
authorization still apply. Swap routers and PUBLIC access require separate
explicit registration. No contract changes are required.

The package currently targets iOS 17 because it depends on AuthenticationServices,
UIKit presentation anchors and Swift concurrency. Build and test it on a real
device for passkey registration and assertion; simulator-only validation is not
sufficient.

## Passkey regression checks

Native authentication validates the server RP ID against the app configuration,
rejects incomplete challenges, and serializes authentication attempts. Cancelled
Apple callbacks cannot complete a later request. API encoding and decoding stay
on the main actor, with network I/O suspended asynchronously.

Keychain sessions are scoped to application, project, network, and RP ID. Users
with sessions stored by older builds must sign in once after this update.
No API migration or hosted-auth change is required by these client fixes.

Run the tests described in CONTRIBUTING.md on macOS. On a physical device verify
new-account registration and wallet proof, returning-user sign-in, cancellation
at both Apple prompts followed by retry, and relaunch/session restoration.
Apple SDK compilation and physical-device validation cannot run on Linux.

## Wallet

The wallet uses the web application's slate/indigo styling with live watched-token
balances, estimated USD values, pull-to-refresh, a balance privacy toggle, and
token contract details. Missing prices or balances appear as unavailable, not zero.
The existing access token supplies the internal username for balance lookup;
reading that claim is metadata handling, not an authorization decision.

Deposit and account details provide QR codes, copy/share actions, and the same
network-specific public deposit page as `socketfi-app`. Depositing from another
wallet happens on that page; the native app does not hold the sending wallet's keys.
Withdrawals accept checksum-validated Stellar G/C addresses. Memo-dependent
exchange deposits are unsupported and require a different receiving route.

Withdrawal and Aquarius swap requests use exact atomic strings, explicit review,
the account’s sign-in authority, and the API’s contract/function allowlist.
Passkey accounts use native passkey authorization. EVM accounts use the exact
WalletConnect session and owner saved at sign-in, with no transaction wallet
picker. Expired, disconnected, changed-account, and older unbound sessions
require a fresh sign-in. A swap review includes input, estimated output, minimum received,
slippage, network, token/router contracts, and quote expiry. A successful HTTP
response alone is insufficient: only a valid transaction hash and RPC `SUCCESS`
are shown as confirmed. No automatic financial retries occur. Unknown submission
outcomes are remembered per project/account/network across relaunch and require
the user to check activity before initiating another payment.

Deployment and validation requirements are in [docs/wallet.md](docs/wallet.md).
The wallet is implemented but is not release-certified until the macOS build,
tests, physical-device signing, and Testnet transaction checks pass.

Transaction history loads through the authenticated API proxy described in
[docs/wallet.md](docs/wallet.md). Indexed events use cursor pagination, exact
atomic amounts, account/network validation, and network-specific explorer links.
The indexer key is server-only. No indexed activity and an unavailable service
are distinct states.
