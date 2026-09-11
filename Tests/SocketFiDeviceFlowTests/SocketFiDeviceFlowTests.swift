import XCTest

/// Opt-in, physical TESTNET integration check. Never run against Production.
final class SocketFiDeviceFlowTests: XCTestCase {
    @MainActor
    func testHistoryUnavailableShowsRetryInsteadOfFalseEmpty() {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "fi.socket.socketfi.testnet")
        app.launch()
        XCTAssertTrue(app.buttons["wallet.settings"].waitForExistence(timeout: 25))
        app.tabBars.buttons["Transactions"].tap()
        XCTAssertTrue(app.buttons["history.retry"].waitForExistence(timeout: 55))
        XCTAssertFalse(app.staticTexts["No indexed activity yet"].exists)
        app.buttons["history.retry"].tap()
        XCTAssertTrue(app.staticTexts["History unavailable"].waitForExistence(timeout: 55))
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "History unavailable and retry on Alaa"; shot.lifetime = .keepAlways; add(shot)
        app.tabBars.buttons["Wallet"].tap()
    }

    @MainActor
    func testLiveIndexedHistoryAndTransactionDetails() throws {
        guard ProcessInfo.processInfo.environment["SOCKETFI_LIVE_HISTORY"] == "1" else {
            throw XCTSkip("Requires the deployed authenticated history proxy and configured indexer")
        }
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "fi.socket.socketfi.testnet")
        app.launch()
        XCTAssertTrue(app.buttons["wallet.settings"].waitForExistence(timeout: 25))
        app.tabBars.buttons["Transactions"].tap()
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "history.item.")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 55), "Must show real indexed activity, not an empty or unavailable state")
        let hash = row.value as? String ?? ""
        XCTAssertNotNil(hash.range(of: "^[a-fA-F0-9]{64}$", options: .regularExpression))
        row.tap()
        XCTAssertTrue(app.staticTexts[hash].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Stellar Testnet"].exists)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "Live indexed transaction details on Alaa"; shot.lifetime = .keepAlways; add(shot)
    }
    /// Opt-in: sends exactly 1 TESTNET XLM once. Wallet approvals stay user-controlled.
    /// Invoke only after checking the deployed policy and recipient baseline.
    @MainActor
    func testLiveTestnetXlmWithdrawal() throws {
        guard ProcessInfo.processInfo.environment["SOCKETFI_LIVE_WITHDRAWAL"] == "1" else {
            throw XCTSkip("Opt-in only: set SOCKETFI_LIVE_WITHDRAWAL=1 in the test runner after confirming TESTNET funding and deployed permissions")
        }
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "fi.socket.socketfi.testnet")
        app.launch()
        XCTAssertTrue(app.buttons["wallet.settings"].waitForExistence(timeout: 25))
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: app.buttons["Withdraw"])
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 60), .completed)
        app.buttons["Withdraw"].tap()
        XCTAssertTrue(app.staticTexts["Testnet"].waitForExistence(timeout: 10))
        // The existing funded session defaults to XLM. Fail instead of guessing another asset.
        XCTAssertTrue(app.staticTexts["XLM"].firstMatch.exists)
        app.textFields["withdraw.amount"].tap()
        app.textFields["withdraw.amount"].typeText("1")
        let recipient = app.descendants(matching: .any)["withdraw.recipient"].firstMatch
        recipient.tap()
        recipient.typeText("GBARGJH4BTODPXFAK6UJGUR37LMUG4N7V46GIH4AD57VLO3ZH4LYHHD3")
        app.toolbars.buttons["Done"].tap()
        let review = app.buttons["Review withdrawal"]
        XCTAssertTrue(review.isEnabled, "Live project must permit TESTNET token transfers; no bypass is allowed")
        review.tap()
        let approve = app.buttons["Approve in wallet"]
        XCTAssertTrue(approve.waitForExistence(timeout: 50), "This opt-in run requires the funded EVM session")
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Actual 1 XLM withdrawal review"; screenshot.lifetime = .keepAlways; add(screenshot)
        approve.tap()
        XCTAssertFalse(app.buttons["wallet.choice.MetaMask"].exists, "A transaction must not show the authentication wallet picker")
        XCTAssertFalse(app.buttons["wallet.choice.Trust Wallet"].exists)
        let wallet = XCUIApplication(bundleIdentifier: "io.metamask.MetaMask")
        let system = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let openDeadline = Date().addingTimeInterval(30)
        while wallet.state != .runningForeground && Date() < openDeadline {
            if app.alerts.buttons["Open"].exists { app.alerts.buttons["Open"].tap() }
            else if system.alerts.buttons["Open"].exists { system.alerts.buttons["Open"].tap() }
            RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        }
        XCTAssertEqual(wallet.state, .runningForeground)
        print("[SocketFiWithdrawalTest] awaiting_physical_wallet_approval")
        XCTAssertTrue(app.staticTexts["Transaction confirmed"].waitForExistence(timeout: 170), "Review any uncertain outcome before attempting another transfer")
        let receipt = app.descendants(matching: .any)["wallet.receipt"].firstMatch
        let hash = receipt.value as? String ?? ""
        XCTAssertNotNil(hash.range(of: "^[a-fA-F0-9]{64}$", options: .regularExpression))
        print("[SocketFiWithdrawalTest] confirmed_hash=\(hash)")
        // A separate RPC/Horizon check must verify this public hash and recipient balance.
    }

    /// Adds an existing TESTNET token only; never deploys or mints an asset.
    @MainActor
    func testCustomAssetPersistsAndWithdrawalPermissions() {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "fi.socket.socketfi.testnet")
        app.launch()
        XCTAssertTrue(app.buttons["wallet.settings"].waitForExistence(timeout: 25))
        app.buttons["wallet.settings"].tap()
        let input = app.textFields["asset.contract"]
        XCTAssertTrue(input.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["XLM"].waitForExistence(timeout: 45))
        if !app.staticTexts["XTAR"].exists {
            input.tap()
            input.typeText("CCZGLAUBDKJSQK72QOZHVU7CUWKW45OZWYWCLL27AEK74U2OIBK6LXF2")
            app.buttons["Review"].tap()
            let addToken = app.buttons["Add to watchlist"]
            XCTAssertTrue(addToken.waitForExistence(timeout: 10))
            if !addToken.isHittable { app.swipeUp() }
            addToken.tap()
            let added = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "Contract address"), object: input)
            XCTAssertEqual(XCTWaiter.wait(for: [added], timeout: 60), .completed, "Metadata must be accepted and added successfully")
        }
        app.navigationBars.buttons["Done"].tap()
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["wallet.settings"].waitForExistence(timeout: 25))
        app.buttons["wallet.settings"].tap()
        XCTAssertTrue(app.staticTexts["XTAR"].waitForExistence(timeout: 45), "Custom asset must survive a relaunch and network reload")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "Custom XTAR persisted on Alaa"; shot.lifetime = .keepAlways; add(shot)
        XCTAssertTrue(app.staticTexts["XLM"].exists)
        XCTAssertTrue(app.staticTexts["USDC"].exists)
        app.navigationBars.buttons["Done"].tap()
        app.buttons["Withdraw"].tap()
        let amount = app.textFields["withdraw.amount"]
        XCTAssertTrue(amount.waitForExistence(timeout: 10))
        amount.tap(); amount.typeText("1")
        let recipient = app.descendants(matching: .any)["withdraw.recipient"].firstMatch
        recipient.tap(); recipient.typeText("GC67BE5DCB4HLU4XSA6W2J7TRRZGIG26MIC5QZTZGHNPMA7Q62UY3DEW")
        let done = app.toolbars.buttons["Done"]
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        done.tap()
        app.swipeUp()
        XCTAssertFalse(app.staticTexts["Withdrawals are unavailable for this app."].exists)
        XCTAssertTrue(app.buttons["Review withdrawal"].isEnabled, "The deployed Testnet token transfer policy must permit review")
        let blocked = XCTAttachment(screenshot: app.screenshot())
        blocked.name = "Funded Testnet withdrawal available"; blocked.lifetime = .keepAlways; add(blocked)
        app.terminate(); app.launch()
    }

    @MainActor
    func testWalletScreensAndRecipientPaste() {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "fi.socket.socketfi.testnet")
        app.launch()
        XCTAssertTrue(app.buttons["wallet.settings"].waitForExistence(timeout: 25))
        let address = app.descendants(matching: .any)["wallet.address"].firstMatch.value as? String ?? ""
        XCTAssertTrue(address.hasPrefix("C") && address.count == 56)
        print("[SocketFiWalletTest] account=\(address)")
        func capture(_ name: String) {
            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.name = name
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        capture("Wallet on Alaa")
        app.buttons["wallet.copyAddress"].tap()
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: app.buttons["Withdraw"])
        XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: 60), .completed)
        app.buttons["Withdraw"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["withdraw.recipient"].firstMatch.waitForExistence(timeout: 10))
        app.buttons["withdraw.paste"].tap()
        let allow = app.alerts.buttons["Allow Paste"]
        if allow.waitForExistence(timeout: 2) { allow.tap() }
        XCTAssertTrue(app.staticTexts["Choose a different destination from this wallet."].waitForExistence(timeout: 5))
        capture("Withdrawal paste on Alaa")
        app.navigationBars.buttons["Cancel"].tap()
        app.buttons["wallet.settings"].tap()
        XCTAssertTrue(app.textFields["asset.contract"].waitForExistence(timeout: 10))
        capture("Wallet settings on Alaa")
        app.textFields["asset.contract"].tap()
        app.textFields["asset.contract"].typeText("invalid")
        app.buttons["Review"].tap()
        XCTAssertTrue(app.staticTexts["This does not look like a valid Stellar contract address."].waitForExistence(timeout: 5))
        capture("Custom asset validation on Alaa")
        app.terminate()
        app.launch()
    }

    @MainActor
    func testFreshPairingCancellationAndRetry() {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "fi.socket.socketfi.testnet")
        app.launchArguments = ["-preview-onboarding"]
        app.launch()
        XCTAssertTrue(app.buttons["onboarding.evm"].waitForExistence(timeout: 20))
        let change = app.buttons["onboarding.changeWallet"]
        if change.exists {
            change.tap()
            let disconnected = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "exists == false"), object: change)
            XCTAssertEqual(XCTWaiter.wait(for: [disconnected], timeout: 20), .completed)
        }
        let wallet = XCUIApplication(bundleIdentifier: "com.sixdays.trust")
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for _ in 0..<2 {
            app.buttons["onboarding.evm"].tap()
            let choice = app.buttons["wallet.choice.Trust Wallet"]
            XCTAssertTrue(choice.waitForExistence(timeout: 35))
            XCTAssertTrue(app.buttons["wallet.choice.MetaMask"].exists)
            choice.tap()
            let deadline = Date().addingTimeInterval(30)
            while wallet.state != .runningForeground && Date() < deadline {
                if app.alerts.buttons["Open"].exists { app.alerts.buttons["Open"].tap() }
                else if springboard.alerts.buttons["Open"].exists { springboard.alerts.buttons["Open"].tap() }
                RunLoop.current.run(until: Date().addingTimeInterval(0.5))
            }
            XCTAssertEqual(wallet.state, .runningForeground)
            // Return without approving the pending wallet connection.
            app.activate()
            let cancel = app.navigationBars.buttons["Cancel"]
            XCTAssertTrue(cancel.waitForExistence(timeout: 10))
            cancel.tap()
            XCTAssertTrue(app.buttons["onboarding.evm"].waitForExistence(timeout: 10))
            XCTAssertFalse(app.buttons["Wallet settings"].exists)
        }
        print("[SocketFiDeviceTest] stage=external_pairing_cancel_retry_passed")
        app.terminate()
        app.launchArguments = []
        app.launch()
        // A cancellation-only test does not create or require a signed-in session.
        // Restoration is asserted by the successful-authentication tests below.
    }

    /// Requires an explicit catalogue selection; saved-session reuse cannot pass.
    @MainActor
    func testFreshTrustWalletAuthentication() throws {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "fi.socket.socketfi.testnet")
        app.launchArguments = ["-preview-onboarding"]
        app.launch()
        XCTAssertTrue(app.buttons["onboarding.evm"].waitForExistence(timeout: 20))
        let change = app.buttons["onboarding.changeWallet"]
        if change.exists {
            change.tap()
            let disconnected = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "exists == false"), object: change)
            XCTAssertEqual(XCTWaiter.wait(for: [disconnected], timeout: 20), .completed)
        }
        app.buttons["onboarding.evm"].tap()
        let choice = app.buttons["wallet.choice.Trust Wallet"]
        XCTAssertTrue(choice.waitForExistence(timeout: 35))
        choice.tap()
        print("[SocketFiDeviceTest] stage=fresh_trust_selected")
        let wallet = XCUIApplication(bundleIdentifier: "com.sixdays.trust")
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let launchDeadline = Date().addingTimeInterval(30)
        while wallet.state != .runningForeground && Date() < launchDeadline {
            if app.alerts.buttons["Open"].exists { app.alerts.buttons["Open"].tap() }
            else if springboard.alerts.buttons["Open"].exists { springboard.alerts.buttons["Open"].tap() }
            RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        }
        XCTAssertEqual(wallet.state, .runningForeground)
        print("[SocketFiDeviceTest] stage=fresh_trust_foreground")
        // Wallet unlock, connection and signature approvals remain user-controlled.
        let deadline = Date().addingTimeInterval(180)
        while Date() < deadline {
            if app.state == .runningForeground {
                if app.buttons["Wallet settings"].exists {
                    print("[SocketFiDeviceTest] stage=fresh_pairing_authenticated")
                    app.terminate()
                    app.launchArguments = []
                    app.launch()
                    XCTAssertTrue(app.buttons["Wallet settings"].waitForExistence(timeout: 20))
                    print("[SocketFiDeviceTest] stage=fresh_pairing_session_restored")
                    return
                }
                if app.buttons["onboarding.evm"].exists {
                    XCTFail("Fresh wallet authentication returned to onboarding; inspect device diagnostics")
                    return
                }
            }
            RunLoop.current.run(until: Date().addingTimeInterval(1))
        }
        XCTFail("Fresh pairing did not authenticate within 180 seconds; check the physical wallet prompt")
    }

    @MainActor
    func testWalletPickerCancellationAndMetaMaskAvailability() {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "fi.socket.socketfi.testnet")
        app.launchArguments = ["-preview-onboarding"]
        app.launch()
        XCTAssertTrue(app.buttons["onboarding.evm"].waitForExistence(timeout: 20))
        // Preserve saved WalletConnect sessions: they must not suppress choices.
        app.buttons["onboarding.evm"].tap()
        XCTAssertTrue(app.buttons["wallet.choice.MetaMask"].waitForExistence(timeout: 35))
        XCTAssertTrue(app.buttons["wallet.choice.Trust Wallet"].exists)
        app.navigationBars.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["onboarding.evm"].waitForExistence(timeout: 10))
        app.buttons["onboarding.evm"].tap()
        XCTAssertTrue(app.buttons["wallet.choice.MetaMask"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["wallet.choice.Trust Wallet"].exists)
        XCTAssertFalse(app.staticTexts["Already connected"].exists)
        app.navigationBars.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["onboarding.evm"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["onboarding.stellar"].exists)
        app.terminate()
        app.launchArguments = []
        app.launch()
    }

    @MainActor
    func testMetaMaskAccountFlow() throws {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "fi.socket.socketfi.testnet")
        app.launchArguments = ["-preview-onboarding"]
        app.launch()
        XCTAssertTrue(app.buttons["onboarding.evm"].waitForExistence(timeout: 20))
        app.buttons["onboarding.evm"].tap()
        let metamask = app.buttons["wallet.choice.MetaMask"]
        XCTAssertTrue(metamask.waitForExistence(timeout: 35))
        metamask.tap()
        let open = app.alerts.buttons["Open"]
        if open.waitForExistence(timeout: 10) { open.tap() }
        else {
            let systemOpen = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.buttons["Open"]
            if systemOpen.waitForExistence(timeout: 2) { systemOpen.tap() }
        }
        let wallet = XCUIApplication(bundleIdentifier: "io.metamask.MetaMask")
        XCTAssertTrue(wallet.wait(for: .runningForeground, timeout: 25), "One tap must open MetaMask")
        print("[SocketFiDeviceTest] stage=metamask_opened_with_one_tap")
        XCTAssertTrue(app.buttons["Wallet settings"].waitForExistence(timeout: 180), "Approve connection and sign-in on the physical device")
        app.terminate()
        app.launchArguments = []
        app.launch()
        XCTAssertTrue(app.buttons["Wallet settings"].waitForExistence(timeout: 20))
    }

    @MainActor
    func testOnboardingLayoutAndPasskeySheet() {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "fi.socket.socketfi.testnet")
        app.launchArguments = ["-preview-onboarding"]
        app.launch()
        let passkey = app.buttons["onboarding.passkey"]
        XCTAssertTrue(passkey.waitForExistence(timeout: 20))
        XCTAssertTrue(app.buttons["onboarding.evm"].exists)
        let stellar = app.buttons["onboarding.stellar"]
        XCTAssertTrue(stellar.exists)
        XCTAssertFalse(stellar.isEnabled)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Onboarding on Alaa"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        passkey.tap()
        XCTAssertTrue(app.buttons["Sign in with passkey"].waitForExistence(timeout: 5))
        let sheet = XCTAttachment(screenshot: app.screenshot())
        sheet.name = "Passkey options on Alaa"
        sheet.lifetime = .keepAlways
        add(sheet)
        app.buttons["Close passkey sign-in"].tap()
        XCTAssertTrue(passkey.waitForExistence(timeout: 5))
        // Exit the visual-only route; the real stored session is untouched.
        app.terminate()
        app.launchArguments = []
        app.launch()
    }

    @MainActor
    func testEvmSessionSurvivesRelaunch() throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("Requires successful EVM sign-in on the physical Testnet device")
        #else
        let app = XCUIApplication(bundleIdentifier: "fi.socket.socketfi.testnet")
        app.launch()
        XCTAssertTrue(app.buttons["Wallet settings"].waitForExistence(timeout: 20))
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["Wallet settings"].waitForExistence(timeout: 20), "Persisted session must restore to the wallet")
        print("[SocketFiDeviceTest] stage=session_restored_after_relaunch")
        #endif
    }

    @MainActor
    func testTrustWalletAccountCreation() throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("Requires the connected physical iPhone and Trust wallet")
        #else
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "fi.socket.socketfi.testnet")
        app.launch()
        let evm = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Continue with EVM wallet")).firstMatch
        XCTAssertTrue(evm.waitForExistence(timeout: 20), "SocketFi must be signed out before this opt-in test")
        evm.tap()
        print("[SocketFiDeviceTest] stage=evm_button_tapped")
        let trustButton = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Trust")).firstMatch
        if trustButton.waitForExistence(timeout: 10) {
            trustButton.tap()
            print("[SocketFiDeviceTest] stage=trust_wallet_selected")
        }
        let appOpen = app.alerts.buttons["Open"]
        if appOpen.waitForExistence(timeout: 5) { appOpen.tap() }
        let wallet = XCUIApplication(bundleIdentifier: "com.sixdays.trust")
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let open = springboard.alerts.buttons["Open"]
        if open.waitForExistence(timeout: 3) { open.tap() }
        if wallet.wait(for: .runningForeground, timeout: 20) {
            print("[SocketFiDeviceTest] stage=trust_wallet_foreground")
        }
        // Wallet approvals remain visible on the real device. Do not blindly
        // approve a stale request or interact with PIN/biometric credentials.
        print("[SocketFiDeviceTest] stage=awaiting_physical_wallet_approval")
        let cancel = app.buttons["Cancel EVM sign-in"]
        let deadline = Date().addingTimeInterval(180)
        while Date() < deadline {
            if app.state == .runningForeground && evm.exists && !cancel.exists {
                // No addresses, response bodies or credentials in test output.
                XCTFail("EVM sign-in returned to onboarding; inspect redacted device stage diagnostics")
                return
            }
            if app.state == .runningForeground && !evm.exists && app.buttons["Deposit"].exists {
                print("[SocketFiDeviceTest] stage=wallet_screen_reached")
                return
            }
            RunLoop.current.run(until: Date().addingTimeInterval(1))
        }
        XCTFail("Physical EVM flow did not reach the wallet screen within 180 seconds")
        #endif
    }
}
