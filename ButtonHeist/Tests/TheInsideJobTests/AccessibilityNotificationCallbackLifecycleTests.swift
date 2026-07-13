#if canImport(UIKit)
import Foundation
import XCTest

import TheScore
@testable import TheInsideJob

@MainActor
final class AccessibilityNotificationCallbackLifecycleTests: XCTestCase {
    func testStopRejectsCallbackRetainedByPrivateSPI() throws {
        let harness = CallbackHarness()
        let observer = makeObserver(harness: harness)
        defer { observer.uninstall() }
        let bus = AccessibilityNotificationBus()
        observer.subscribe(bus)
        let callback = try XCTUnwrap(harness.callbacks.first)
        let actionWindow = bus.beginActionWindow()

        observer.uninstall()
        callback(1000, nil, nil)

        XCTAssertTrue(actionWindow.capture()?.events.isEmpty == true)
        actionWindow.cancel()
        XCTAssertEqual(observer.latestSequence, 0)
        XCTAssertEqual(harness.uninstallCount, 1)
    }

    func testRemovedCallbackCannotPublishIntoLaterActionWindow() throws {
        let harness = CallbackHarness()
        let observer = makeObserver(harness: harness)
        defer { observer.uninstall() }
        let original = AccessibilityNotificationBus()
        let replacement = AccessibilityNotificationBus()
        observer.subscribe(original)
        let removedCallback = try XCTUnwrap(harness.callbacks.first)

        observer.unsubscribe(original)
        observer.subscribe(replacement)
        XCTAssertEqual(harness.callbacks.count, 2)
        let actionWindow = replacement.beginActionWindow()

        removedCallback(1000, nil, nil)
        removedCallback(1005, nil, nil)
        removedCallback(1008, "Stale announcement" as NSString, nil)

        let staleBatch = try XCTUnwrap(actionWindow.capture())
        XCTAssertEqual(actionWindow.cursor.sequence, 0)
        XCTAssertTrue(staleBatch.events.isEmpty)
        XCTAssertEqual(staleBatch.through.sequence, 0)
        actionWindow.cancel()
        XCTAssertEqual(observer.latestSequence, 0)

        let activeCallback = try XCTUnwrap(harness.callbacks.last)
        let activeWindow = replacement.beginActionWindow()
        activeCallback(1000, nil, nil)
        activeCallback(1005, nil, nil)
        activeCallback(1008, "Current announcement" as NSString, nil)

        let activeBatch = try XCTUnwrap(activeWindow.capture())
        activeWindow.cancel()
        XCTAssertEqual(activeWindow.cursor.sequence, 0)
        XCTAssertEqual(activeBatch.events.map(\.sequence), [1, 2, 3])
        XCTAssertEqual(activeBatch.through.sequence, 3)
        XCTAssertEqual(
            activeBatch.events.map(\.kind),
            [.screenChanged, .elementChanged(.value), .announcement]
        )
        XCTAssertEqual(observer.latestSequence, 3)
    }

    func testCallbacksDeliveredIntoOpenActionWindowExtendSameRangeWithoutLoss() throws {
        let harness = CallbackHarness()
        let observer = makeObserver(harness: harness)
        defer { observer.uninstall() }
        let bus = AccessibilityNotificationBus()
        observer.subscribe(bus)
        let callback = try XCTUnwrap(harness.callbacks.first)
        let actionWindow = bus.beginActionWindow()

        callback(1000, nil, nil)
        let firstBatch = try XCTUnwrap(actionWindow.capture())
        callback(UInt32.max, nil, nil)
        let secondBatch = try XCTUnwrap(actionWindow.capture())

        XCTAssertEqual(actionWindow.cursor.sequence, 0)
        XCTAssertEqual(firstBatch.events.map(\.sequence), [1])
        XCTAssertEqual(firstBatch.through.sequence, 1)
        XCTAssertEqual(secondBatch.events.map(\.sequence), [1, 2])
        XCTAssertEqual(secondBatch.through.sequence, 2)
        XCTAssertEqual(secondBatch.events.map(\.kind), [.screenChanged, .unknown(.max)])
        XCTAssertNil(firstBatch.gap)
        XCTAssertNil(secondBatch.gap)
        actionWindow.cancel()
    }

    func testCallbackImmediatelyNormalizesMutableObjectiveCPayload() throws {
        let harness = CallbackHarness()
        let observer = makeObserver(harness: harness)
        defer { observer.uninstall() }
        let bus = AccessibilityNotificationBus()
        observer.subscribe(bus)
        let callback = try XCTUnwrap(harness.callbacks.first)
        let mutablePayload = NSMutableString(string: "Original announcement")
        let actionWindow = bus.beginActionWindow()

        callback(1008, mutablePayload, nil)
        mutablePayload.setString("Mutated after callback")

        let events = actionWindow.capture()?.events ?? []
        actionWindow.cancel()
        XCTAssertEqual(events.count, 1)
        let event = try XCTUnwrap(events.first)
        guard case .string(let value) = event.notificationData else {
            return XCTFail("Expected normalized string payload")
        }
        XCTAssertEqual(value, "Original announcement")
    }

    private func makeObserver(harness: CallbackHarness) -> AccessibilityNotificationObserver {
        AccessibilityNotificationObserver(
            installCallbackForTesting: { callback in
                harness.install(callback)
            },
            uninstallCallbackForTesting: {
                harness.uninstall()
            }
        )
    }

    @MainActor
    private final class CallbackHarness {
        private(set) var callbacks: [AccessibilityNotificationCallback] = []
        private(set) var uninstallCount = 0

        func install(_ callback: @escaping AccessibilityNotificationCallback) {
            callbacks.append(callback)
        }

        func uninstall() {
            uninstallCount += 1
        }
    }
}

#endif
