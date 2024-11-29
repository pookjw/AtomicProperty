@_exported import os
@_exported import Foundation

@attached(accessor, names: named(init), named(get), named(set))
@attached(peer, names: prefixed(_))
public macro Atomic(isNSCopying: Bool = false, unchecked: Bool = false) = #externalMacro(module: "AtomicPropertyMacros", type: "AtomicProperty")
