import AtomicProperty

actor FooActor {
    @Atomic nonisolated var foo: Int = 0
    
    @Atomic(isNSCopying: true, unchecked: true) nonisolated var attributedString_2: NSAttributedString
    
    init() {
        attributedString_2 = .init()
    }
}

final class FooClass: @unchecked Sendable {
    @Atomic nonisolated var foo: Int = 0
    
    @Atomic(isNSCopying: true, unchecked: true) nonisolated var attributedString_2: NSAttributedString
    
    init() {
        attributedString_2 = .init()
    }
}
