#if DEBUG
import AppKit
import SwiftUI
import XCTest
@testable import Bairometer

final class MenuBarPopoverLifecycleTests: XCTestCase {
    func testToggleDecisionClosesWheneverLogicalOrNativePresentationIsVisible() {
        XCTAssertEqual(
            MenuBarPopoverToggleCoordinator.decision(
                isPresentationVisible: false,
                isPopoverShown: false
            ),
            .open
        )
        XCTAssertEqual(
            MenuBarPopoverToggleCoordinator.decision(
                isPresentationVisible: true,
                isPopoverShown: false
            ),
            .closeOnly
        )
        XCTAssertEqual(
            MenuBarPopoverToggleCoordinator.decision(
                isPresentationVisible: false,
                isPopoverShown: true
            ),
            .closeOnly
        )
        XCTAssertEqual(
            MenuBarPopoverToggleCoordinator.decision(
                wasVisibleAtMouseDown: true,
                isPresentationVisible: false,
                isPopoverShown: false
            ),
            .closeOnly
        )
        XCTAssertEqual(
            MenuBarPopoverToggleCoordinator.decision(
                isPresentationVisible: true,
                isPopoverShown: true
            ),
            .closeOnly
        )
    }

    @MainActor
    func testPreDismissLatchClosesExactMouseDownAfterTransientDelegateClose() {
        let harness = makeControllerHarness()
        let firstAnchor = harness.statusButton
        let secondAnchor = NSStatusBarButton(frame: .zero)
        harness.panelPresentation.isVisible = true
        harness.presenter.isShown = true

        harness.controller.handlePreDismissEvent(.leftMouseDown)
        harness.presenter.isShown = false
        harness.controller.popoverDidClose(
            Notification(name: NSPopover.didCloseNotification)
        )
        harness.controller.handleStatusItemAction(
            sender: firstAnchor,
            eventType: .leftMouseDown
        )

        XCTAssertEqual(harness.presenter.showCount, 0)
        XCTAssertEqual(harness.presenter.closeCount, 0)
        XCTAssertFalse(harness.panelPresentation.isVisible)

        harness.controller.handlePreDismissEvent(.leftMouseDown)
        harness.controller.handleStatusItemAction(
            sender: secondAnchor,
            eventType: .leftMouseDown
        )

        XCTAssertEqual(harness.presenter.showCount, 1)
        XCTAssertEqual(harness.presenter.closeCount, 0)
        XCTAssertTrue(harness.anchorFactory.lastSourceView === secondAnchor)
        XCTAssertTrue(
            harness.presenter.lastAnchor
                === harness.anchorFactory.activeHost?.positioningView
        )
        XCTAssertTrue(harness.panelPresentation.isVisible)
    }

    @MainActor
    func testPreDismissLatchExpiresAfterUnrelatedOutsideMouseDown() {
        let harness = makeControllerHarness()
        harness.panelPresentation.isVisible = true
        harness.presenter.isShown = true

        harness.controller.handlePreDismissEvent(.leftMouseDown)
        harness.presenter.isShown = false
        harness.controller.popoverDidClose(
            Notification(name: NSPopover.didCloseNotification)
        )
        runMainLoop()

        let laterAnchor = NSStatusBarButton(frame: .zero)
        harness.controller.handleStatusItemAction(
            sender: laterAnchor,
            eventType: .leftMouseDown
        )

        XCTAssertEqual(harness.presenter.showCount, 1)
        XCTAssertEqual(harness.presenter.closeCount, 0)
        XCTAssertTrue(harness.anchorFactory.lastSourceView === laterAnchor)
    }

    @MainActor
    func testPreDismissLatchIsConsumedOnceForSameAnchor() {
        let harness = makeControllerHarness()
        harness.panelPresentation.isVisible = true

        harness.controller.handlePreDismissEvent(.leftMouseDown)
        harness.controller.popoverDidClose(
            Notification(name: NSPopover.didCloseNotification)
        )
        harness.controller.handleStatusItemAction(
            sender: harness.statusButton,
            eventType: .leftMouseDown
        )
        harness.controller.handleStatusItemAction(
            sender: harness.statusButton,
            eventType: .leftMouseDown
        )

        XCTAssertEqual(harness.presenter.closeCount, 0)
        XCTAssertEqual(harness.presenter.showCount, 1)
        XCTAssertTrue(harness.panelPresentation.isVisible)
    }

    func testPreDismissLatchGenerationCannotClearANewerEvent() {
        var latch = MenuBarPreDismissVisibilityLatch()
        let firstGeneration = latch.beginEvent(isVisible: true)
        _ = latch.beginEvent(isVisible: true)

        latch.expire(generation: firstGeneration)

        XCTAssertTrue(latch.consume(for: .leftMouseDown))
        XCTAssertFalse(latch.consume(for: .leftMouseDown))
    }

    func testPreDismissLatchIgnoresKeyboardRightAndMouseUpActions() {
        var latch = MenuBarPreDismissVisibilityLatch()
        _ = latch.beginEvent(isVisible: true)

        XCTAssertFalse(latch.consume(for: nil))
        XCTAssertFalse(latch.consume(for: .rightMouseDown))
        XCTAssertFalse(latch.consume(for: .rightMouseUp))
        XCTAssertFalse(latch.consume(for: .leftMouseUp))
        XCTAssertTrue(latch.consume(for: .leftMouseDown))
    }

    @MainActor
    func testPreDismissMonitorReleasesAndRemovesItsLocalMonitorOnTeardown() {
        weak var weakMonitor: MenuBarPreDismissMouseDownMonitor?

        autoreleasepool {
            let monitor = MenuBarPreDismissMouseDownMonitor { _ in }
            weakMonitor = monitor
        }

        XCTAssertNil(weakMonitor)
    }

    @MainActor
    func testAnchorGeometryCapturesScreenRectBeforeSourceWindowMoves() throws {
        let window = NSWindow(
            contentRect: NSRect(x: 120, y: 240, width: 100, height: 60),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        let sourceView = NSView(
            frame: NSRect(x: 7, y: 11, width: 24, height: 18)
        )
        window.contentView?.addSubview(sourceView)
        let expected = window.convertToScreen(
            sourceView.convert(sourceView.bounds, to: nil)
        )

        let captured = try XCTUnwrap(
            MenuBarPopoverAnchorGeometry.screenRect(
                relativeTo: sourceView.bounds,
                of: sourceView
            )
        )
        sourceView.frame.origin = NSPoint(x: 37, y: 29)
        window.setFrameOrigin(NSPoint(x: 800, y: 600))

        XCTAssertEqual(captured, expected)
        XCTAssertNotEqual(
            MenuBarPopoverAnchorGeometry.screenRect(
                relativeTo: sourceView.bounds,
                of: sourceView
            ),
            captured
        )
    }

    @MainActor
    func testProductionAnchorHostIsNonactivatingAndTearsDownItsPanel() throws {
        let screenRect = NSRect(x: -10_000, y: -10_000, width: 24, height: 24)
        let host = MenuBarPopoverAnchorHost(screenRect: screenRect)
        let panel = try XCTUnwrap(host.panelForTesting)

        XCTAssertEqual(host.screenRect, screenRect)
        XCTAssertEqual(host.positioningRect, host.positioningView.bounds)
        XCTAssertTrue(panel.styleMask.contains(.borderless))
        XCTAssertTrue(panel.styleMask.contains(.nonactivatingPanel))
        XCTAssertTrue(panel.ignoresMouseEvents)
        XCTAssertFalse(panel.canBecomeKey)
        XCTAssertFalse(panel.canBecomeMain)
        XCTAssertFalse(panel.isOpaque)
        XCTAssertFalse(panel.hasShadow)

        host.tearDown()

        XCTAssertNil(host.panelForTesting)
        XCTAssertFalse(panel.isVisible)
    }

    @MainActor
    func testFrozenAnchorClosesWithoutReopenAndNextClickCapturesNewRect() {
        let harness = makeControllerHarness()
        let firstRect = NSRect(x: 100, y: 900, width: 24, height: 24)
        let migratedRect = NSRect(x: 1_500, y: 900, width: 24, height: 24)
        let secondRect = NSRect(x: 1_600, y: 900, width: 24, height: 24)
        harness.anchorFactory.sourceScreenRects[
            ObjectIdentifier(harness.statusButton)
        ] = firstRect

        harness.controller.handleStatusItemAction(
            sender: harness.statusButton,
            eventType: .leftMouseDown
        )

        weak let firstHost = harness.anchorFactory.activeHost
        XCTAssertEqual(firstHost?.screenRect, firstRect)
        XCTAssertEqual(harness.presenter.showCount, 1)
        XCTAssertEqual(
            harness.controller.popoverBehaviorForTesting,
            .transient
        )

        harness.anchorFactory.sourceScreenRects[
            ObjectIdentifier(harness.statusButton)
        ] = migratedRect
        XCTAssertEqual(firstHost?.screenRect, firstRect)
        XCTAssertEqual(harness.presenter.showCount, 1)

        harness.presenter.isShown = false
        harness.controller.popoverDidClose(
            Notification(name: NSPopover.didCloseNotification)
        )

        XCTAssertEqual(harness.presenter.showCount, 1)
        XCTAssertEqual(harness.presenter.closeCount, 0)
        XCTAssertEqual(harness.anchorFactory.tearDownCount, 1)
        XCTAssertNil(harness.anchorFactory.activeHost)
        XCTAssertFalse(harness.panelPresentation.isVisible)

        let secondButton = NSStatusBarButton(frame: .zero)
        harness.anchorFactory.sourceScreenRects[
            ObjectIdentifier(secondButton)
        ] = secondRect
        harness.controller.handleStatusItemAction(
            sender: secondButton,
            eventType: .leftMouseDown
        )

        XCTAssertEqual(harness.presenter.showCount, 2)
        XCTAssertEqual(harness.anchorFactory.creationCount, 2)
        XCTAssertEqual(
            harness.anchorFactory.capturedScreenRects,
            [firstRect, secondRect]
        )
        XCTAssertEqual(
            harness.anchorFactory.activeHost?.screenRect,
            secondRect
        )
        XCTAssertTrue(harness.anchorFactory.lastSourceView === secondButton)
    }

    @MainActor
    func testAnchorFactoryAndPresentationFailureLeaveNoActiveHost() {
        let factoryFailure = makeControllerHarness()
        factoryFailure.anchorFactory.returnsHost = false

        factoryFailure.controller.handleStatusItemAction(
            sender: factoryFailure.statusButton,
            eventType: .leftMouseDown
        )

        XCTAssertEqual(factoryFailure.anchorFactory.creationCount, 1)
        XCTAssertEqual(factoryFailure.presenter.showCount, 0)
        XCTAssertNil(factoryFailure.anchorFactory.activeHost)
        XCTAssertFalse(factoryFailure.panelPresentation.isVisible)

        let presentationFailure = makeControllerHarness()
        presentationFailure.presenter.succeedsOnShow = false

        presentationFailure.controller.handleStatusItemAction(
            sender: presentationFailure.statusButton,
            eventType: .leftMouseDown
        )

        XCTAssertEqual(presentationFailure.presenter.showCount, 1)
        XCTAssertEqual(presentationFailure.anchorFactory.tearDownCount, 1)
        XCTAssertNil(presentationFailure.anchorFactory.activeHost)
        XCTAssertFalse(presentationFailure.panelPresentation.isVisible)
    }

    @MainActor
    func testControllerTeardownReleasesActivePresentationAnchor() {
        let storageDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let suiteName = "MenuBarPopoverLifecycleTests.\(UUID().uuidString)"
        let userDefaults = UserDefaults(suiteName: suiteName)!
        defer {
            try? FileManager.default.removeItem(at: storageDirectory)
            userDefaults.removePersistentDomain(forName: suiteName)
        }
        let appModel = AppModel(
            storageDirectory: storageDirectory,
            userDefaults: userDefaults
        )
        let languagePreference = AppLanguagePreference(
            userDefaults: userDefaults
        )
        let statusButton = NSStatusBarButton(frame: .zero)
        let presenter = MenuBarPopoverPresenterSpy()
        let anchorFactory = MenuBarPopoverAnchorHostFactorySpy()
        let panelPresentation = MenuBarPanelPresentationState()
        var controller: MenuBarStatusItemController? =
            MenuBarStatusItemController(
                appModelForTesting: appModel,
                appLanguagePreference: languagePreference,
                statusButton: statusButton,
                popoverPresenter: presenter,
                popoverAnchorFactory: anchorFactory,
                panelPresentation: panelPresentation
            )

        controller?.handleStatusItemAction(
            sender: statusButton,
            eventType: .leftMouseDown
        )
        weak let weakHost = anchorFactory.activeHost
        XCTAssertNotNil(weakHost)

        controller?.popoverWillClose(
            Notification(name: NSPopover.willCloseNotification)
        )
        presenter.completeClose()
        controller?.handleStatusItemAction(
            sender: statusButton,
            eventType: .leftMouseDown
        )
        XCTAssertEqual(presenter.showCount, 1)
        XCTAssertEqual(presenter.closeCount, 0)
        XCTAssertTrue(panelPresentation.isVisible)
        XCTAssertEqual(anchorFactory.tearDownCount, 0)
        XCTAssertNotNil(weakHost)

        controller = nil

        XCTAssertEqual(anchorFactory.tearDownCount, 1)
        XCTAssertNil(weakHost)
        XCTAssertNil(anchorFactory.activeHost)
    }

    @MainActor
    func testControllerShowsExactlyOnceUsingClickedSenderAnchor() {
        let harness = makeControllerHarness()
        let clickedButton = NSStatusBarButton(frame: .zero)

        harness.controller.handleStatusItemAction(
            sender: clickedButton,
            eventType: .leftMouseDown
        )

        XCTAssertEqual(harness.presenter.showCount, 1)
        XCTAssertEqual(harness.presenter.closeCount, 0)
        XCTAssertTrue(harness.anchorFactory.lastSourceView === clickedButton)
        XCTAssertTrue(
            harness.presenter.lastAnchor
                === harness.anchorFactory.activeHost?.positioningView
        )
        XCTAssertTrue(harness.panelPresentation.isVisible)
    }

    @MainActor
    func testStaleLogicalVisibilityWithoutNativePopoverCleansImmediately() {
        let harness = makeControllerHarness()
        harness.controller.handleStatusItemAction(
            sender: harness.statusButton,
            eventType: .leftMouseDown
        )
        weak let anchor = harness.anchorFactory.activeHost
        harness.presenter.isShown = false

        harness.controller.handleStatusItemAction(
            sender: harness.statusButton,
            eventType: .leftMouseDown
        )

        XCTAssertEqual(harness.presenter.showCount, 1)
        XCTAssertEqual(harness.presenter.closeCount, 0)
        XCTAssertFalse(harness.panelPresentation.isVisible)
        XCTAssertEqual(harness.anchorFactory.tearDownCount, 1)
        XCTAssertNil(harness.anchorFactory.activeHost)
        XCTAssertNil(anchor)
    }

    @MainActor
    func testAutomaticTransientWillCloseRetainsAnchorUntilDidClose() {
        let harness = makeControllerHarness()
        harness.controller.handleStatusItemAction(
            sender: harness.statusButton,
            eventType: .leftMouseDown
        )
        weak let anchor = harness.anchorFactory.activeHost

        harness.controller.popoverWillClose(
            Notification(name: NSPopover.willCloseNotification)
        )
        harness.presenter.completeClose()
        harness.controller.handleStatusItemAction(
            sender: harness.statusButton,
            eventType: .leftMouseDown
        )

        XCTAssertEqual(harness.presenter.showCount, 1)
        XCTAssertEqual(harness.presenter.closeCount, 0)
        XCTAssertFalse(harness.presenter.isShown)
        XCTAssertTrue(harness.panelPresentation.isVisible)
        XCTAssertEqual(harness.anchorFactory.tearDownCount, 0)
        XCTAssertNotNil(anchor)
        XCTAssertTrue(harness.anchorFactory.activeHost === anchor)

        harness.controller.popoverDidClose(
            Notification(name: NSPopover.didCloseNotification)
        )

        XCTAssertFalse(harness.panelPresentation.isVisible)
        XCTAssertEqual(harness.anchorFactory.tearDownCount, 1)
        XCTAssertNil(anchor)
        XCTAssertNil(harness.anchorFactory.activeHost)
    }

    @MainActor
    func testEscapeWillCloseIsIdempotentAndPreventsReopenUntilDidClose() {
        let harness = makeControllerHarness()
        harness.controller.handleStatusItemAction(
            sender: harness.statusButton,
            eventType: .leftMouseDown
        )
        weak let firstAnchor = harness.anchorFactory.activeHost

        harness.controller.popoverWillClose(
            Notification(name: NSPopover.willCloseNotification)
        )
        harness.controller.popoverWillClose(
            Notification(name: NSPopover.willCloseNotification)
        )
        harness.presenter.completeClose()
        harness.controller.handleStatusItemAction(
            sender: harness.statusButton,
            eventType: .leftMouseDown
        )

        XCTAssertEqual(harness.presenter.showCount, 1)
        XCTAssertEqual(harness.presenter.closeCount, 0)
        XCTAssertTrue(harness.panelPresentation.isVisible)
        XCTAssertEqual(harness.anchorFactory.tearDownCount, 0)
        XCTAssertNotNil(firstAnchor)
        XCTAssertTrue(harness.anchorFactory.activeHost === firstAnchor)

        harness.controller.popoverDidClose(
            Notification(name: NSPopover.didCloseNotification)
        )
        XCTAssertFalse(harness.panelPresentation.isVisible)
        XCTAssertEqual(harness.anchorFactory.tearDownCount, 1)
        XCTAssertNil(firstAnchor)

        harness.controller.handleStatusItemAction(
            sender: harness.statusButton,
            eventType: .leftMouseDown
        )
        XCTAssertEqual(harness.presenter.showCount, 2)
        XCTAssertEqual(harness.anchorFactory.creationCount, 2)
        XCTAssertTrue(harness.panelPresentation.isVisible)
    }

    @MainActor
    func testNewPresentationClearsStaleWillCloseBoundary() {
        let harness = makeControllerHarness()
        harness.controller.popoverWillClose(
            Notification(name: NSPopover.willCloseNotification)
        )

        harness.controller.handleStatusItemAction(
            sender: harness.statusButton,
            eventType: .leftMouseDown
        )
        XCTAssertEqual(harness.presenter.showCount, 1)
        XCTAssertTrue(harness.panelPresentation.isVisible)

        harness.presenter.isShown = false
        harness.controller.handleStatusItemAction(
            sender: harness.statusButton,
            eventType: .leftMouseDown
        )

        XCTAssertFalse(harness.panelPresentation.isVisible)
        XCTAssertEqual(harness.anchorFactory.tearDownCount, 1)
        XCTAssertNil(harness.anchorFactory.activeHost)
    }

    @MainActor
    func testAsyncCloseRetainsAnchorUntilDidCloseThenNextClickUsesNewAnchor() {
        let harness = makeControllerHarness()
        var firstButton: NSStatusBarButton? = NSStatusBarButton(frame: .zero)
        weak let weakFirstButton = firstButton
        let secondButton = NSStatusBarButton(frame: .zero)

        harness.controller.handleStatusItemAction(
            sender: firstButton,
            eventType: .leftMouseDown
        )
        harness.controller.handleStatusItemAction(
            sender: secondButton,
            eventType: .leftMouseDown
        )

        weak let firstAnchor = harness.anchorFactory.activeHost
        XCTAssertTrue(harness.panelPresentation.isVisible)
        XCTAssertEqual(harness.presenter.showCount, 1)
        XCTAssertEqual(harness.presenter.closeCount, 1)
        XCTAssertFalse(harness.presenter.isShown)
        XCTAssertEqual(harness.anchorFactory.tearDownCount, 0)
        XCTAssertNotNil(firstAnchor)
        XCTAssertTrue(
            harness.anchorFactory.activeHost === firstAnchor
        )

        harness.controller.popoverWillClose(
            Notification(name: NSPopover.willCloseNotification)
        )
        harness.controller.handleStatusItemAction(
            sender: secondButton,
            eventType: .leftMouseDown
        )
        XCTAssertEqual(harness.presenter.closeCount, 1)
        XCTAssertTrue(harness.panelPresentation.isVisible)
        XCTAssertEqual(harness.anchorFactory.tearDownCount, 0)
        XCTAssertTrue(harness.anchorFactory.activeHost === firstAnchor)

        firstButton = nil
        XCTAssertNil(weakFirstButton)
        XCTAssertNotNil(firstAnchor)

        harness.presenter.completeClose()
        harness.controller.popoverDidClose(
            Notification(name: NSPopover.didCloseNotification)
        )
        XCTAssertFalse(harness.panelPresentation.isVisible)
        XCTAssertEqual(harness.presenter.showCount, 1)
        XCTAssertEqual(harness.anchorFactory.tearDownCount, 1)
        XCTAssertNil(firstAnchor)
        XCTAssertNil(harness.anchorFactory.activeHost)

        harness.controller.handleStatusItemAction(
            sender: secondButton,
            eventType: .leftMouseDown
        )

        XCTAssertEqual(harness.presenter.showCount, 2)
        XCTAssertEqual(harness.presenter.closeCount, 1)
        XCTAssertTrue(harness.anchorFactory.lastSourceView === secondButton)
        XCTAssertEqual(harness.anchorFactory.creationCount, 2)
        XCTAssertTrue(harness.panelPresentation.isVisible)
    }

    @MainActor
    func testRefusedCloseWhileNestedInfoIsOpenRetainsAnchorAndCanRetry() {
        let harness = makeControllerHarness()
        harness.presenter.closeBehavior = .refused
        harness.controller.handleStatusItemAction(
            sender: harness.statusButton,
            eventType: .leftMouseDown
        )
        weak let anchor = harness.anchorFactory.activeHost

        harness.controller.handleStatusItemAction(
            sender: harness.statusButton,
            eventType: .leftMouseDown
        )
        harness.controller.handleStatusItemAction(
            sender: harness.statusButton,
            eventType: .leftMouseDown
        )

        XCTAssertEqual(harness.presenter.showCount, 1)
        XCTAssertEqual(harness.presenter.closeCount, 2)
        XCTAssertTrue(harness.presenter.isShown)
        XCTAssertTrue(harness.panelPresentation.isVisible)
        XCTAssertEqual(harness.anchorFactory.creationCount, 1)
        XCTAssertEqual(harness.anchorFactory.tearDownCount, 0)
        XCTAssertNotNil(anchor)
        XCTAssertTrue(harness.anchorFactory.activeHost === anchor)

        harness.controller.popoverWillClose(
            Notification(name: NSPopover.willCloseNotification)
        )
        harness.presenter.completeClose()
        harness.controller.popoverDidClose(
            Notification(name: NSPopover.didCloseNotification)
        )

        XCTAssertFalse(harness.panelPresentation.isVisible)
        XCTAssertEqual(harness.anchorFactory.tearDownCount, 1)
        XCTAssertNil(anchor)
    }

    @MainActor
    func testSynchronousDelegateCloseCleansAnchorIdempotently() {
        let harness = makeControllerHarness()
        harness.controller.handleStatusItemAction(
            sender: harness.statusButton,
            eventType: .leftMouseDown
        )
        weak let anchor = harness.anchorFactory.activeHost
        harness.presenter.closeBehavior = .synchronous
        weak let controller = harness.controller
        harness.presenter.onSynchronousClose = {
            controller?.popoverWillClose(
                Notification(name: NSPopover.willCloseNotification)
            )
            controller?.popoverDidClose(
                Notification(name: NSPopover.didCloseNotification)
            )
        }

        harness.controller.handleStatusItemAction(
            sender: harness.statusButton,
            eventType: .leftMouseDown
        )

        XCTAssertEqual(harness.presenter.closeCount, 1)
        XCTAssertFalse(harness.presenter.isShown)
        XCTAssertFalse(harness.panelPresentation.isVisible)
        XCTAssertEqual(harness.anchorFactory.tearDownCount, 1)
        XCTAssertNil(anchor)
        XCTAssertNil(harness.anchorFactory.activeHost)

        harness.controller.popoverDidClose(
            Notification(name: NSPopover.didCloseNotification)
        )
        XCTAssertEqual(harness.anchorFactory.tearDownCount, 1)
    }

    @MainActor
    func testStatusItemDispatchMaskAvoidsMouseUpAndRightClickDoubleFire() {
        let harness = makeControllerHarness()
        let configuredMask = harness.statusButton.sendAction(on: [])
        XCTAssertEqual(
            configuredMask,
            Int(MenuBarStatusItemController.actionEventMask.rawValue)
        )
        harness.statusButton.sendAction(
            on: MenuBarStatusItemController.actionEventMask
        )

        harness.controller.handleStatusItemAction(
            sender: harness.statusButton,
            eventType: .rightMouseDown
        )
        harness.controller.handleStatusItemAction(
            sender: harness.statusButton,
            eventType: .leftMouseUp
        )
        XCTAssertEqual(harness.presenter.showCount, 0)
        XCTAssertEqual(harness.presenter.closeCount, 0)

        harness.controller.handleStatusItemAction(
            sender: harness.statusButton,
            eventType: .leftMouseDown
        )
        harness.controller.handleStatusItemAction(
            sender: harness.statusButton,
            eventType: .leftMouseUp
        )
        XCTAssertEqual(harness.presenter.showCount, 1)
        XCTAssertEqual(harness.presenter.closeCount, 0)
    }

    @MainActor
    func testStatusItemPerformClickPreservesKeyboardAccessibilityActionPath() {
        let harness = makeControllerHarness()

        harness.statusButton.performClick(nil)

        XCTAssertEqual(harness.presenter.showCount, 1)
        XCTAssertEqual(harness.presenter.closeCount, 0)
        XCTAssertTrue(
            harness.anchorFactory.lastSourceView === harness.statusButton
        )
        XCTAssertTrue(harness.panelPresentation.isVisible)
    }

    @MainActor
    func testAccountDetailsScrollConfiguratorIsIdempotentAcrossRecreation() {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.scrollerStyle = .legacy
        scrollView.autohidesScrollers = false
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .black
        scrollView.verticalScroller?.controlSize = .regular

        let documentView = NSView()
        let firstProbe = NSView()
        documentView.addSubview(firstProbe)
        scrollView.documentView = documentView

        XCTAssertTrue(
            AccountDetailsScrollViewConfigurator
                .configureEnclosingScrollView(from: firstProbe)
        )
        XCTAssertEqual(scrollView.scrollerStyle, .overlay)
        XCTAssertTrue(scrollView.autohidesScrollers)
        XCTAssertFalse(scrollView.drawsBackground)
        XCTAssertEqual(scrollView.backgroundColor, .clear)
        XCTAssertEqual(scrollView.verticalScroller?.controlSize, .mini)
        XCTAssertTrue(scrollView.hasVerticalScroller)

        let secondProbe = NSView()
        documentView.addSubview(secondProbe)
        XCTAssertTrue(
            AccountDetailsScrollViewConfigurator
                .configureEnclosingScrollView(from: secondProbe)
        )
        XCTAssertEqual(scrollView.scrollerStyle, .overlay)
        XCTAssertTrue(scrollView.autohidesScrollers)
        XCTAssertFalse(scrollView.drawsBackground)
        XCTAssertEqual(scrollView.verticalScroller?.controlSize, .mini)
    }

    @MainActor
    func testAccountDetailsScrollConfiguratorIgnoresDetachedProbe() {
        XCTAssertFalse(
            AccountDetailsScrollViewConfigurator
                .configureEnclosingScrollView(from: NSView())
        )
    }

    @MainActor
    func testSwiftUIRecreationKeepsAccountDetailsScrollerOverlayConfigured() throws {
        let hostingView = NSHostingView(rootView: accountDetailsScrollFixture("first"))
        hostingView.frame = NSRect(x: 0, y: 0, width: 360, height: 180)
        hostingView.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.01))

        let firstScrollView = try XCTUnwrap(findScrollView(in: hostingView))
        assertAccountDetailsScrollerConfiguration(firstScrollView)

        hostingView.rootView = accountDetailsScrollFixture("second")
        hostingView.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.01))

        let recreatedScrollView = try XCTUnwrap(findScrollView(in: hostingView))
        assertAccountDetailsScrollerConfiguration(recreatedScrollView)
    }

    @MainActor
    func testScrollCoordinatorDetachesFromRealHostedScrollView() throws {
        var hostingView: NSHostingView<AnyView>? = makeUnconfiguredHostingView(
            "attached"
        )
        var scrollView: NSScrollView? = try XCTUnwrap(
            findScrollView(in: XCTUnwrap(hostingView))
        )
        let probe = NSView()
        scrollView?.documentView?.addSubview(probe)
        let coordinator = AccountDetailsScrollViewConfigurator.Coordinator()

        coordinator.configureAfterMount(from: probe)
        assertAccountDetailsScrollerConfiguration(try XCTUnwrap(scrollView))

        probe.removeFromSuperview()
        coordinator.configureAfterMount(from: probe)
        XCTAssertNil(coordinator.observedScrollViewForTesting)
        scrollView?.scrollerStyle = .legacy
        runMainLoop()
        XCTAssertEqual(scrollView?.scrollerStyle, .legacy)

        AccountDetailsScrollViewConfigurator.dismantleNSView(
            probe,
            coordinator: coordinator
        )
        scrollView = nil
        hostingView = nil
        runMainLoop()
    }

    @MainActor
    func testScrollCoordinatorRebindsBetweenRealHostedScrollViews() throws {
        var firstHostingView: NSHostingView<AnyView>? =
            makeUnconfiguredHostingView("first")
        let secondHostingView = makeUnconfiguredHostingView("second")
        var firstScrollView: NSScrollView? = try XCTUnwrap(
            findScrollView(in: XCTUnwrap(firstHostingView))
        )
        let secondScrollView = try XCTUnwrap(findScrollView(in: secondHostingView))
        let firstProbe = NSView()
        let secondProbe = NSView()
        firstScrollView?.documentView?.addSubview(firstProbe)
        secondScrollView.documentView?.addSubview(secondProbe)
        let coordinator = AccountDetailsScrollViewConfigurator.Coordinator()

        coordinator.configureAfterMount(from: firstProbe)
        coordinator.configureAfterMount(from: secondProbe)
        runMainLoop()

        firstScrollView?.scrollerStyle = .legacy
        secondScrollView.scrollerStyle = .legacy
        runMainLoop()
        XCTAssertEqual(firstScrollView?.scrollerStyle, .legacy)
        assertAccountDetailsScrollerConfiguration(secondScrollView)

        coordinator.configureAfterMount(from: secondProbe)
        assertAccountDetailsScrollerConfiguration(secondScrollView)
        XCTAssertTrue(
            coordinator.observedScrollViewForTesting === secondScrollView
        )

        firstProbe.removeFromSuperview()
        firstScrollView = nil
        firstHostingView = nil
        runMainLoop()
    }

    @MainActor
    func testScrollCoordinatorObservationDoesNotRetainDetachedScrollView() {
        let coordinator = AccountDetailsScrollViewConfigurator.Coordinator()
        weak var weakScrollView: NSScrollView?

        autoreleasepool {
            let scrollView = NSScrollView()
            let documentView = NSView()
            let probe = NSView()
            documentView.addSubview(probe)
            scrollView.documentView = documentView
            weakScrollView = scrollView

            coordinator.configureAfterMount(from: probe)
            XCTAssertTrue(
                coordinator.observedScrollViewForTesting === scrollView
            )
            coordinator.detach()
            XCTAssertNil(coordinator.observedScrollViewForTesting)
        }

        XCTAssertNil(weakScrollView)
    }

    @MainActor
    private func accountDetailsScrollFixture(_ value: String) -> AnyView {
        AnyView(
            ScrollView {
                Text(value)
                    .frame(height: 400)
                    .background {
                        AccountDetailsScrollViewConfigurator()
                    }
            }
            .frame(width: 360, height: 180)
        )
    }

    @MainActor
    private func makeAccountDetailsHostingView(
        _ value: String
    ) -> NSHostingView<AnyView> {
        let hostingView = NSHostingView(
            rootView: accountDetailsScrollFixture(value)
        )
        hostingView.frame = NSRect(x: 0, y: 0, width: 360, height: 180)
        hostingView.layoutSubtreeIfNeeded()
        runMainLoop()
        return hostingView
    }

    @MainActor
    private func makeUnconfiguredHostingView(
        _ value: String
    ) -> NSHostingView<AnyView> {
        let hostingView = NSHostingView(
            rootView: AnyView(
                ScrollView {
                    Text(value)
                        .frame(height: 400)
                }
                .frame(width: 360, height: 180)
            )
        )
        hostingView.frame = NSRect(x: 0, y: 0, width: 360, height: 180)
        hostingView.layoutSubtreeIfNeeded()
        runMainLoop()
        return hostingView
    }

    @MainActor
    private func findScrollView(in view: NSView) -> NSScrollView? {
        if let scrollView = view as? NSScrollView {
            return scrollView
        }
        return view.subviews.lazy.compactMap(findScrollView(in:)).first
    }

    @MainActor
    private func assertAccountDetailsScrollerConfiguration(
        _ scrollView: NSScrollView,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(scrollView.scrollerStyle, .overlay, file: file, line: line)
        XCTAssertTrue(scrollView.autohidesScrollers, file: file, line: line)
        XCTAssertFalse(scrollView.drawsBackground, file: file, line: line)
        XCTAssertEqual(
            scrollView.verticalScroller?.controlSize,
            .mini,
            file: file,
            line: line
        )
    }

    @MainActor
    private func makeControllerHarness() -> MenuBarControllerHarness {
        let storageDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let suiteName = "MenuBarPopoverLifecycleTests.\(UUID().uuidString)"
        let userDefaults = UserDefaults(suiteName: suiteName)!
        addTeardownBlock {
            try? FileManager.default.removeItem(at: storageDirectory)
            userDefaults.removePersistentDomain(forName: suiteName)
        }
        let appModel = AppModel(
            storageDirectory: storageDirectory,
            userDefaults: userDefaults
        )
        let languagePreference = AppLanguagePreference(
            userDefaults: userDefaults
        )
        let statusButton = NSStatusBarButton(frame: .zero)
        let presenter = MenuBarPopoverPresenterSpy()
        let anchorFactory = MenuBarPopoverAnchorHostFactorySpy()
        let panelPresentation = MenuBarPanelPresentationState()
        let controller = MenuBarStatusItemController(
            appModelForTesting: appModel,
            appLanguagePreference: languagePreference,
            statusButton: statusButton,
            popoverPresenter: presenter,
            popoverAnchorFactory: anchorFactory,
            panelPresentation: panelPresentation
        )
        return MenuBarControllerHarness(
            controller: controller,
            statusButton: statusButton,
            presenter: presenter,
            anchorFactory: anchorFactory,
            panelPresentation: panelPresentation
        )
    }

    @MainActor
    private func runMainLoop() {
        RunLoop.main.run(until: Date().addingTimeInterval(0.01))
    }
}

@MainActor
private struct MenuBarControllerHarness {
    let controller: MenuBarStatusItemController
    let statusButton: NSStatusBarButton
    let presenter: MenuBarPopoverPresenterSpy
    let anchorFactory: MenuBarPopoverAnchorHostFactorySpy
    let panelPresentation: MenuBarPanelPresentationState
}

private enum MenuBarPopoverCloseBehavior {
    case asynchronous
    case refused
    case synchronous
}

@MainActor
private final class MenuBarPopoverPresenterSpy: MenuBarPopoverPresenting {
    var isShown = false
    var succeedsOnShow = true
    var closeBehavior: MenuBarPopoverCloseBehavior = .asynchronous
    var onSynchronousClose: (() -> Void)?
    private(set) var showCount = 0
    private(set) var closeCount = 0
    private(set) weak var lastAnchor: NSView?

    func show(
        relativeTo positioningRect: NSRect,
        of positioningView: NSView,
        preferredEdge: NSRectEdge
    ) {
        showCount += 1
        lastAnchor = positioningView
        isShown = succeedsOnShow
    }

    func performClose(_ sender: Any?) {
        closeCount += 1
        switch closeBehavior {
        case .asynchronous:
            isShown = false
        case .refused:
            break
        case .synchronous:
            isShown = false
            onSynchronousClose?()
        }
    }

    func completeClose() {
        isShown = false
    }
}

@MainActor
private final class MenuBarPopoverAnchorHostFactorySpy:
    MenuBarPopoverAnchorHostFactory
{
    var returnsHost = true
    var sourceScreenRects: [ObjectIdentifier: NSRect] = [:]
    private(set) var creationCount = 0
    private(set) var tearDownCount = 0
    private(set) var capturedScreenRects: [NSRect] = []
    private(set) weak var lastSourceView: NSView?
    private(set) weak var activeHost: MenuBarPopoverAnchorHostSpy?

    func makeAnchorHost(
        relativeTo positioningRect: NSRect,
        of positioningView: NSView
    ) -> (any MenuBarPopoverAnchorHosting)? {
        creationCount += 1
        lastSourceView = positioningView
        guard returnsHost else { return nil }

        let screenRect = sourceScreenRects[ObjectIdentifier(positioningView)]
            ?? NSRect(x: CGFloat(creationCount * 100), y: 500, width: 24, height: 24)
        capturedScreenRects.append(screenRect)
        let host = MenuBarPopoverAnchorHostSpy(
            screenRect: screenRect,
            onTearDown: { [weak self] in
                self?.tearDownCount += 1
            }
        )
        activeHost = host
        return host
    }
}

@MainActor
private final class MenuBarPopoverAnchorHostSpy:
    MenuBarPopoverAnchorHosting
{
    let screenRect: NSRect
    let positioningView: NSView
    var positioningRect: NSRect {
        positioningView.bounds
    }

    private var didTearDown = false
    private let onTearDown: () -> Void

    init(screenRect: NSRect, onTearDown: @escaping () -> Void) {
        self.screenRect = screenRect
        positioningView = NSView(
            frame: NSRect(origin: .zero, size: screenRect.size)
        )
        self.onTearDown = onTearDown
    }

    func tearDown() {
        guard !didTearDown else { return }
        didTearDown = true
        onTearDown()
    }
}
#endif
