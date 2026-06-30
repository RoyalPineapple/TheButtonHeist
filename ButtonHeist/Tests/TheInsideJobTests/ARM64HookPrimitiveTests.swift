#if canImport(UIKit) && arch(arm64)
@testable import TheInsideJob
import XCTest

final class ARM64HookPrimitiveTests: XCTestCase {
    func testAbsoluteJumpEncodesFixedARM64StubAndLittleEndianDestination() {
        let jump = ARM64AbsoluteJump(destinationAddress: 0x1122334455667788)

        XCTAssertEqual(jump.bytes, [
            // ldr x16, #8: load the embedded absolute address below.
            0x50, 0x00, 0x00, 0x58,
            // br x16: branch to the loaded address.
            0x00, 0x02, 0x1f, 0xd6,
            // 0x1122334455667788 encoded little-endian for arm64 simulator.
            0x88, 0x77, 0x66, 0x55,
            0x44, 0x33, 0x22, 0x11,
        ])
    }

    func testInstructionBlockRejectsPartialARM64InstructionBytes() throws {
        do {
            _ = try ARM64InstructionBlock(bytes: [0x00, 0x01, 0x02])
            XCTFail("Expected partial instruction bytes to fail validation")
        } catch let error as ARM64HookError {
            XCTAssertEqual(error, .invalidInstructionBlockByteCount(3))
        } catch {
            XCTFail("Expected ARM64HookError, got \(error)")
        }
    }

    func testInstructionBlockAcceptsRelocatableNonPCRelativeInstructions() throws {
        let block = try ARM64InstructionBlock(bytes: ARM64HookPrimitiveTestBytes.relocatableEntry)

        try block.validateCanRunFromTrampoline()
    }

    func testInstructionBlockRejectsEntryThatAlreadyStartsWithOurPatch() throws {
        let block = try ARM64InstructionBlock(bytes: ARM64AbsoluteJump(destinationAddress: 0x1000).bytes)

        do {
            try block.validateCanRunFromTrampoline()
            XCTFail("Expected already-patched entry to fail validation")
        } catch let error as ARM64HookError {
            XCTAssertEqual(error, .targetAlreadyPatched)
        } catch {
            XCTFail("Expected ARM64HookError, got \(error)")
        }
    }

    func testInstructionBlockRejectsPCRelativeEntryInstructions() throws {
        let block = try ARM64InstructionBlock(bytes: ARM64HookPrimitiveTestBytes.entryWithADRP)

        do {
            try block.validateCanRunFromTrampoline()
            XCTFail("Expected PC-relative instruction to fail validation")
        } catch let error as ARM64HookError {
            XCTAssertEqual(error, .nonRelocatableInstruction(index: 1, instruction: 0x90000000))
        } catch {
            XCTFail("Expected ARM64HookError, got \(error)")
        }
    }

    func testTrampolineLayoutAppendsJumpBackAfterOriginalEntryBytes() throws {
        let originalEntry = try ARM64InstructionBlock(bytes: ARM64HookPrimitiveTestBytes.relocatableEntry)

        let layout = try ARM64TrampolineLayout(
            originalEntry: originalEntry,
            returnAddress: 0x8877665544332211,
            capacity: 32
        )

        XCTAssertEqual(
            layout.bytes,
            originalEntry.bytes + ARM64AbsoluteJump(destinationAddress: 0x8877665544332211).bytes
        )
    }

    func testTrampolineLayoutRejectsInsufficientCapacityBeforeWritingMemory() throws {
        let originalEntry = try ARM64InstructionBlock(bytes: ARM64HookPrimitiveTestBytes.relocatableEntry)

        do {
            _ = try ARM64TrampolineLayout(
                originalEntry: originalEntry,
                returnAddress: 0x1000,
                capacity: 31
            )
            XCTFail("Expected trampoline capacity validation to fail")
        } catch let error as ARM64HookError {
            XCTAssertEqual(error, .trampolineTooSmall(required: 32, available: 31))
        } catch {
            XCTFail("Expected ARM64HookError, got \(error)")
        }
    }

    func testFunctionEntryPatchCanHookATestCAbiFunctionAndRestoreIt() throws {
        let result = try ARM64FunctionEntryPatchTestProbe.runFakeCFunctionPatchRoundTrip()

        XCTAssertEqual(
            result,
            ARM64FunctionEntryPatchTestProbeResult(
                beforePatch: 12,
                duringPatch: 36,
                replacementCallCount: 1,
                afterUninstall: 12
            )
        )
    }
}

private enum ARM64HookPrimitiveTestBytes {
    // ARM64 "nop" means "no operation". The CPU does not read or write memory,
    // touch registers, or branch; it simply advances to the next instruction.
    // That makes it a good stand-in for an entry instruction that remains valid
    // after we copy it into a trampoline.
    private static let nop: [UInt8] = [
        0x1f, 0x20, 0x03, 0xd5,
    ]

    // ARM64 "adrp x0, #0" forms a page address relative to the current program
    // counter. If we copied it from the real function entry into a trampoline,
    // it would resolve relative to the trampoline's address instead of the
    // original function's address. The hook rejects this instruction family
    // instead of trying to rewrite it.
    private static let adrp: [UInt8] = [
        0x00, 0x00, 0x00, 0x90,
    ]

    // Four instructions because the production hook overwrites exactly 16
    // bytes at the target entry.
    static let relocatableEntry = nop + nop + nop + nop

    static let entryWithADRP = nop + adrp + nop + nop
}
#endif
