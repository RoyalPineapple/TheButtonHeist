#if canImport(UIKit)
import Foundation
import Testing
@testable import TheInsideJob

@Suite("ObjCRuntime swizzling", .serialized)
@MainActor
struct ObjCRuntimeSwizzlingTests {
    @Test("Typed object invocation composes original-first and restores")
    func objectInvocationComposesAndRestores() throws {
        let fixture = ObjCRuntimeSwizzleFixture()
        let method = ObjCRuntime.ObjectMethod<ObjCRuntime.ObjectArgument<NSObject>>(
            "observeObject:"
        )
        let swizzle = try ObjCRuntime.swizzle(
            method,
            on: ObjCRuntime.ClassName("BHObjCRuntimeSwizzleFixture")
        ) { invocation in
            fixture.events.append("replacement-before")
            invocation.callOriginal()
            fixture.events.append("replacement-after")
        }

        fixture.observeObject(NSObject())
        #expect(fixture.events == ["replacement-before", "original", "replacement-after"])

        #expect(swizzle.restore() == .restored)
        fixture.events.removeAll()
        fixture.observeObject(NSObject())
        #expect(fixture.events == ["original"])
    }

    @Test("Typed object-bool invocation preserves arguments")
    func objectBoolInvocationPreservesArguments() throws {
        let fixture = ObjCRuntimeSwizzleFixture()
        let method = ObjCRuntime.ObjectMethod<ObjCRuntime.ObjectBoolArguments<NSObject>>(
            "observeObject:flag:"
        )
        let argument = NSObject()
        let swizzle = try ObjCRuntime.swizzle(
            method,
            on: ObjCRuntime.ClassName("BHObjCRuntimeSwizzleFixture")
        ) { invocation in
            #expect(invocation.argument === argument)
            #expect(invocation.flag)
            invocation.callOriginal()
        }
        defer { _ = swizzle.restore() }

        fixture.observeObject(argument, flag: true)
        #expect(fixture.events == ["original-true"])
    }

    @Test("Missing class fails before runtime mutation")
    func missingClassFails() {
        let method = ObjCRuntime.ObjectMethod<ObjCRuntime.ObjectArgument<NSObject>>(
            "observeObject:"
        )

        #expect(throws: ObjCRuntime.SwizzleInstallationError.classUnavailable(
            ObjCRuntime.ClassName("BHMissingSwizzleFixture")
        )) {
            _ = try ObjCRuntime.swizzle(
                method,
                on: ObjCRuntime.ClassName("BHMissingSwizzleFixture")
            ) { _ in }
        }
    }

    @Test("Mismatched phantom signature fails before runtime mutation")
    func mismatchedSignatureFails() {
        let method = ObjCRuntime.ObjectMethod<ObjCRuntime.ObjectBoolArguments<NSObject>>(
            "observeObject:"
        )
        let className = ObjCRuntime.ClassName("BHObjCRuntimeSwizzleFixture")

        #expect(throws: ObjCRuntime.SwizzleInstallationError.incompatibleSignature(
            className: className,
            method: "observeObject:"
        )) {
            _ = try ObjCRuntime.swizzle(method, on: className) { _ in }
        }
    }
}

@objc(BHObjCRuntimeSwizzleFixture)
private final class ObjCRuntimeSwizzleFixture: NSObject {
    var events: [String] = []

    @objc(observeObject:)
    dynamic func observeObject(_ object: NSObject) {
        events.append("original")
    }

    @objc(observeObject:flag:)
    dynamic func observeObject(_ object: NSObject, flag: Bool) {
        events.append("original-\(flag)")
    }
}
#endif
