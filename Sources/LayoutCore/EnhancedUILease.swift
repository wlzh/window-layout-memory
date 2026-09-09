import Foundation

/// A transaction-local compatibility lease. Never persists or changes system settings.
public final class EnhancedUILease {
    private var restore: (() -> Bool)?
    public init(assistiveTechnologyActive: Bool,read: @escaping () -> Bool?,write: @escaping (Bool) -> Bool) {
        guard !assistiveTechnologyActive,read() == true else { return }
        let changed=write(false)
        if changed || read() == false { restore={let written=write(true);return read() ?? written} }
    }
    @discardableResult public func finish() -> Bool {
        let action=restore;restore=nil;return action?() ?? true
    }
    deinit { _=finish() }
}
