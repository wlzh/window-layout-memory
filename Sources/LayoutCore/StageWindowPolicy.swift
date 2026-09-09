import Foundation

public struct StageWindowTraits: Equatable {
    public var role: String, subrole: String, parentRole: String
    public var modal: Bool
    public init(role: String = "AXWindow", subrole: String = "AXStandardWindow", parentRole: String = "AXApplication", modal: Bool = false) {
        self.role=role;self.subrole=subrole;self.parentRole=parentRole;self.modal=modal
    }
    public var isStandard: Bool { role == "AXWindow" && subrole == "AXStandardWindow" }
    public var isChild: Bool { parentRole == "AXWindow" || parentRole == "AXSheet" }
    public func permits(includeChildren: Bool) -> Bool {
        !modal && isStandard && (parentRole == "AXApplication" || (includeChildren && isChild))
    }
}

/// Exact AX identifiers only: never infer a persistent rule from titles or dimensions.
public struct StageWindowRule: Codable, Equatable, Hashable {
    public var bundle: String, identifier: String, role: String, subrole: String
    public init(bundle: String, identifier: String, role: String, subrole: String) {
        self.bundle=bundle;self.identifier=identifier;self.role=role;self.subrole=subrole
    }
    public var valid: Bool {
        [bundle,identifier,role,subrole].allSatisfy { !$0.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty && $0.utf8.count <= 1024 }
    }
    public func matches(_ identity: WindowIdentity, traits: StageWindowTraits) -> Bool {
        valid && bundle == identity.bundle && identifier == identity.identifier && role == traits.role && subrole == traits.subrole
    }
}
