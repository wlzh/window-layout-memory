import AppKit
import ApplicationServices
import CryptoKit

// One-shot diagnostic only: no setters, observers, timers, window activation or layout writes.
func digest(_ text: String) -> String {
    SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
}

final class Probe {
    let deadline = ProcessInfo.processInfo.systemUptime + 5
    var reads = 0
    var failures = 0
    var truncated = false
    func value(_ element: AXUIElement, _ attribute: String) -> Any? {
        guard reads < 600, ProcessInfo.processInfo.systemUptime < deadline else {
            truncated = true; return nil
        }
        reads += 1
        AXUIElementSetMessagingTimeout(element, 0.08)
        var result: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &result)
        guard error == .success else { failures += 1; return nil }
        return result
    }
    func structure(_ element: AXUIElement, depth: Int, remaining: inout Int) -> [String: Any] {
        guard remaining > 0, ProcessInfo.processInfo.systemUptime < deadline else {
            truncated = true; return ["truncated": true]
        }
        remaining -= 1
        var row: [String: Any] = [:]
        for key in ["AXRole", "AXSubrole"] {
            if let text = value(element, key) as? String { row[key] = text }
        }
        // Identifier values may contain user data; retain only hashes for comparisons.
        if let identifier = value(element, "AXIdentifier") as? String, !identifier.isEmpty {
            row["identifierSHA256"] = digest(identifier)
        }
        if depth > 0, let children = value(element, "AXChildren") as? [AXUIElement] {
            row["childCount"] = children.count
            if children.count > 16 { truncated = true }
            row["children"] = children.prefix(16).map { structure($0, depth: depth - 1, remaining: &remaining) }
        }
        return row
    }
    func report(bundle: String) -> [String: Any] {
        var result: [String: Any] = ["bundle": bundle, "trusted": AXIsProcessTrusted(),
                                   "privacy": "no titles, values, descriptions, document URLs or screenshots"]
        guard AXIsProcessTrusted() else { result["error"] = "accessibilityPermissionRequired"; return result }
        let apps = NSWorkspace.shared.runningApplications.filter { $0.bundleIdentifier == bundle }
        result["processes"] = apps.map { app -> [String: Any] in
            let root = AXUIElementCreateApplication(app.processIdentifier)
            guard let windows = value(root, "AXWindows") as? [AXUIElement] else {
                return ["pid": app.processIdentifier, "error": "windowsUnavailable"]
            }
            if windows.count > 12 { truncated = true }
            let rows = windows.prefix(12).enumerated().map { index, window -> [String: Any] in
                var budget = 64
                let tree = structure(window, depth: 3, remaining: &budget)
                var row: [String: Any] = ["index": index, "structure": tree]
                for key in ["AXMain", "AXFocused", "AXModal", "AXMinimized"] {
                    if let flag = value(window, key) as? Bool { row[key] = flag }
                }
                if let raw = value(window, "AXParent") as CFTypeRef?, CFGetTypeID(raw) == AXUIElementGetTypeID() {
                    let parent = raw as! AXUIElement
                    row["parentRole"] = value(parent, "AXRole") as? String ?? "unavailable"
                }
                return row
            }
            return ["pid": app.processIdentifier, "windowCount": windows.count, "windows": rows]
        }
        result["reads"] = reads; result["unavailableAttributes"] = failures
        result["truncated"] = truncated
        result["warning"] = "Observed structure is not proof of a persistent window identity. Indices and PIDs are session-only."
        return result
    }
}

let arguments = Array(CommandLine.arguments.dropFirst())
if arguments == ["--request-permission"] {
    let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
    print("trusted=\(AXIsProcessTrustedWithOptions(options))")
} else if arguments == ["--self-test"] {
    precondition(digest("a") == digest("a"))
    precondition(digest("a") != digest("b"))
    precondition(digest("").count == 64)
    print("PROBE_SELF_TEST passed=3; hashing only, live AX not tested")
} else if arguments.count == 1, arguments[0].contains("."), !arguments[0].hasPrefix("-") {
    let report = Probe().report(bundle: arguments[0])
    let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
    print(String(decoding: data, as: UTF8.self))
    if !AXIsProcessTrusted() { exit(2) }
} else {
    fputs("Usage: window-identity-probe BUNDLE_ID | --self-test | --request-permission\n", stderr)
    exit(64)
}
