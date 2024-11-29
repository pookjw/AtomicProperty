import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftDiagnostics

struct SimpleDiagnosticMessage: DiagnosticMessage {
    let message: String
    let diagnosticID: SwiftDiagnostics.MessageID
    let severity: SwiftDiagnostics.DiagnosticSeverity
}

extension SimpleDiagnosticMessage: FixItMessage {
    var fixItID: SwiftDiagnostics.MessageID { diagnosticID }
}

public struct AtomicProperty: AccessorMacro, PeerMacro {
    public static func expansion(of node: SwiftSyntax.AttributeSyntax, providingAccessorsOf declaration: some SwiftSyntax.DeclSyntaxProtocol, in context: some SwiftSyntaxMacros.MacroExpansionContext) throws -> [SwiftSyntax.AccessorDeclSyntax] {
        
        let (isNSCopying, unchecked) = arguments(of: node)
        
        guard let property = check(of: node, providingPeersOf: declaration, in: context),
              let name = name(of: property),
              let typeText = typeText(of: property)
        else {
            return []
        }
        
        
        let initAccessor: AccessorDeclSyntax
        if unchecked {
            if isNSCopying {
                initAccessor = """
                @storageRestrictions(initializes: _\(raw: name))
                init(initialValue) {
                let copied = initialValue.copy() as! \(raw: typeText)
                _\(raw: name) = os.OSAllocatedUnfairLock<\(raw: typeText)>(uncheckedState: copied)
                }
                """
            } else {
                initAccessor = """
                @storageRestrictions(initializes: _\(raw: name))
                init(initialValue) {
                _\(raw: name) = os.OSAllocatedUnfairLock<\(raw: typeText)>(uncheckedState: initialValue)
                }
                """
            }
        } else {
            if isNSCopying {
                initAccessor = """
                @storageRestrictions(initializes: _\(raw: name))
                init(initialValue) {
                let copied = initialValue.copy() as! \(raw: typeText)
                _\(raw: name) = os.OSAllocatedUnfairLock<\(raw: typeText)>(initialState: copied)
                }
                """
            } else {
                initAccessor = """
                @storageRestrictions(initializes: _\(raw: name))
                init(initialValue) {
                _\(raw: name) = os.OSAllocatedUnfairLock<\(raw: typeText)>(initialState: initialValue)
                }
                """
            }
        }
        
        let getAccessor: AccessorDeclSyntax
        if unchecked {
            getAccessor = """
            get {
            return _\(raw: name).withLockUnchecked(flags: os.OSAllocatedUnfairLockFlags.adaptiveSpin) { value in
            return value
            }
            }
            """
        } else {
            getAccessor = """
            get {
            return _\(raw: name).withLock(flags: os.OSAllocatedUnfairLockFlags.adaptiveSpin) { value in
            return value
            }
            }
            """
        }
        
        let setAccessor: AccessorDeclSyntax
        if unchecked {
            if isNSCopying {
                setAccessor = """
                set {
                let copied = newValue.copy() as! \(raw: typeText)
                _\(raw: name).withLockUnchecked(flags: os.OSAllocatedUnfairLockFlags.adaptiveSpin) { value in
                value = copied
                }
                }
                """
            } else {
                setAccessor = """
                set {
                _\(raw: name).withLockUnchecked(flags: os.OSAllocatedUnfairLockFlags.adaptiveSpin) { value in
                value = newValue
                }
                }
                """
            }
        } else {
            if isNSCopying {
                setAccessor = """
                set {
                let copied = newValue.copy() as! \(raw: typeText)
                _\(raw: name).withLock(flags: os.OSAllocatedUnfairLockFlags.adaptiveSpin) { value in
                value = copied
                }
                }
                """
            } else {
                setAccessor = """
                set {
                _\(raw: name).withLock(flags: os.OSAllocatedUnfairLockFlags.adaptiveSpin) { value in
                value = newValue
                }
                }
                """
            }
        }
        
        if hasInitializer(of: property) {
            return [getAccessor, setAccessor]
        } else {
            return [initAccessor, getAccessor, setAccessor]
        }
    }
    
    public static func expansion(of node: SwiftSyntax.AttributeSyntax, providingPeersOf declaration: some SwiftSyntax.DeclSyntaxProtocol, in context: some SwiftSyntaxMacros.MacroExpansionContext) throws -> [SwiftSyntax.DeclSyntax] {
        guard let property = check(of: node, providingPeersOf: declaration, in: context),
              let name = name(of: property),
              let typeText = typeText(of: property)
        else {
            return []
        }
        
        let (isNSCopying, unchecked) = arguments(of: node)
        
        let decl: DeclSyntax
        if let initialValue = initialValue(of: property) {
            if unchecked {
                if isNSCopying {
                    decl = "private nonisolated(unsafe) var _\(raw: name): os.OSAllocatedUnfairLock<\(raw: typeText)> = os.OSAllocatedUnfairLock<\(raw: typeText)>(uncheckedState: (\(raw: initialValue).copy() as! \(raw: typeText)))"
                    
                } else {
                    decl = "private nonisolated(unsafe) var _\(raw: name): os.OSAllocatedUnfairLock<\(raw: typeText)> = os.OSAllocatedUnfairLock<\(raw: typeText)>(uncheckedState: \(raw: initialValue))"
                }
            } else {
                if isNSCopying {
                    decl = "private nonisolated(unsafe) var _\(raw: name): os.OSAllocatedUnfairLock<\(raw: typeText)> = os.OSAllocatedUnfairLock<\(raw: typeText)>(initialState: (\(raw: initialValue).copy() as! \(raw: typeText)))"
                } else {
                    decl = "private nonisolated(unsafe) var _\(raw: name): os.OSAllocatedUnfairLock<\(raw: typeText)> = os.OSAllocatedUnfairLock<\(raw: typeText)>(initialState: \(raw: initialValue))"
                }
            }
        } else {
            decl = "private nonisolated(unsafe) var _\(raw: name): os.OSAllocatedUnfairLock<\(raw: typeText)>"
        }
        
        return [decl]
    }
    
    private static func check(
        of node: SwiftSyntax.AttributeSyntax,
        providingPeersOf declaration: some SwiftSyntax.DeclSyntaxProtocol,
        in context: some SwiftSyntaxMacros.MacroExpansionContext
    ) -> VariableDeclSyntax? {
        guard let property = declaration.as(VariableDeclSyntax.self) else {
            let diagnostic = Diagnostic(
                node: node,
                position: declaration.position,
                message: SimpleDiagnosticMessage(
                    message: "no",
                    diagnosticID: MessageID(domain: "AtomicProperty", id: "AtomicProperty"),
                    severity: .error
                )
            )
                
            context.diagnose(diagnostic)
            return nil
        }
        
        guard property.bindingSpecifier.tokenKind == .keyword(.var) else {
            let diagnostic = Diagnostic(
                node: Syntax(property.bindingSpecifier),
                position: property.position,
                message: SimpleDiagnosticMessage(
                    message: "no",
                    diagnosticID: MessageID(domain: "AtomicProperty", id: "AtomicProperty"),
                    severity: .error
                ),
                fixIt: .replace(
                    message: SimpleDiagnosticMessage(
                        message: "replace with var",
                        diagnosticID: MessageID(domain: "AtomicProperty", id: "AtomicProperty"),
                        severity: .error
                    ),
                    oldNode: Syntax(property.bindingSpecifier),
                    newNode: Syntax(TokenSyntax.keyword(.var))
                )
            )
                
            context.diagnose(diagnostic)
            return nil
        }
        
        for binding in property.bindings {
            if binding.accessorBlock != nil {
                fatalError()
            }
        }
        
        return property
    }
    
    private static func name(of decl: VariableDeclSyntax) -> String? {
        var name: String?
        for binding in decl.bindings {
            guard let syntax = binding.pattern.as(IdentifierPatternSyntax.self) else {
                continue
            }
            
            name = syntax.identifier.text
            break
        }
        
        if name == nil {
            fatalError()
        }
        
        return name
    }
    
    private static func typeText(of decl: VariableDeclSyntax) -> String? {
        var type: String?
        for binding in decl.bindings {
            guard let text = binding.typeAnnotation?.type.as(IdentifierTypeSyntax.self)?.name.text else {
                continue
            }
            
            type = text
            break
        }
        
        if type == nil {
            fatalError()
        }
        
        return type
    }
    
    private static func hasInitializer(of decl: VariableDeclSyntax) -> Bool {
        for binding in decl.bindings {
            if binding.initializer != nil {
                return true
            }
        }
        return false
    }
    
    // TODO: Unstable
    private static func initialValue(of decl: VariableDeclSyntax) -> String? {
        var initialValue: String?
        for binding in decl.bindings {
            guard let initializer = binding.initializer,
                  initializer.equal.tokenKind == .equal
            else {
                continue
            }
            
            for child in Syntax(initializer.value).children(viewMode: .all) {
                if let tokenSyntax = child.as(TokenSyntax.self) {
                    if initialValue == nil {
                        initialValue = ""
                    }
                    
                    initialValue?.append(tokenSyntax.text)
                } else if let exprSyntax = child.as(DeclReferenceExprSyntax.self) {
                    if initialValue == nil {
                        initialValue = ""
                    }
                    
                    initialValue?.append(exprSyntax.baseName.text)
                }
            }
            
            break
        }
        
        return initialValue
    }
    
    private static func arguments(of node: SwiftSyntax.AttributeSyntax) -> (isNSCopying: Bool, unchecked: Bool) {
        var isNSCopying = false
        var unchecked = false
        
        if let arguments = node.arguments {
            for argument in arguments.children(viewMode: .all) {
                guard let label = argument.as(LabeledExprSyntax.self),
                      let name = label.label?.identifier?.name,
                      let boolExpr = label.expression.as(BooleanLiteralExprSyntax.self),
                      boolExpr.literal.tokenKind == .keyword(.true)
                else {
                    continue
                }
                
                if name == "isNSCopying" {
                    isNSCopying = true
                } else if name == "unchecked" {
                    unchecked = true
                }
            }
        }
        
        return (isNSCopying, unchecked)
    }
}

@main
struct AtomicPropertyPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        AtomicProperty.self,
    ]
}
