import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import XCTest

// Macro implementations build for the host, so the corresponding module is not available when cross-compiling. Cross-compiled tests may still make use of the macro itself in end-to-end tests.
#if canImport(AtomicPropertyMacros)
import AtomicPropertyMacros

let testMacros: [String: Macro.Type] = [
    "Atomic": AtomicProperty.self,
]
#endif

final class AtomicPropertyTests: XCTestCase {
    func testMacro_1() throws {
        #if canImport(AtomicPropertyMacros)
        assertMacroExpansion(
            """
            @Atomic private(set) var number: Int
            """,
            expandedSource: """
            private(set) var number: Int {
                @storageRestrictions(initializes: _number)
                init(initialValue) {
                    _number = os.OSAllocatedUnfairLock<Int>(initialState: initialValue)
                }
                get {
                    return _number.withLock(flags: os.OSAllocatedUnfairLockFlags.adaptiveSpin) { value in
                        return value
                    }
                }
                set {
                    _number.withLock(flags: os.OSAllocatedUnfairLockFlags.adaptiveSpin) { value in
                        value = newValue
                    }
                }
            }
            
            private nonisolated(unsafe) var _number: os.OSAllocatedUnfairLock<Int>
            """,
            macros: testMacros
        )
        #else
        throw XCTSkip("macros are only supported when running tests for the host platform")
        #endif
    }
    
    func testMacro_2() throws {
        #if canImport(AtomicPropertyMacros)
        assertMacroExpansion(
            """
            @Atomic private(set) var number: Int = 100
            """,
            expandedSource: """
            private(set) var number: Int {
                get {
                    return _number.withLock(flags: os.OSAllocatedUnfairLockFlags.adaptiveSpin) { value in
                        return value
                    }
                }
                set {
                    _number.withLock(flags: os.OSAllocatedUnfairLockFlags.adaptiveSpin) { value in
                        value = newValue
                    }
                }
            }
            
            private nonisolated(unsafe) var _number: os.OSAllocatedUnfairLock<Int> = os.OSAllocatedUnfairLock<Int>(initialState: 100)
            """,
            macros: testMacros
        )
        #else
        throw XCTSkip("macros are only supported when running tests for the host platform")
        #endif
    }
    
    func testMacro_3() throws {
        #if canImport(AtomicPropertyMacros)
        assertMacroExpansion(
            """
            @Atomic(isNSCopying: true, unchecked: true) var attributedString: NSAttributedString = NSAttributedString()
            """,
            expandedSource: """
            var attributedString: NSAttributedString {
                get {
                    return _attributedString.withLockUnchecked(flags: os.OSAllocatedUnfairLockFlags.adaptiveSpin) { value in
                        return value
                    }
                }
                set {
                    let copied = newValue.copy() as! NSAttributedString
                    _attributedString.withLockUnchecked(flags: os.OSAllocatedUnfairLockFlags.adaptiveSpin) { value in
                        value = copied
                    }
                }
            }
            
            private nonisolated(unsafe) var _attributedString: os.OSAllocatedUnfairLock<NSAttributedString> = os.OSAllocatedUnfairLock<NSAttributedString>(uncheckedState: (NSAttributedString().copy() as! NSAttributedString))
            """,
            macros: testMacros
        )
        #else
        throw XCTSkip("macros are only supported when running tests for the host platform")
        #endif
    }
}
