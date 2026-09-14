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
        return !modal && isStandard
            && (parentRole == "AXApplication" || (includeChildren && isChild))
    }
}

/// Explicit identifier, title or supported filename-extension rules.
public struct StageWindowRule: Codable, Equatable, Hashable {
    public var bundle: String, identifier: String, role: String, subrole: String
    public var exactTitle: String? = nil
    public var fileExtension: String? = nil
    public var windowCategory: String? = nil
    public static func isChatHistory(bundle: String, title: String) -> Bool {
        guard ["com.tencent.xinWeChat", "com.tencent.xinWeChat2"].contains(bundle), title.utf8.count <= 1024 else { return false }
        return title == "搜索聊天记录" || (title.hasSuffix("的聊天记录") && title.count > "的聊天记录".count)
    }
    public var normalized: StageWindowRule {
        guard valid, let exactTitle, Self.isChatHistory(bundle: bundle, title: exactTitle),
              role == "AXWindow", subrole == "AXStandardWindow" else { return self }
        var rule=self;rule.exactTitle=nil;rule.windowCategory="wechatChatHistory"
        return rule
    }
    public static let supportedExtensions: Set<String> = ["pdf","doc","docx","xls","xlsx","ppt","pptx","txt","md","csv","rtf","png","jpg","jpeg","gif","webp","heic","bmp","tif","tiff","svg","mp4","mov","m4v","mp3","wav","m4a","zip","rar","7z"]
    public static func extensionInTitle(_ title: String) -> String? {
        guard !title.isEmpty,title.utf8.count <= 1024 else { return nil }
        let ext=(title as NSString).pathExtension.lowercased()
        guard supportedExtensions.contains(ext),
              !(title as NSString).deletingPathExtension.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else { return nil }
        return ext
    }
    public init(bundle: String, identifier: String, role: String, subrole: String) {
        self.bundle=bundle;self.identifier=identifier;self.role=role;self.subrole=subrole
    }
    public var valid: Bool {
        let value=windowCategory ?? fileExtension ?? exactTitle ?? identifier
        return [windowCategory,fileExtension,exactTitle].compactMap { $0 }.count <= 1 &&
            (windowCategory == nil || (windowCategory == "wechatChatHistory" && ["com.tencent.xinWeChat","com.tencent.xinWeChat2"].contains(bundle) && role == "AXWindow" && subrole == "AXStandardWindow")) &&
            (fileExtension == nil || Self.supportedExtensions.contains(fileExtension!)) &&
            ((exactTitle == nil && fileExtension == nil && windowCategory == nil) || identifier.isEmpty) &&
            [bundle,value,role,subrole].allSatisfy { !$0.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty && $0.utf8.count <= 1024 }
    }
    public func matches(_ identity: WindowIdentity, traits: StageWindowTraits) -> Bool {
        guard valid,bundle == identity.bundle,role == traits.role,subrole == traits.subrole else { return false }
        if windowCategory == "wechatChatHistory" { return Self.isChatHistory(bundle: bundle, title: identity.title) }
        if let fileExtension { return Self.extensionInTitle(identity.title) == fileExtension }
        return exactTitle.map { $0 == identity.title } ?? (identifier == identity.identifier)
    }
}
