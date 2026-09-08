import AppKit

private final class AboutSurface: NSView {
    override var isOpaque: Bool { true }
    override func draw(_ dirtyRect:NSRect) {
        NSColor.windowBackgroundColor.setFill()
        NSBezierPath(rect:bounds).fill()
    }
}

enum AboutLink: String, CaseIterable {
    case author, website, github, documentation, releases, license
    var title: String {
        switch self {
        case .author: return "X @wlzh"
        case .website: return "869hr.uk"
        case .github: return "GitHub"
        case .documentation: return "使用文档"
        case .releases: return "版本记录"
        case .license: return "MIT License"
        }
    }
    var url: URL {
        let repository="https://github.com/wlzh/window-layout-memory"
        switch self {
        case .author: return URL(string:"https://x.com/wlzh")!
        case .website: return URL(string:"https://869hr.uk")!
        case .github: return URL(string:repository)!
        case .documentation: return URL(string:repository+"/blob/main/docs/USER_GUIDE.md")!
        case .releases: return URL(string:repository+"/releases")!
        case .license: return URL(string:repository+"/blob/main/LICENSE")!
        }
    }
}

final class AboutWindowController: NSWindowController, NSWindowDelegate {
    var onClose: (()->Void)?
    private var opener: ((URL)->Void)?
    private(set) var links: [NSButton]=[]
    private(set) var closed=false
    let versionText="版本 \(AppVersion.marketing)-\(AppVersion.channel) · Build \(AppVersion.build)"

    init(openURL: @escaping (URL)->Void = { NSWorkspace.shared.open($0) }) {
        let window=NSWindow(contentRect:NSRect(x:0,y:0,width:440,height:480),
            styleMask:[.titled,.closable,.fullSizeContentView],backing:.buffered,defer:false)
        super.init(window:window)
        opener=openURL
        window.title="关于窗口布局记忆"
        window.titlebarAppearsTransparent=true
        window.isRestorable=false;window.isReleasedWhenClosed=false;window.delegate=self
        window.backgroundColor = .windowBackgroundColor
        let root=AboutSurface();window.contentView=root
        func label(_ text:String,_ size:CGFloat,_ color:NSColor = .labelColor,_ weight:NSFont.Weight = .regular)->NSTextField {
            let view=NSTextField(wrappingLabelWithString:text)
            view.font=NSFont.systemFont(ofSize:size,weight:weight)
            view.textColor=color;view.alignment = .center;view.maximumNumberOfLines=0
            return view
        }
        func stack(_ views:[NSView],_ orientation:NSUserInterfaceLayoutOrientation = .vertical,_ spacing:CGFloat = 5)->NSStackView {
            let view=NSStackView(views:views);view.orientation=orientation;view.alignment = .centerY
            if orientation == .vertical { view.alignment = .centerX }
            view.spacing=spacing;return view
        }
        func link(_ item:AboutLink)->NSButton {
            let button=NSButton(title:item.title,target:self,action:#selector(openLink(_:)))
            button.identifier=NSUserInterfaceItemIdentifier(item.rawValue)
            button.isBordered=false;button.font=NSFont.systemFont(ofSize:12,weight:.medium)
            button.contentTintColor = .linkColor;button.toolTip=item.url.absoluteString
            button.setAccessibilityHelp("在默认浏览器中打开 \(item.title)")
            links.append(button);return button
        }
        let icon=NSImageView()
        icon.image=NSImage(systemSymbolName:"rectangle.3.group.fill",accessibilityDescription:"窗口布局记忆")
        icon.symbolConfiguration=NSImage.SymbolConfiguration(pointSize:42,weight:.regular)
        icon.contentTintColor = .controlAccentColor
        icon.widthAnchor.constraint(equalToConstant:72).isActive=true
        icon.heightAnchor.constraint(equalToConstant:64).isActive=true
        let title=label("窗口布局记忆",25,.labelColor,.semibold)
        let identity=stack([title,label("Window Layout Memory",13,.secondaryLabelColor),
            label(versionText,11,.secondaryLabelColor),label("开发预览",11,.systemOrange,.medium)])
        let author=stack([label("作者",12,.secondaryLabelColor),link(.author)],.horizontal,6)
        let resources=stack([link(.github),link(.documentation),link(.releases)],.horizontal,22)
        let divider=NSBox();divider.boxType = .separator;divider.widthAnchor.constraint(equalToConstant:310).isActive=true
        let footer=stack([link(.license),label("© 2026 wlzh",11,.tertiaryLabelColor)],.horizontal,10)
        let body=stack([icon,identity,label("按显示器组合，记住你的窗口布局",13,.secondaryLabelColor),
            stack([author,link(.website)]),divider,resources,
            label("布局数据保存在本机\n不上传窗口内容",11,.secondaryLabelColor),footer],.vertical,14)
        body.translatesAutoresizingMaskIntoConstraints=false;root.addSubview(body)
        NSLayoutConstraint.activate([
            body.centerXAnchor.constraint(equalTo:root.centerXAnchor),
            body.centerYAnchor.constraint(equalTo:root.centerYAnchor,constant:-2),
            body.widthAnchor.constraint(equalToConstant:376),
            body.topAnchor.constraint(greaterThanOrEqualTo:root.topAnchor,constant:28),
            body.bottomAnchor.constraint(lessThanOrEqualTo:root.bottomAnchor,constant:-20)
        ])
        window.center()
    }
    required init?(coder:NSCoder) { fatalError("init(coder:) is unavailable") }
    @objc func openLink(_ sender:NSButton) {
        guard !closed,let raw=sender.identifier?.rawValue,let link=AboutLink(rawValue:raw) else { return }
        opener?(link.url)
    }
    func windowWillClose(_ notification:Notification) {
        guard !closed else { return }
        closed=true;opener=nil
        links.forEach { $0.target=nil };links=[]
        window?.delegate=nil;window?.contentView=nil;window=nil
        let callback=onClose;onClose=nil;callback?()
    }
}
