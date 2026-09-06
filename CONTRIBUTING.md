# Contributing to SocketFi iOS

`main` is the protected integration branch. Work should be done on a short-lived
branch and merged through a pull request. Do not commit directly to `main`.

## Start a working branch

```bash
git switch main
git pull --ff-only origin main
git switch -c feat/passkey-approval-screen
```

Use prefixes such as `feat/`, `fix/`, `security/`, `docs/`, or `chore/`. Keep a
branch focused on one coherent change.

## Local setup and validation

```bash
brew install xcodegen
xcodegen generate
open SocketFi.xcodeproj
```

Before opening a pull request, run the Testnet checks on macOS:

```bash
xcodebuild \
  -project SocketFi.xcodeproj \
  -scheme SocketFi \
  -configuration Testnet \
  -destination 'generic/platform=iOS Simulator' \
  build

xcodebuild \
  -project SocketFi.xcodeproj \
  -scheme SocketFi \
  -configuration Testnet \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  test
```

Passkey registration, assertion, associated domains, wallet callbacks and
transaction approval must also be exercised on a physical Testnet device.

Never commit production client credentials, signing material, API keys, wallet
keys, provisioning profiles or local `xcconfig` files. Keep generated Xcode
projects and build output untracked; `project.yml` is the source of truth.

## Commit and push

```bash
git add <files>
git diff --cached --check
git commit -m "feat: describe the change"
git push -u origin HEAD
```

Use conventional commit prefixes: `feat`, `fix`, `security`, `docs`, `test`,
`refactor`, or `chore`.

## Open and merge a pull request

With GitHub CLI:

```bash
gh pr create \
  --base main \
  --head "$(git branch --show-current)" \
  --fill
```

Or open the repository on GitHub and create a pull request from the pushed branch
into `main`. A pull request should include the user-visible behavior, validation
performed, API/contract implications, and any Testnet-only limitations.

After review and passing checks, merge through GitHub (prefer squash merge) and
delete the working branch:

```bash
gh pr merge --squash --delete-branch
git switch main
git pull --ff-only origin main
```

Do not merge changes that weaken passkey challenge/RP validation, signer binding,
network separation, transaction review, amount safety, Keychain handling, or the
Soroban authorization boundary.
