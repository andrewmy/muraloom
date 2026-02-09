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
        app.launchArguments = ["-ui-testing"]
        app.launchEnvironment["MURALOOM_UI_TESTING"] = "1"
        if let photosMode {
            app.launchEnvironment["MURALOOM_UI_TEST_PHOTOS_MODE"] = photosMode
        }
        return app
    }

    @MainActor
    func testLaunchShowsAlbumsAndEnablesChangeNow() throws {
        let app = makeApp()
        app.launch()

        XCTAssertTrue(app.staticTexts["app.title"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.popUpButtons["albums.picker"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["wallpaper.changeNow"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["wallpaper.changeNow"].isEnabled)
    }

    @MainActor
    func testAdvancedControlsToggleShowsManualAlbumIdField() throws {
        let app = makeApp()
        app.launch()

        XCTAssertTrue(app.buttons["advanced.toggle"].waitForExistence(timeout: 3))
        app.buttons["advanced.toggle"].click()
        XCTAssertTrue(app.textFields["advanced.albumId"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testSignOutAndSignInDoesNotRequireInteractiveAuth() throws {
        let app = makeApp()
        app.launch()

        XCTAssertTrue(app.buttons["auth.signOut"].waitForExistence(timeout: 3))
        app.buttons["auth.signOut"].click()
        XCTAssertTrue(app.buttons["auth.signIn"].waitForExistence(timeout: 3))

        app.buttons["auth.signIn"].click()
        XCTAssertTrue(app.buttons["auth.signOut"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.popUpButtons["albums.picker"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testAlbumReloadShowsErrorThenRecovers() throws {
        let app = makeApp(photosMode: "listAlbumsFailOnce")
        app.launch()

        XCTAssertTrue(app.staticTexts["auth.error"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["albums.load"].waitForExistence(timeout: 3))

        // Retry: should recover and show picker.
        app.buttons["albums.load"].click()
        XCTAssertTrue(app.popUpButtons["albums.picker"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["auth.error"].exists)
    }

    @MainActor
    func testPauseResumeTogglesButManualChangeRemainsEnabled() throws {
        let app = makeApp()
        app.launch()

        let pauseResume = app.buttons["wallpaper.pauseResume"]
        XCTAssertTrue(pauseResume.waitForExistence(timeout: 5))

        let changeNow = app.buttons["wallpaper.changeNow"]
        XCTAssertTrue(changeNow.waitForExistence(timeout: 5))
        XCTAssertTrue(changeNow.isEnabled)

        XCTAssertEqual(pauseResume.label, "Resume Automatic Changes")
        pauseResume.click()
        XCTAssertEqual(pauseResume.label, "Pause Automatic Changes")
        XCTAssertTrue(changeNow.isEnabled)
    }

    @MainActor
    func testMenuBarOpenSettingsAndSignInOut() throws {
        let app = makeApp()
        app.launch()

        // Exercise menu bar actions via an in-window harness (UI testing mode),
        // avoiding flaky interactions with the system menu bar.
        XCTAssertTrue(app.buttons["advanced.toggle"].waitForExistence(timeout: 5))
        app.buttons["advanced.toggle"].click()

        XCTAssertTrue(app.buttons["menubar.openSettings"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["menubar.signOut"].waitForExistence(timeout: 5))
        app.buttons["menubar.signOut"].click()

        XCTAssertTrue(app.buttons["menubar.signIn"].waitForExistence(timeout: 5))
        app.buttons["menubar.signIn"].click()

        XCTAssertTrue(app.buttons["menubar.signOut"].waitForExistence(timeout: 5))
    }
}
