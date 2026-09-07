# SocketFi iOS

This is the native SwiftUI implementation of the SocketFi app. It is intentionally
separate from the React web app and from the customer integration reference.

The first vertical slice is passkey-first and uses the existing native SocketFi
API protocol:

1. Start native auth.
2. Request WebAuthn options.
3. Perform registration/assertion with `AuthenticationServices`.
4. Verify with SocketFi, including the create-wallet proof when required.
5. Persist the session in a device-only Keychain item.
6. Restore the account on app launch.

The onboarding UI exposes passkey, EVM wallet and Stellar wallet choices. Only
passkey is enabled by `SocketFiNativeAccountClient` at this stage; EVM and Stellar
must use their own native signer adapters and hardened project-bound API routes.
The UI deliberately does not route those methods through the passkey endpoint.

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
Testnet registration enables native sign-in/sign-up only; its empty invocation
allowlist does not authorize arbitrary contract calls. Transaction permissions
require a separate reviewed configuration. No contract changes are required.

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
