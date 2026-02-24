//
//  MuraloomUITests.swift
//  MuraloomUITests
//
//  Created by Andrejs MJ on 21/08/2025.
//

import XCTest

final class MuraloomUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func makeApp(photosMode: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ui-testing",
            "-ApplePersistenceIgnoreState", "YES"
        ]
        app.launchEnvironment["MURALOOM_UI_TESTING"] = "1"
        if let photosMode {
            app.launchEnvironment["MURALOOM_UI_TEST_PHOTOS_MODE"] = photosMode
        }
        return app
    }

    @MainActor
    private func launchApp(_ app: XCUIApplication) {
        app.launch()
        app.activate()

        if element(app, id: "app.title").waitForExistence(timeout: 2) { return }

        _ = openSettingsFromStatusMenu(app)
        if element(app, id: "app.title").waitForExistence(timeout: 5) { return }

        app.activate()
        app.typeKey("n", modifierFlags: .command)
        if element(app, id: "app.title").waitForExistence(timeout: 5) { return }

        _ = openSettingsFromAppMenu(app)
        _ = element(app, id: "app.title").waitForExistence(timeout: 5)
    }

    @MainActor
    @discardableResult
    private func openSettingsFromStatusMenu(_ app: XCUIApplication) -> Bool {
        let statusItem = app.menuBars.statusItems["menubar.statusItem"]
        guard statusItem.waitForExistence(timeout: 2) else { return false }
        statusItem.click()

        let openSettings = app.menuItems["Open Settings…"]
        guard openSettings.waitForExistence(timeout: 2) else { return false }
        openSettings.click()
        return true
    }

    @MainActor
    @discardableResult
    private func openSettingsFromAppMenu(_ app: XCUIApplication) -> Bool {
        let fileMenu = app.menuBars.menuBarItems["File"]
        guard fileMenu.waitForExistence(timeout: 2) else { return false }
        fileMenu.click()

        let newWindow = app.menuItems["New Window"]
        guard newWindow.waitForExistence(timeout: 2) else { return false }
        newWindow.click()
        return true
    }

    @MainActor
    private func element(_ app: XCUIApplication, id: String) -> XCUIElement {
        app.descendants(matching: .any)[id]
    }

    @MainActor
    @discardableResult
    private func requireElement(
        _ app: XCUIApplication,
        id: String,
        timeout: TimeInterval = 5,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> XCUIElement {
        let target = element(app, id: id)
        if target.waitForExistence(timeout: timeout) == false {
            XCTFail("Missing accessibility id '\(id)'.\n\(app.debugDescription)", file: file, line: line)
        }
        return target
    }

    @MainActor
    func testLaunchShowsAlbumsAndEnablesChangeNow() throws {
        let app = makeApp()
        launchApp(app)

        _ = requireElement(app, id: "app.title", timeout: 5)
        _ = requireElement(app, id: "albums.picker", timeout: 5)
        let changeNow = requireElement(app, id: "wallpaper.changeNow", timeout: 5)
        XCTAssertTrue(changeNow.isEnabled)
    }

    @MainActor
    func testAdvancedControlsToggleShowsManualAlbumIdField() throws {
        let app = makeApp()
        launchApp(app)

        let advancedToggle = requireElement(app, id: "advanced.toggle", timeout: 5)
        advancedToggle.click()
        _ = requireElement(app, id: "advanced.albumId", timeout: 5)
    }

    @MainActor
    func testSignOutAndSignInDoesNotRequireInteractiveAuth() throws {
        let app = makeApp()
        launchApp(app)

        let signOut = requireElement(app, id: "auth.signOut", timeout: 5)
        signOut.click()
        let signIn = requireElement(app, id: "auth.signIn", timeout: 5)

        signIn.click()
        _ = requireElement(app, id: "auth.signOut", timeout: 5)
        _ = requireElement(app, id: "albums.picker", timeout: 5)
    }

    @MainActor
    func testAlbumReloadShowsErrorThenRecovers() throws {
        let app = makeApp(photosMode: "listAlbumsFailOnce")
        launchApp(app)

        _ = requireElement(app, id: "auth.error", timeout: 5)
        let reload = requireElement(app, id: "albums.load", timeout: 5)

        // Retry: should recover and show picker.
        reload.click()
        _ = requireElement(app, id: "albums.picker", timeout: 5)
        XCTAssertFalse(element(app, id: "auth.error").exists)
    }

    @MainActor
    func testPauseResumeTogglesButManualChangeRemainsEnabled() throws {
        let app = makeApp()
        launchApp(app)

        let pauseResume = requireElement(app, id: "wallpaper.pauseResume", timeout: 5)

        let changeNow = requireElement(app, id: "wallpaper.changeNow", timeout: 5)
        XCTAssertTrue(changeNow.isEnabled)

        XCTAssertEqual(pauseResume.label, "Resume Automatic Changes")
        pauseResume.click()
        XCTAssertEqual(pauseResume.label, "Pause Automatic Changes")
        XCTAssertTrue(changeNow.isEnabled)
    }

    @MainActor
    func testMenuBarOpenSettingsAndSignInOut() throws {
        let app = makeApp()
        launchApp(app)

        // Exercise menu bar actions via an in-window harness (UI testing mode),
        // avoiding flaky interactions with the system menu bar.
        let advancedToggle = requireElement(app, id: "advanced.toggle", timeout: 5)
        advancedToggle.click()

        _ = requireElement(app, id: "menubar.openSettings", timeout: 5)
        let menubarSignOut = requireElement(app, id: "menubar.signOut", timeout: 5)
        menubarSignOut.click()

        let menubarSignIn = requireElement(app, id: "menubar.signIn", timeout: 5)
        menubarSignIn.click()

        _ = requireElement(app, id: "menubar.signOut", timeout: 5)
    }
}
