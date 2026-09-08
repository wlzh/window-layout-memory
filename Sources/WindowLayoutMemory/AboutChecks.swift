#if DEBUG
import AppKit

func runAboutChecks() -> Int32 {
    _=NSApplication.shared
    var passed=0,failed=0
    func check(_ name:String,_ value: @autoclosure ()->Bool) {
        if value() { passed+=1;print("PASS ABOUT \(name)") }
        else { failed+=1;print("FAIL ABOUT \(name)") }
    }
    var opened:[URL]=[]
    weak var releasedController: AboutWindowController?
    weak var releasedWindow: NSWindow?
    weak var releasedView: NSView?
    autoreleasepool {
        var controller: AboutWindowController?=AboutWindowController(openURL:{ opened.append($0) })
        releasedController=controller;releasedWindow=controller?.window;releasedView=controller?.window?.contentView
        check("metadata matches runtime version",controller?.versionText == "版本 \(AppVersion.marketing)-\(AppVersion.channel) · Build \(AppVersion.build)")
        check("all six destinations are available",controller?.links.count == AboutLink.allCases.count)
        check("destinations use HTTPS",AboutLink.allCases.allSatisfy { $0.url.scheme == "https" })
        check("license and documentation belong to this project",AboutLink.license.url.path == "/wlzh/window-layout-memory/blob/main/LICENSE" && AboutLink.documentation.url.path == "/wlzh/window-layout-memory/blob/main/docs/USER_GUIDE.md")
        for button in controller!.links { button.performClick(nil) }
        let expectedURLs=Set([
            "https://x.com/wlzh", "https://869hr.uk",
            "https://github.com/wlzh/window-layout-memory",
            "https://github.com/wlzh/window-layout-memory/blob/main/docs/USER_GUIDE.md",
            "https://github.com/wlzh/window-layout-memory/releases",
            "https://github.com/wlzh/window-layout-memory/blob/main/LICENSE"
        ])
        check("buttons dispatch exact URLs without network in tests",Set(opened.map(\.absoluteString)) == expectedURLs && opened.count == 6)
        let unknown=NSButton();unknown.identifier=NSUserInterfaceItemIdentifier("unknown")
        controller?.openLink(unknown)
        check("unknown link identifiers are ignored",opened.count == 6)
        for (name,appearance) in [("light",NSAppearance.Name.aqua),("dark",NSAppearance.Name.darkAqua)] {
            let window=controller!.window!;window.appearance=NSAppearance(named:appearance)
            window.orderFront(nil);window.contentView!.layoutSubtreeIfNeeded();window.displayIfNeeded()
            let root=window.contentView!
            func fits(_ view:NSView)->Bool {
                if view is NSTextField || view is NSButton || view is NSImageView {
                    let rect=view.convert(view.bounds,to:root)
                    if rect.minX < -1 || rect.maxX > root.bounds.width+1 || rect.minY < -1 || rect.maxY > root.bounds.height+1 { return false }
                }
                return view.subviews.allSatisfy { fits($0) }
            }
            check("\(name) layout contains every label and control",fits(root))
            check("\(name) layout has no ambiguous root constraints",!root.hasAmbiguousLayout && !root.subviews.contains(where: { $0.hasAmbiguousLayout }))
            if let i=CommandLine.arguments.firstIndex(of:"--render-about"),CommandLine.arguments.indices.contains(i+1),
               let bitmap=root.bitmapImageRepForCachingDisplay(in:root.bounds) {
                root.effectiveAppearance.performAsCurrentDrawingAppearance { root.cacheDisplay(in:root.bounds,to:bitmap) }
                do {
                    let path=CommandLine.arguments[i+1]+"-\(name).png"
                    try bitmap.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:path))
                    print("ABOUT_RENDER=\(path)")
                } catch { failed+=1;print("FAIL ABOUT render: \(error)") }
            }
        }
        var closes=0;controller?.onClose={ closes+=1 }
        controller?.window?.close()
        controller?.windowWillClose(Notification(name:NSWindow.willCloseNotification))
        check("close clears resources and calls owner once",controller?.closed == true && controller?.window == nil && controller?.links.isEmpty == true && closes == 1)
        unknown.identifier=NSUserInterfaceItemIdentifier(AboutLink.github.rawValue)
        controller?.openLink(unknown)
        check("closed controller cannot open links",opened.count == 6)
        controller=nil
    }
    RunLoop.main.run(until:Date(timeIntervalSinceNow:0.1))
    check("controller is released",releasedController == nil)
    check("window is released",releasedWindow == nil)
    check("content is released",releasedView == nil)
    autoreleasepool {
        let owner=AppDelegate();owner.showAbout()
        let first=owner.about
        owner.showAbout()
        check("repeated opening reuses one window",first === owner.about)
        owner.about?.window?.close()
        check("close clears app owner reference",owner.about == nil)
        owner.showAbout()
        check("opening after close creates a fresh window",owner.about != nil && owner.about !== first)
        owner.about?.window?.close()
    }
    print("ABOUT_TESTS passed=\(passed) failed=\(failed); native AppKit, injected URL opening")
    return failed == 0 ? 0:1
}
#endif
