#if canImport(UIKit)
#if DEBUG
import Darwin
import Foundation
import os.log
import UIKit

private let accessibilityNotificationLogger = ButtonHeistLog.logger(.insideJob(.accessibility))

// C ABI for the private AXRuntime function we hook. This mirrors the register
// shape observed in LLDB:
//   x0: notification code
//   x1: associated AX element
//   x2: notification payload
// The hook replacement and the original trampoline must use this exact ABI.
private typealias AccessibilityPostNotificationHookFunction = @convention(c) (
    UInt32,
    UnsafeRawPointer?,
    UnsafeRawPointer?
) -> Int32

// Private AccessibilitySupport switch that makes in-process AX notifications
// behave like test automation is active. This is a best-effort arming step; if
// the symbol is absent we still allow the hook installer to fail or succeed on
// its own merits.
private typealias SetUnitTestModeFunction = @convention(c) (Int32) -> Void

// Swift does not expose this libc cache-flush symbol directly. After changing
// executable memory, we must ask the CPU to forget any stale decoded
// instructions it may have cached for that address range.
@_silgen_name("sys_icache_invalidate")
private func sys_icache_invalidate(_ start: UnsafeRawPointer, _ len: Int)

// Rationale: singleton state is protected by `lock`; callbacks use copied weak subscribers.
// swiftlint:disable:next agent_unchecked_sendable_no_comment
final class AccessibilityNotificationObserver: @unchecked Sendable {
    static let shared = AccessibilityNotificationObserver()

    private let lock = NSLock()
    private var subscribers: [ObjectIdentifier: WeakAccessibilityNotificationSubscriber] = [:]
    private var latestSequenceStorage: UInt64 = 0

    var latestSequence: UInt64 {
        lock.lock()
        defer { lock.unlock() }
        return latestSequenceStorage
    }

    var hasSubscribers: Bool {
        lock.lock()
        defer { lock.unlock() }

        removeExpiredSubscribers()
        return !subscribers.isEmpty
    }

    private init() {}

    func subscribe(_ subscriber: AccessibilityNotificationBus) {
        addSubscriber(subscriber)
        setUnitTestModeIfAvailable()
        AccessibilityPostNotificationHookState.shared.install(axRuntimePath: axRuntimePath())
    }

    func unsubscribe(_ subscriber: AccessibilityNotificationBus) {
        lock.lock()
        defer { lock.unlock() }

        subscribers[ObjectIdentifier(subscriber)] = nil
        removeExpiredSubscribers()
    }

    func uninstall() {
        removeAllSubscribers()
        AccessibilityPostNotificationHookState.shared.uninstall()
    }

    fileprivate func rebroadcast(
        code: UInt32,
        notificationData: CapturedAccessibilityNotificationPayload,
        associatedElement: CapturedAccessibilityNotificationPayload
    ) {
        let subscribers = recordAndCopySubscribers()
        for subscriber in subscribers {
            subscriber.record(
                code: code,
                notificationData: notificationData,
                associatedElement: associatedElement
            )
        }
    }

    private func addSubscriber(_ subscriber: AccessibilityNotificationBus) {
        lock.lock()
        defer { lock.unlock() }

        removeExpiredSubscribers()
        subscribers[ObjectIdentifier(subscriber)] = WeakAccessibilityNotificationSubscriber(subscriber)
    }

    private func removeAllSubscribers() {
        lock.lock()
        defer { lock.unlock() }

        subscribers.removeAll()
    }

    private func recordAndCopySubscribers() -> [AccessibilityNotificationBus] {
        lock.lock()
        defer { lock.unlock() }

        latestSequenceStorage += 1
        removeExpiredSubscribers()
        return subscribers.values.compactMap(\.subscriber)
    }

    private func removeExpiredSubscribers() {
        subscribers = subscribers.filter { $0.value.subscriber != nil }
    }

    private func setUnitTestModeIfAvailable() {
        let path = libAccessibilityPath()
        guard let handle = dlopen(path, RTLD_LOCAL),
              let symbol = dlsym(handle, "_AXSSetInUnitTestMode")
        else {
            accessibilityNotificationLogger.debug("_AXSSetInUnitTestMode not found")
            return
        }
        let setUnitTestMode = unsafeBitCast(symbol, to: SetUnitTestModeFunction.self)
        setUnitTestMode(1)
        accessibilityNotificationLogger.info("Armed accessibility notification callback via _AXSSetInUnitTestMode")
    }

    private func axRuntimePath(environment: [String: String] = ProcessInfo.processInfo.environment) -> String {
        let framework = "/System/Library/PrivateFrameworks/AXRuntime.framework/AXRuntime"
        guard let simulatorRoot = environment[AccessibilityEnvironmentKey.iPhoneSimulatorRoot.rawValue] else {
            return framework
        }
        return (simulatorRoot as NSString).appendingPathComponent(framework)
    }
}

private struct WeakAccessibilityNotificationSubscriber {
    weak var subscriber: AccessibilityNotificationBus?

    init(_ subscriber: AccessibilityNotificationBus) {
        self.subscriber = subscriber
    }
}

// Rationale: global hook state is protected by `lock`, which is held through trampoline calls.
// swiftlint:disable:next agent_unchecked_sendable_no_comment
private final class AccessibilityPostNotificationHookState: @unchecked Sendable {
    static let shared = AccessibilityPostNotificationHookState()

    private let lock = NSRecursiveLock()
    private var installedHook: AccessibilityPostNotificationHookInstaller.InstalledHook?

    func install(axRuntimePath: String) {
        lock.lock()
        defer { lock.unlock() }

        guard installedHook == nil else {
            return
        }

        do {
            let installedHook = try AccessibilityPostNotificationHookInstaller.install(
                axRuntimePath: axRuntimePath,
                replacement: BHAccessibilityPostNotificationHook
            )
            self.installedHook = installedHook
            accessibilityNotificationLogger.info("Installed accessibility post notification inline hook")
        } catch {
            accessibilityNotificationLogger.info(
                "accessibility post notification inline hook install failed: \(String(describing: error), privacy: .public)"
            )
        }
    }

    func uninstall() {
        lock.lock()
        defer { lock.unlock() }

        guard let installedHook else { return }
        do {
            try installedHook.uninstall()
        } catch {
            accessibilityNotificationLogger.info(
                "accessibility post notification inline hook uninstall failed: \(String(describing: error), privacy: .public)"
            )
        }
        self.installedHook = nil
        accessibilityNotificationLogger.info("Removed accessibility post notification inline hook")
    }

    func recordAndForward(
        code: UInt32,
        associatedElement: UnsafeRawPointer?,
        notificationData: UnsafeRawPointer?
    ) -> Int32 {
        lock.lock()
        defer { lock.unlock() }

        // This function is called from the patched AXRuntime entrypoint, on
        // whatever thread posted the notification. Keep the fast path boring:
        // if nobody is listening, immediately chain to the original
        // implementation without converting ObjC objects or logging.
        //
        // Keep this lock held until the original implementation returns. The
        // callable original lives in our trampoline page; uninstall must not be
        // able to unmap that page while an in-flight notification is about to
        // branch through it. The lock is recursive because AXRuntime may post
        // another accessibility notification while we are forwarding this one.
        guard let original = installedHook?.originalImplementation else { return 0 }
        guard AccessibilityNotificationObserver.shared.hasSubscribers else {
            return original(code, associatedElement, notificationData)
        }
        autoreleasepool {
            AccessibilityNotificationObserver.shared.rebroadcast(
                code: code,
                notificationData: Self.payload(from: notificationData),
                associatedElement: Self.payload(from: associatedElement)
            )
        }
        return original(code, associatedElement, notificationData)
    }

    private static func payload(from pointer: UnsafeRawPointer?) -> CapturedAccessibilityNotificationPayload {
        CapturedAccessibilityNotificationPayload(object(from: pointer))
    }

    private static func object(from pointer: UnsafeRawPointer?) -> AnyObject? {
        guard let pointer else { return nil }
        return Unmanaged<AnyObject>.fromOpaque(pointer).takeUnretainedValue()
    }
}

/// Sealed unsafe container for the accessibility post notification hook.
///
/// Callers get one safe-ish Swift operation:
///
///     install(axRuntimePath:replacement:) -> InstalledHook
///
/// Everything below this line is intentionally private implementation detail.
/// The rest of Button Heist should not know about ARM instructions, writable
/// code pages, `dlsym`, or trampoline memory.
///
/// This is like Objective-C method swizzling in spirit, but one level lower.
/// With ObjC swizzling, the runtime has a method table, so you swap one IMP for
/// another and keep the old IMP to call through. AXRuntime gives us a plain C
/// function, not a method table. To get equivalent behavior, we patch the
/// function entry itself and keep a trampoline that calls the original bytes.
///
/// The idea in plain terms:
/// 1. UIKit and SwiftUI eventually call an AXRuntime C function when they
///    post accessibility notifications. Its private symbol name is
///    `AXPushNotificationToSystemForBroadcast`; the name is Apple terminology,
///    but the concept here is "post an accessibility notification."
/// 2. Machine code is just bytes in memory. The first few bytes of a function
///    are its entry instructions.
/// 3. We save those original entry bytes, then overwrite that function entry
///    with a tiny ARM64 jump to our Swift replacement function.
/// 4. We still need to call the real implementation. To do that, we allocate a
///    small executable buffer called a trampoline. The trampoline contains:
///       original entry bytes
///       jump back to the post-notification function after the overwritten bytes
///    Calling the trampoline is equivalent to calling the original function.
/// 5. On uninstall, we copy the saved bytes back into the original function
///    entry and release the trampoline page.
private enum AccessibilityPostNotificationHookInstaller {
    // Deliberately exact. If Apple renames this symbol, we do not fuzzy-search
    // AXRuntime for something hook-shaped. Guessing wrong here means patching
    // arbitrary executable memory. The safe failure mode is no hook.
    private static let symbolName = "AXPushNotificationToSystemForBroadcast"

    enum InstallError: Error {
        case runtimeUnavailable(String)
        case symbolUnavailable(String)
    }

    // Rationale: immutable owner for a loaded image handle plus the synchronized entry patch.
    // swiftlint:disable:next agent_unchecked_sendable_no_comment
    final class InstalledHook: @unchecked Sendable {
        // Callable copy of the original function entry. This points at our
        // trampoline, not at AXRuntime's now-patched entrypoint.
        let originalImplementation: AccessibilityPostNotificationHookFunction

        // Keep AXRuntime loaded for at least as long as the patch is installed.
        // The hook target address lives inside this image.
        private let runtimeHandle: UnsafeMutableRawPointer
        // Owns the actual function-entry bytes and executable trampoline page.
        private let entryPatch: ARM64FunctionEntryPatch

        fileprivate init(
            runtimeHandle: UnsafeMutableRawPointer,
            entryPatch: ARM64FunctionEntryPatch,
            originalImplementation: AccessibilityPostNotificationHookFunction
        ) {
            self.runtimeHandle = runtimeHandle
            self.entryPatch = entryPatch
            self.originalImplementation = originalImplementation
        }

        func uninstall() throws {
            try entryPatch.uninstall()
            // Intentionally do not `dlclose` `runtimeHandle`. AXRuntime is a
            // system framework already participating in process-global state;
            // unloading it after patch removal buys nothing and risks invalidating
            // addresses held elsewhere in the process.
            _ = runtimeHandle
        }
    }

    static func install(
        axRuntimePath: String,
        replacement: AccessibilityPostNotificationHookFunction
    ) throws -> InstalledHook {
        // Load the exact AXRuntime image for this process. On simulator we pass
        // the runtime-root path; on device this resolves to the system path.
        guard let runtimeHandle = dlopen(axRuntimePath, RTLD_NOW | RTLD_LOCAL) else {
            throw InstallError.runtimeUnavailable(axRuntimePath)
        }
        // Find the one private function we intentionally hook. This is an exact
        // lookup: no fallback names and no symbol scanning.
        guard let target = dlsym(runtimeHandle, symbolName) else {
            throw InstallError.symbolUnavailable(symbolName)
        }

        // Swift function values are typed. The patcher only knows how to write
        // an absolute machine address into the target entry, so convert the
        // replacement C-function value into its raw entry address.
        let replacementPointer = unsafeBitCast(replacement, to: UnsafeMutableRawPointer.self)
        let entryPatch = try ARM64FunctionEntryPatch.install(
            target: target,
            replacement: replacementPointer
        )
        return InstalledHook(
            runtimeHandle: runtimeHandle,
            entryPatch: entryPatch,
            originalImplementation: try entryPatch.typedOriginalImplementation(as: AccessibilityPostNotificationHookFunction.self)
        )
    }
}

enum ARM64HookError: Error, Equatable {
    // We only know how to encode ARM64 instructions.
    case unsupportedArchitecture
    // Function entries should be 4-byte aligned because ARM64 instructions are
    // 4 bytes wide.
    case unalignedFunctionEntry(UInt)
    // The replacement function must be a different entrypoint. Patching a
    // function to branch to itself would create an immediate loop.
    case replacementMatchesTarget
    // ARM64 instructions are 4 bytes wide. Any byte block we decode as
    // instructions must preserve that boundary.
    case invalidInstructionBlockByteCount(Int)
    // The first instructions already look like our absolute jump stub.
    case targetAlreadyPatched
    // The copied instructions depend on their original program-counter
    // location, so moving them into a trampoline would change behavior.
    case nonRelocatableInstruction(index: Int, instruction: UInt32)
    // The trampoline page must have room for the copied original entry plus
    // the jump back into the target function.
    case trampolineTooSmall(required: Int, available: Int)
    // The replacement stub must exactly cover the bytes we captured from the
    // original entry. Anything else would leave a partial instruction behind or
    // overwrite more than the trampoline can replay.
    case patchByteCountMismatch(expected: Int, actual: Int)
    // We only protect the code page that contains the function entry. If the
    // requested write would cross into another page, fail closed.
    case patchCrossesPageBoundary
    case trampolineAllocationFailed
    case trampolineProtectionFailed(errno: Int32)
    case trampolineAlreadySealed
    case trampolineNotExecutable
    case trampolineReleased
    case trampolineReleaseFailed(errno: Int32)
    case pageProtectionFailed(kern_return_t)
    case testProbeTargetUnavailable
}

// Owns one installed ARM64 function-entry patch.
//
// This type is deliberately not AX-specific. Its job is to compose small
// wrappers around unsafe operations in the order we need them:
// 1. Describe the target function entry and its code page.
// 2. Capture and validate the bytes that will be moved.
// 3. Build a trampoline that can call those original bytes.
// 4. Replace the target entry with an absolute jump to our replacement.
// 5. Restore the original bytes on uninstall.
// Rationale: installed patches are only reached through hook-state locking.
// swiftlint:disable:next agent_unchecked_sendable_no_comment
private final class ARM64FunctionEntryPatch: @unchecked Sendable {
    // We patch exactly four ARM64 instructions. That gives us enough room for:
    //   ldr x16, #8
    //   br x16
    //   8-byte absolute destination address
    private static let patchLength = 16

    private let entry: ARM64FunctionEntry
    private let originalEntry: ARM64InstructionBlock
    private let trampoline: ARM64TrampolinePage
    private var isInstalled = true

    private init(
        entry: ARM64FunctionEntry,
        originalEntry: ARM64InstructionBlock,
        trampoline: ARM64TrampolinePage
    ) {
        self.entry = entry
        self.originalEntry = originalEntry
        self.trampoline = trampoline
    }

    static func install(target: UnsafeMutableRawPointer, replacement: UnsafeMutableRawPointer) throws -> ARM64FunctionEntryPatch {
        #if arch(arm64)
        let entry = try ARM64FunctionEntry(target)
        guard target != replacement else {
            throw ARM64HookError.replacementMatchesTarget
        }

        let originalEntry = try ARM64InstructionBlock(reading: entry.pointer, byteCount: patchLength)
        try originalEntry.validateCanRunFromTrampoline()

        let trampoline = try ARM64TrampolinePage.allocate(pageSize: entry.pageSize)
        try trampoline.write(
            originalEntry: originalEntry,
            returnAddress: entry.pointer.advanced(by: originalEntry.byteCount)
        )
        try trampoline.sealExecutable()

        let replacementJump = ARM64AbsoluteJump(destinationAddress: UInt(bitPattern: replacement))
        guard replacementJump.bytes.count == originalEntry.byteCount else {
            throw ARM64HookError.patchByteCountMismatch(
                expected: originalEntry.byteCount,
                actual: replacementJump.bytes.count
            )
        }

        var shouldRestoreEntry = false
        defer {
            if shouldRestoreEntry {
                try? entry.restore(originalEntry)
            }
        }
        shouldRestoreEntry = true
        try entry.replaceEntry(with: replacementJump.bytes)

        let installedPatch = ARM64FunctionEntryPatch(
            entry: entry,
            originalEntry: originalEntry,
            trampoline: trampoline
        )
        shouldRestoreEntry = false
        return installedPatch
        #else
        throw ARM64HookError.unsupportedArchitecture
        #endif
    }

    func typedOriginalImplementation<T>(as type: T.Type) throws -> T {
        // The trampoline has the same call ABI as the target function because it
        // starts by executing the target's original entry instructions and then
        // jumps back into the target. Cast that executable address back into the
        // typed C function pointer the caller expects.
        try trampoline.typedFunction(as: type)
    }

    func uninstall() throws {
        guard isInstalled else { return }
        // Restore the exact bytes we overwrote. After this, future calls enter
        // AXRuntime directly again and the trampoline is no longer needed.
        try entry.restore(originalEntry)
        try trampoline.release()
        isInstalled = false
    }
}

private struct ARM64FunctionEntry {
    let pointer: UnsafeMutableRawPointer
    let page: ARM64CodePage

    var pageSize: vm_size_t {
        page.size
    }

    init(_ pointer: UnsafeMutableRawPointer) throws {
        let address = UInt(bitPattern: pointer)
        // Do not patch an address that cannot be an ARM64 instruction boundary.
        guard address.isMultiple(of: 4) else {
            throw ARM64HookError.unalignedFunctionEntry(address)
        }
        self.pointer = pointer
        self.page = ARM64CodePage(containing: pointer)
    }

    func replaceEntry(with bytes: [UInt8]) throws {
        try page.overwrite(pointer, with: bytes)
    }

    func restore(_ originalEntry: ARM64InstructionBlock) throws {
        try replaceEntry(with: originalEntry.bytes)
    }
}

struct ARM64InstructionBlock: Equatable {
    let bytes: [UInt8]

    var byteCount: Int {
        bytes.count
    }

    init(bytes: [UInt8]) throws {
        guard bytes.count.isMultiple(of: MemoryLayout<UInt32>.size) else {
            throw ARM64HookError.invalidInstructionBlockByteCount(bytes.count)
        }
        self.bytes = bytes
    }

    fileprivate init(reading pointer: UnsafeMutableRawPointer, byteCount: Int) throws {
        guard byteCount.isMultiple(of: MemoryLayout<UInt32>.size) else {
            throw ARM64HookError.invalidInstructionBlockByteCount(byteCount)
        }
        // Capture exactly the bytes we will overwrite. These are later copied
        // into the trampoline and also used to restore the original entry.
        self.bytes = Array(UnsafeBufferPointer(
            start: pointer.assumingMemoryBound(to: UInt8.self),
            count: byteCount
        ))
    }

    func validateCanRunFromTrampoline() throws {
        // Our own patch starts with "load absolute address into x16; branch x16".
        // Seeing that sequence means another install already modified this entry.
        if instructions.starts(with: [0x58000050, 0xd61f0200]) {
            throw ARM64HookError.targetAlreadyPatched
        }
        // We only copy instructions that are safe to run from the trampoline's
        // address. Any instruction that encodes a PC-relative target would point
        // somewhere else after being copied, so we fail closed.
        for (index, instruction) in instructions.enumerated()
            where Self.isPCRelativeInstruction(instruction) {
            throw ARM64HookError.nonRelocatableInstruction(index: index, instruction: instruction)
        }
    }

    private var instructions: [UInt32] {
        // Decode every 4 bytes as one little-endian ARM64 instruction. ARM64 is
        // fixed-width, so there is no variable-length instruction parsing here.
        stride(from: 0, to: bytes.count, by: MemoryLayout<UInt32>.size).map { offset in
            bytes[offset..<(offset + MemoryLayout<UInt32>.size)]
                .enumerated()
                .reduce(UInt32(0)) { partial, item in
                    partial | (UInt32(item.element) << UInt32(item.offset * 8))
                }
        }
    }

    private static func isPCRelativeInstruction(_ instruction: UInt32) -> Bool {
        // These masks recognize broad ARM64 instruction families whose operand
        // is relative to the program counter. The list is intentionally
        // conservative: rejecting a hook is better than relocating an
        // instruction we do not understand.
        switch instruction & 0x9f000000 {
        case 0x10000000, // adr
             0x90000000: // adrp
            return true
        default:
            break
        }

        switch instruction & 0xfc000000 {
        case 0x14000000, // b
             0x94000000: // bl
            return true
        default:
            break
        }

        switch instruction & 0xff000000 {
        case 0x54000000: // b.cond
            return true
        default:
            break
        }

        switch instruction & 0x7c000000 {
        case 0x34000000, // cbz/cbnz
             0x36000000: // tbz/tbnz
            return true
        default:
            break
        }

        return (instruction & 0x3b000000) == 0x18000000 // ldr literal
    }
}

// Rationale: trampoline pages are owned by one patch and never exposed outside this wrapper.
// swiftlint:disable:next agent_unchecked_sendable_no_comment
private final class ARM64TrampolinePage: @unchecked Sendable {
    private enum State {
        case writable
        case executable
        case released
    }

    private var pointerStorage: UnsafeMutableRawPointer?
    private var state = State.writable
    private let size: vm_size_t

    private func livePointer() throws -> UnsafeMutableRawPointer {
        guard let pointerStorage, state != .released else {
            throw ARM64HookError.trampolineReleased
        }
        return pointerStorage
    }

    private init(pointer: UnsafeMutableRawPointer, size: vm_size_t) {
        self.pointerStorage = pointer
        self.size = size
    }

    deinit {
        try? release()
    }

    static func allocate(pageSize: vm_size_t) throws -> ARM64TrampolinePage {
        // Allocate one scratch page for the trampoline. It starts writable so we
        // can copy bytes into it; after construction it becomes read+execute.
        guard let pointer = mmap(
            nil,
            Int(pageSize),
            PROT_READ | PROT_WRITE,
            MAP_PRIVATE | MAP_ANON,
            -1,
            0
        ), pointer != MAP_FAILED else {
            throw ARM64HookError.trampolineAllocationFailed
        }
        return ARM64TrampolinePage(pointer: pointer, size: pageSize)
    }

    func write(originalEntry: ARM64InstructionBlock, returnAddress: UnsafeRawPointer) throws {
        guard state == .writable else {
            throw ARM64HookError.trampolineAlreadySealed
        }
        let pointer = try livePointer()
        let layout = try ARM64TrampolineLayout(
            originalEntry: originalEntry,
            returnAddress: UInt(bitPattern: returnAddress),
            capacity: Int(size)
        )

        // Build the trampoline:
        // - first: original function entry instructions
        // - then: jump back into the original function after our patch
        _ = layout.bytes.withUnsafeBytes { bytes in
            memcpy(pointer, bytes.baseAddress, bytes.count)
        }
    }

    func sealExecutable() throws {
        guard state == .writable else {
            throw ARM64HookError.trampolineAlreadySealed
        }
        let pointer = try livePointer()
        // Seal the trampoline after writing it. W^X discipline: memory should
        // not remain writable and executable at the same time.
        guard mprotect(pointer, Int(size), PROT_READ | PROT_EXEC) == 0 else {
            let capturedErrno = errno
            throw ARM64HookError.trampolineProtectionFailed(errno: capturedErrno)
        }
        state = .executable
    }

    func typedFunction<T>(as type: T.Type) throws -> T {
        guard state == .executable else {
            throw ARM64HookError.trampolineNotExecutable
        }
        let pointer = try livePointer()
        return unsafeBitCast(pointer, to: type)
    }

    func release() throws {
        guard let pointerStorage else { return }
        let result = munmap(pointerStorage, Int(size))
        guard result == 0 else {
            throw ARM64HookError.trampolineReleaseFailed(errno: errno)
        }
        self.pointerStorage = nil
        state = .released
    }
}

struct ARM64TrampolineLayout: Equatable {
    let bytes: [UInt8]

    init(originalEntry: ARM64InstructionBlock, returnAddress: UInt, capacity: Int) throws {
        let returnJump = ARM64AbsoluteJump(destinationAddress: returnAddress)
        let bytes = originalEntry.bytes + returnJump.bytes
        guard bytes.count <= capacity else {
            throw ARM64HookError.trampolineTooSmall(
                required: bytes.count,
                available: capacity
            )
        }
        self.bytes = bytes
    }
}

struct ARM64AbsoluteJump: Equatable {
    let bytes: [UInt8]

    init(destinationAddress: UInt) {
        // ARM64 instructions are fixed width: every instruction is 4 bytes.
        // Our jump sequence is 16 bytes total:
        //
        //   ldr x16, #8        ; load the 8-byte destination address below
        //   br  x16            ; branch to that address
        //   .quad destination  ; the absolute address to jump to
        var bytes: [UInt8] = []
        Self.appendUInt32(0x58000050, to: &bytes) // ldr x16, #8
        Self.appendUInt32(0xd61f0200, to: &bytes) // br x16
        Self.appendUInt64(UInt64(destinationAddress), to: &bytes)
        self.bytes = bytes
    }

    private static func appendUInt32(_ value: UInt32, to bytes: inout [UInt8]) {
        // ARM64 simulator is little-endian. Emit instruction words in the byte
        // order the CPU expects in memory.
        withUnsafeBytes(of: value.littleEndian) { bytes.append(contentsOf: $0) }
    }

    private static func appendUInt64(_ value: UInt64, to bytes: inout [UInt8]) {
        // Absolute jump target embedded after the two-instruction jump stub.
        withUnsafeBytes(of: value.littleEndian) { bytes.append(contentsOf: $0) }
    }
}

private struct ARM64CodePage {
    let address: vm_address_t
    let size: vm_size_t

    init(containing pointer: UnsafeRawPointer) {
        let pageSize = vm_size_t(getpagesize())
        let pointerAddress = UInt(bitPattern: pointer)
        self.address = vm_address_t(pointerAddress & ~(UInt(pageSize) - 1))
        self.size = pageSize
    }

    func overwrite(_ target: UnsafeMutableRawPointer, with bytes: [UInt8]) throws {
        try validateWrite(target, byteCount: bytes.count)
        // Code pages are normally read+execute, not writable. Temporarily make
        // the target page writable, copy the bytes, flush the instruction cache
        // so the CPU stops seeing stale code bytes, then restore read+execute.
        try withWritableMapping {
            _ = bytes.withUnsafeBytes { rawBytes in
                memcpy(target, rawBytes.baseAddress, rawBytes.count)
            }
            sys_icache_invalidate(UnsafeRawPointer(target), bytes.count)
        }
    }

    private func withWritableMapping(_ body: () throws -> Void) throws {
        try makeWritable()
        var pageIsWritable = true
        defer {
            if pageIsWritable {
                try? makeExecutable()
            }
        }
        try body()
        try makeExecutable()
        pageIsWritable = false
    }

    private func validateWrite(_ target: UnsafeRawPointer, byteCount: Int) throws {
        let targetAddress = UInt(bitPattern: target)
        let pageStart = UInt(address)
        let pageEnd = pageStart + UInt(size)
        guard targetAddress >= pageStart,
              targetAddress <= pageEnd,
              byteCount <= Int(pageEnd - targetAddress)
        else {
            throw ARM64HookError.patchCrossesPageBoundary
        }
    }

    private func makeWritable() throws {
        // VM_PROT_COPY asks Mach for a private writable mapping of the code
        // page. This is what lets us modify code that normally lives in a
        // read+execute mapping.
        let result = vm_protect(
            mach_task_self_,
            address,
            size,
            0,
            VM_PROT_READ | VM_PROT_WRITE | VM_PROT_COPY
        )
        guard result == KERN_SUCCESS else {
            throw ARM64HookError.pageProtectionFailed(result)
        }
    }

    private func makeExecutable() throws {
        // Put the code page back into its normal executable state. We never keep
        // AXRuntime's text page writable after patching/restoring.
        let result = vm_protect(
            mach_task_self_,
            address,
            size,
            0,
            VM_PROT_READ | VM_PROT_EXECUTE
        )
        guard result == KERN_SUCCESS else {
            throw ARM64HookError.pageProtectionFailed(result)
        }
    }
}

#if DEBUG
struct ARM64FunctionEntryPatchTestProbeResult: Equatable {
    let beforePatch: Int32
    let duringPatch: Int32
    let replacementCallCount: Int
    let afterUninstall: Int32
}

enum ARM64FunctionEntryPatchTestProbe {
    static func runFakeCFunctionPatchRoundTrip() throws -> ARM64FunctionEntryPatchTestProbeResult {
        let targetPointer = try testTargetPointer()
        let replacementPointer = unsafeBitCast(
            BHARM64FunctionEntryPatchProbeReplacement as ARM64FunctionEntryPatchProbeFunction,
            to: UnsafeMutableRawPointer.self
        )
        let patchedFunction = unsafeBitCast(
            targetPointer,
            to: ARM64FunctionEntryPatchProbeFunction.self
        )

        let beforePatch = patchedFunction(5)
        let patch = try ARM64FunctionEntryPatch.install(
            target: targetPointer,
            replacement: replacementPointer
        )
        var patchIsInstalled = true
        defer {
            ARM64FunctionEntryPatchProbeState.shared.installOriginal(nil)
            if patchIsInstalled {
                try? patch.uninstall()
            }
        }

        ARM64FunctionEntryPatchProbeState.shared.installOriginal(
            try patch.typedOriginalImplementation(as: ARM64FunctionEntryPatchProbeFunction.self)
        )
        let duringPatch = patchedFunction(5)
        let replacementCallCount = ARM64FunctionEntryPatchProbeState.shared.replacementCallCount

        try patch.uninstall()
        patchIsInstalled = false
        ARM64FunctionEntryPatchProbeState.shared.installOriginal(nil)
        let afterUninstall = patchedFunction(5)

        return ARM64FunctionEntryPatchTestProbeResult(
            beforePatch: beforePatch,
            duringPatch: duringPatch,
            replacementCallCount: replacementCallCount,
            afterUninstall: afterUninstall
        )
    }

    private static func testTargetPointer() throws -> UnsafeMutableRawPointer {
        guard let handle = dlopen(nil, RTLD_NOW),
              let pointer = dlsym(handle, "BHTestCAbiPatchTarget")
        else {
            throw ARM64HookError.testProbeTargetUnavailable
        }
        return pointer
    }
}

private typealias ARM64FunctionEntryPatchProbeFunction = @convention(c) (Int32) -> Int32

// Rationale: DEBUG probe storage is guarded by `lock`; pointer reads happen after recording.
// swiftlint:disable:next agent_unchecked_sendable_no_comment
private final class ARM64FunctionEntryPatchProbeState: @unchecked Sendable {
    static let shared = ARM64FunctionEntryPatchProbeState()

    private let lock = NSLock()
    private var originalStorage: ARM64FunctionEntryPatchProbeFunction?
    private var replacementCallCountStorage = 0

    var replacementCallCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return replacementCallCountStorage
    }

    func installOriginal(_ original: ARM64FunctionEntryPatchProbeFunction?) {
        lock.lock()
        defer { lock.unlock() }
        originalStorage = original
        replacementCallCountStorage = 0
    }

    func callOriginal(_ value: Int32) -> Int32 {
        let original = recordReplacementCall()
        return original?(value) ?? -10_000
    }

    private func recordReplacementCall() -> ARM64FunctionEntryPatchProbeFunction? {
        lock.lock()
        defer { lock.unlock() }
        replacementCallCountStorage += 1
        return originalStorage
    }
}

@_cdecl("BHARM64FunctionEntryPatchProbeReplacement")
private func BHARM64FunctionEntryPatchProbeReplacement(_ value: Int32) -> Int32 {
    ARM64FunctionEntryPatchProbeState.shared.callOriginal(value) * 3
}
#endif

@_cdecl("BHAccessibilityPostNotificationHook")
private func BHAccessibilityPostNotificationHook(
    _ code: UInt32,
    _ associatedElement: UnsafeRawPointer?,
    _ notificationData: UnsafeRawPointer?
) -> Int32 {
    AccessibilityPostNotificationHookState.shared.recordAndForward(
        code: code,
        associatedElement: associatedElement,
        notificationData: notificationData
    )
}

#endif // DEBUG
#endif // canImport(UIKit)
