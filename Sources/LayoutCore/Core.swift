import Foundation

public struct Rect: Codable, Equatable {
    public var x: Double, y: Double, width: Double, height: Double
    public init(_ x: Double, _ y: Double, _ width: Double, _ height: Double) {
        self.x = x; self.y = y; self.width = width; self.height = height
    }
    public var valid: Bool { [x,y,width,height].allSatisfy { $0.isFinite && abs($0) < 1_000_000 } && width > 0 && height > 0 }
    public func close(to b: Rect, tolerance: Double = 4) -> Bool {
        valid && b.valid && zip([x,y,width,height], [b.x,b.y,b.width,b.height]).allSatisfy { abs($0-$1) <= tolerance }
    }
    public func intersection(_ b: Rect) -> Double {
        max(0, min(x+width,b.x+b.width)-max(x,b.x)) * max(0,min(y+height,b.y+b.height)-max(y,b.y))
    }
    public func normalized(in b: Rect) -> Rect {
        Rect((x-b.x)/b.width, (y-b.y)/b.height, width/b.width, height/b.height)
    }
    public func expanded(in b: Rect) -> Rect { Rect(b.x+x*b.width,b.y+y*b.height,width*b.width,height*b.height) }
    public func reachable(in b: Rect) -> Rect {
        // Preserve a usable title bar without forcing large windows to fit.
        Rect(min(max(x,b.x-width+min(width,80)),b.x+b.width-min(width,80)),
             min(max(y,b.y),b.y+b.height-min(height,32)),width,height)
    }
}

public struct Display: Codable, Equatable {
    public var id: String, name: String
    public var frame: Rect, visible: Rect
    public var scale: Double, rotation: Double
    public var primary: Bool, mirrored: Bool
    public init(id: String, name: String, frame: Rect, visible: Rect? = nil, scale: Double = 1,
                rotation: Double = 0, primary: Bool = false, mirrored: Bool = false) {
        self.id=id; self.name=name; self.frame=frame; self.visible=visible ?? frame
        self.scale=scale; self.rotation=rotation; self.primary=primary; self.mirrored=mirrored
    }
}
public struct Topology: Codable, Equatable {
    public var displays: [Display]
    public init(_ displays: [Display]) { self.displays = displays.sorted { $0.id < $1.id } }
    public var valid: Bool {
        !displays.isEmpty && displays.count <= 16 && Set(displays.map(\.id)).count == displays.count &&
        displays.filter(\.primary).count == 1 && displays.allSatisfy {
            !$0.id.isEmpty && $0.frame.valid && $0.visible.valid && !$0.mirrored && $0.scale.isFinite && $0.scale > 0 && $0.rotation.isFinite
        }
    }
    public var key: String {
        // Canonical JSON avoids collisions from identifiers containing delimiters.
        let rows: [[String]] = displays.sorted { $0.id < $1.id }.map {
            [$0.id, String($0.frame.x),String($0.frame.y),String($0.frame.width),String($0.frame.height),
             String($0.scale),String($0.rotation),String($0.primary),String($0.mirrored)]
        }
        return String(data: try! JSONEncoder().encode(rows), encoding: .utf8)!
    }
    public func owner(of frame: Rect) -> Display? {
        let ranked = displays.map { ($0, frame.intersection($0.frame)) }.sorted { $0.1 > $1.1 }
        guard let first = ranked.first, first.1 > 0,
              ranked.count == 1 || first.1 != ranked[1].1 else { return nil }
        return first.0
    }
}

public struct WindowIdentity: Codable, Equatable {
    public var bundle: String, title: String, document: String, identifier: String
    public init(bundle: String, title: String = "", document: String = "", identifier: String = "") {
        self.bundle=bundle; self.title=title; self.document=document; self.identifier=identifier
    }
}
public struct SavedWindow: Codable, Equatable, Identifiable {
    public var id: UUID
    public var identity: WindowIdentity
    public var displayID: String
    public var frame: Rect, sourceVisible: Rect
    public init(id: UUID = UUID(), identity: WindowIdentity, displayID: String, frame: Rect, sourceVisible: Rect) {
        self.id=id; self.identity=identity; self.displayID=displayID; self.frame=frame; self.sourceVisible=sourceVisible
    }
    public func target(in topology: Topology) -> Rect? {
        guard topology.valid, frame.valid, sourceVisible.valid,
              let d = topology.displays.first(where: { $0.id == displayID }) else { return nil }
        return (sourceVisible == d.visible ? frame : frame.normalized(in: sourceVisible).expanded(in: d.visible)).reachable(in: d.visible)
    }
}
public struct Profile: Codable, Equatable, Identifiable {
    public var id: UUID, name: String, topology: Topology, windows: [SavedWindow]
    public var revision: Int, locked: Bool, updatedAt: Date
    public init(name: String, topology: Topology, windows: [SavedWindow] = []) {
        id=UUID(); self.name=name; self.topology=topology; self.windows=windows
        revision=1; locked=false; updatedAt=Date()
    }
}
public struct Preferences: Codable, Equatable {
    public var autoObserve = true, autoRestore = false
    public var excludedBundles: [String] = []
    public init() {}
}
public struct Database: Codable, Equatable {
    public var schemaVersion = 1
    public var profiles: [Profile] = []
    public var history: [Profile] = []
    public var preferences = Preferences()
    public init() {}
    public func validate() throws {
        guard schemaVersion == 1 else { throw CoreError.invalid("Unsupported schema") }
        guard profiles.count <= 100, history.count <= 200,
              Set(profiles.map(\.id)).count == profiles.count,
              Set(profiles.map { $0.topology.key }).count == profiles.count else { throw CoreError.invalid("Duplicate or excessive profiles") }
        for p in profiles + history {
            guard p.topology.valid, p.revision > 0, p.windows.count <= 500,
                  Set(p.windows.map(\.id)).count == p.windows.count,
                  p.windows.allSatisfy({ !$0.identity.bundle.isEmpty && $0.frame.valid && $0.sourceVisible.valid }) else {
                throw CoreError.invalid("Invalid profile geometry or identity")
            }
            for w in p.windows where !p.topology.displays.contains(where: { $0.id == w.displayID }) {
                throw CoreError.invalid("Unknown display")
            }
        }
    }
    public mutating func replace(_ profile: Profile, expectedRevision: Int?) throws {
        var next = self
        try next.replaceUnchecked(profile, expectedRevision: expectedRevision)
        self = next
    }
    private mutating func replaceUnchecked(_ profile: Profile, expectedRevision: Int?) throws {
        if let i = profiles.firstIndex(where: { $0.id == profile.id }) {
            guard profiles[i].revision == expectedRevision, profile.revision > profiles[i].revision else { throw CoreError.invalid("Stale revision") }
            history.append(profiles[i]); profiles[i] = profile
        } else {
            guard expectedRevision == nil else { throw CoreError.invalid("Missing profile") }
            profiles.append(profile)
        }
        var counts: [UUID:Int] = [:]
        history = history.reversed().filter { p in
            counts[p.id,default:0] += 1; return counts[p.id,default:0] <= 20
        }.prefix(200).reversed()
        try validate()
    }
}
public enum CoreError: Error, CustomStringConvertible {
    case invalid(String)
    public var description: String { switch self { case .invalid(let message): return message } }
}

public struct LiveWindow {
    public var token: String, identity: WindowIdentity, frame: Rect, eligible: Bool
    public init(token: String, identity: WindowIdentity, frame: Rect, eligible: Bool = true) {
        self.token=token; self.identity=identity; self.frame=frame; self.eligible=eligible
    }
}
public struct MatchResult {
    public var resolved: [UUID:String] = [:], ambiguous: Set<UUID> = [], missing: Set<UUID> = []
}
public enum Matcher {
    public static func assign(_ saved: [SavedWindow], _ live: [LiveWindow], bindings: [UUID:String] = [:]) -> MatchResult {
        var proposals: [UUID:[String]] = [:]
        for s in saved {
            let same = live.filter { $0.identity.bundle == s.identity.bundle }
            if let binding=bindings[s.id], same.contains(where: { $0.token == binding }) {
                proposals[s.id] = [binding]; continue
            }
            let strong = same.filter {
                (!s.identity.document.isEmpty && $0.identity.document == s.identity.document) ||
                (!s.identity.identifier.isEmpty && $0.identity.identifier == s.identity.identifier)
            }
            let title = same.filter { !s.identity.title.isEmpty && $0.identity.title == s.identity.title }
            // No singleton/titleless fallback: another same-app window may appear later.
            proposals[s.id] = (!strong.isEmpty ? strong : title).map(\.token)
        }
        var claims: [String:Int] = [:]
        for tokens in proposals.values { for token in tokens { claims[token,default:0] += 1 } }
        var result = MatchResult()
        for s in saved {
            let tokens = proposals[s.id] ?? []
            if tokens.isEmpty { result.missing.insert(s.id) }
            else if tokens.count == 1, claims[tokens[0]] == 1 { result.resolved[s.id] = tokens[0] }
            else { result.ambiguous.insert(s.id) }
        }
        return result
    }
}

public struct GuardState {
    public private(set) var generation: UInt64 = 0
    public var paused = false, trusted = false, sleeping = false, settling = true
    public var topologyKey = ""
    public init() {}
    public mutating func invalidate() { generation &+= 1; settling = true }
    public func permits(_ generation: UInt64, key: String) -> Bool {
        trusted && !paused && !sleeping && !settling && self.generation == generation && topologyKey == key && !key.isEmpty
    }
}

public final class LayoutStore {
    public let directory: URL
    public var file: URL { directory.appendingPathComponent("layouts.json") }
    private let fm = FileManager.default
    public init(directory: URL) { self.directory=directory }
    private func checkLink(_ url: URL) throws {
        if (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
            throw CoreError.invalid("Refusing symbolic link")
        }
    }
    public func load() throws -> Database {
        try checkLink(directory); try checkLink(file)
        guard fm.fileExists(atPath: file.path) else { return Database() }
        return try decode(file)
    }
    public func decode(_ url: URL) throws -> Database {
        try checkLink(url)
        let size = (try fm.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue ?? Int.max
        guard size <= 20 * 1024 * 1024 else { throw CoreError.invalid("File exceeds 20 MiB limit") }
        let db = try JSONDecoder().decode(Database.self, from: Data(contentsOf: url))
        try db.validate(); return db
    }
    public func save(_ db: Database) throws {
        try db.validate(); try checkLink(directory); try checkLink(file)
        let encoder=JSONEncoder(); encoder.outputFormatting=[.sortedKeys]
        let bytes = try encoder.encode(db)
        guard bytes.count <= 20 * 1024 * 1024 else { throw CoreError.invalid("Data exceeds 20 MiB limit") }
        try fm.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try fm.setAttributes([.posixPermissions:0o700], ofItemAtPath:directory.path)
        if let old = try? Data(contentsOf: file), old == bytes { return }
        let temp=directory.appendingPathComponent(".write-\(UUID().uuidString)")
        defer { try? fm.removeItem(at:temp) }
        guard fm.createFile(atPath:temp.path,contents:bytes,attributes:[.posixPermissions:0o600]) else { throw CoreError.invalid("Cannot create temporary file") }
        let handle=try FileHandle(forWritingTo:temp); try handle.synchronize(); try handle.close()
        if fm.fileExists(atPath:file.path) { _ = try fm.replaceItemAt(file,withItemAt:temp) }
        else { try fm.moveItem(at:temp,to:file) }
        try fm.setAttributes([.posixPermissions:0o600],ofItemAtPath:file.path)
    }
}
