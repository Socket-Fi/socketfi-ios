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

Enable the Associated Domains capability with `webcredentials:socket.fi` after
the SocketFi application is registered. Never commit real client IDs, production
credentials, API keys or wallet secrets to this repository.

In Xcode, select the `SocketFi` target, choose your Apple Development Team under
Signing & Capabilities, and enable automatic signing. Register both bundle IDs
(`fi.socket.socketfi.testnet` and `fi.socket.socketfi`) in the Apple Developer
portal first; a provisioning profile cannot be created for an unregistered ID.

The associated-domain file must be served by SocketFi at
`https://socket.fi/.well-known/apple-app-site-association` and include both
registered bundle identifiers. The bundle IDs and client IDs in
`project.yml` are placeholders until the applications are registered. A server
payload template is included at `AssociatedDomains/apple-app-site-association.example.json`.

The package currently targets iOS 17 because it depends on AuthenticationServices,
UIKit presentation anchors and Swift concurrency. Build and test it on a real
device for passkey registration and assertion; simulator-only validation is not
sufficient.
