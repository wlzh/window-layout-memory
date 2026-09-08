import AppKit
import ApplicationServices
import ServiceManagement
import LayoutCore

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    var engine: Engine!
    var item: NSStatusItem!
    var panel: NSWindow?
    var textView: NSTextView?
    var closeObserver: NSObjectProtocol?
    var preview: LayoutPreviewController?
    var about: AboutWindowController?
    func applicationDidFinishLaunching(_ notification: Notification) {
        engine=Engine()
        item=NSStatusBar.system.statusItem(withLength:NSStatusItem.variableLength)
        item.button?.image=NSImage(systemSymbolName:"rectangle.3.group",accessibilityDescription:"窗口布局记忆")
        item.button?.toolTip="Window Layout Memory"
        engine.changed = { [weak self] in self?.updatePanel();self?.preview?.requestRefresh() }
        let menu=NSMenu(); menu.autoenablesItems=false; menu.delegate=self; item.menu=menu
        if !AXIsProcessTrusted() { showPanel() }
    }
    func applicationShouldHandleReopen(_ sender:NSApplication,hasVisibleWindows:Bool) -> Bool {
        engine.displayChanged(); showPanel(); return true
    }
    func menuWillOpen(_ menu: NSMenu) {
        menu.removeAllItems()
        add(menu,"Window Layout Memory \(AppVersion.label)",nil)
        add(menu,engine.status,nil)
        menu.addItem(.separator())
        add(menu,"布局预览：当前 / 已保存 / 对比…",#selector(showPreview))
        add(menu,"保存已核对候选为基准 (\(engine.candidates.count))",#selector(save),enabled:!engine.busy && !engine.candidates.isEmpty)
        add(menu,"恢复当前前台窗口",#selector(restore),enabled:engine.profile != nil && !engine.busy)
        add(menu,"撤销最近恢复",#selector(undo),enabled:engine.canUndo)
        add(menu,engine.profile?.locked == true ? "解锁当前基准":"锁定当前基准",#selector(lock),enabled:engine.profile != nil)
        add(menu,"重命名当前布局…",#selector(rename),enabled:engine.profile != nil && !engine.busy)
        let copies=NSMenu()
        for p in engine.database.profiles where p.topology.key != engine.topology.key {
            let entry=add(copies,"\(p.name) / \(p.topology.displays.count)屏 / \(p.id.uuidString.prefix(6))",#selector(copyLayout(_:)))
            entry.representedObject=p
        }
        let copyItem=add(menu,"从其它布局手动映射显示器…",nil);copyItem.submenu=copies;copyItem.isEnabled = !engine.busy
        menu.addItem(.separator())
        let observe=add(menu,"自动核对窗口变化",#selector(toggleObserve)); observe.state=engine.database.preferences.autoObserve ? .on:.off
        let remember=add(menu,"自动保存手动拖动后的布局",#selector(toggleRemember)); remember.state=engine.database.preferences.autoRemember ? .on:.off
        let auto=add(menu,"激活/登录/切屏后自动恢复",#selector(toggleAuto)); auto.state=engine.database.preferences.autoRestore ? .on:.off
        let fill=add(menu,"台前调度：横屏自动铺满（拖左边缘调整留白）",#selector(toggleStageFill));fill.state=engine.database.preferences.stageFill ? .on:.off
        let login=add(menu,"登录时启动",#selector(toggleLogin)); login.state=SMAppService.mainApp.status == .enabled ? .on:.off
        add(menu,engine.guardState.paused ? "继续自动操作":"暂停自动操作",#selector(pause))
        add(menu,"取消待恢复并暂停",#selector(cancelRestores))
        menu.addItem(.separator())
        let exclude=NSMenu()
        for app in NSWorkspace.shared.runningApplications.filter({ $0.activationPolicy == .regular }).sorted(by:{ ($0.localizedName ?? "") < ($1.localizedName ?? "") }) {
            guard let bundle=app.bundleIdentifier,bundle != Bundle.main.bundleIdentifier else { continue }
            let entry=add(exclude,"\(app.localizedName ?? bundle) [\(bundle)]",#selector(toggleExclude(_:)))
            entry.representedObject=bundle; entry.state=engine.database.preferences.excludedBundles.contains(bundle) ? .on:.off
        }
        let excludedItem=add(menu,"排除应用",nil); excludedItem.submenu=exclude; excludedItem.isEnabled=true
        let roles=NSMenu()
        for w in engine.profile?.windows ?? [] {
            let entry=add(roles,"\(w.identity.bundle) / \(w.id.uuidString.prefix(6))",#selector(bind(_:)))
            entry.representedObject=w.id.uuidString
        }
        let roleItem=add(menu,"将当前窗口绑定到已存角色",nil); roleItem.submenu=roles; roleItem.isEnabled=true
        let history=NSMenu()
        for p in engine.database.history.reversed().filter({ $0.id == engine.profile?.id }) {
            let entry=add(history,"修订 \(p.revision) · \(p.windows.count) 窗口 · \(p.updatedAt.formatted())",#selector(history(_:)))
            entry.representedObject=p
        }
        let historyItem=add(menu,"恢复历史基准（不移动窗口）",nil); historyItem.submenu=history; historyItem.isEnabled=true
        add(menu,"导出私人布局备份…",#selector(exportBackup))
        add(menu,"导入布局备份…",#selector(importBackup))
        menu.addItem(.separator())
        add(menu,"布局状态与使用说明…",#selector(showPanel))
        add(menu,"授权辅助功能…",#selector(authorize))
        add(menu,"重新核对权限与窗口",#selector(refresh))
        add(menu,"关于窗口布局记忆…",#selector(showAbout))
        add(menu,"退出",#selector(quit),key:"q")
    }
    @discardableResult func add(_ menu:NSMenu,_ title:String,_ action:Selector?,enabled:Bool=true,key:String="") -> NSMenuItem {
        let entry=NSMenuItem(title:title,action:action,keyEquivalent:key); entry.target=self
        entry.isEnabled=action != nil && enabled; menu.addItem(entry); return entry
    }
    func confirm(_ message:String)->Bool {
        let alert=NSAlert(); alert.messageText=message; alert.addButton(withTitle:"继续"); alert.addButton(withTitle:"取消")
        return alert.runModal() == .alertFirstButtonReturn
    }
    @objc func save() { engine.saveCandidates() }
    @objc func restore() { engine.restore() }
    @objc func undo() { engine.undoRestore() }
    @objc func lock() { engine.toggleLock() }
    @objc func cancelRestores() { engine.cancelRestores() }
    @objc func rename() {
        guard let p=engine.profile else { return }
        let alert=NSAlert();alert.messageText="重命名当前布局（最多100字）"
        let field=NSTextField(string:p.name);field.frame=NSRect(x:0,y:0,width:340,height:24)
        alert.accessoryView=field;alert.addButton(withTitle:"保存");alert.addButton(withTitle:"取消")
        if alert.runModal() == .alertFirstButtonReturn { engine.renameProfile(field.stringValue) }
    }
    @objc func copyLayout(_ sender:NSMenuItem) {
        guard let source=sender.representedObject as? Profile else { return }
        let topology=engine.topology
        let alert=NSAlert();alert.messageText="手动指定每个旧显示器对应的当前显示器"
        alert.informativeText="每个目标只能选一次。保存将替换当前基准并保留历史，不移动窗口；完成后保持暂停。旧配置不变。"
        let view=NSView(frame:NSRect(x:0,y:0,width:560,height:CGFloat(source.topology.displays.count*64)))
        var menus: [NSPopUpButton]=[]
        for (index,display) in source.topology.displays.enumerated() {
            let y=CGFloat((source.topology.displays.count-index-1)*64)
            let label=NSTextField(labelWithString:"\(display.name) / \(display.id.prefix(8))")
            label.frame=NSRect(x:0,y:y+30,width:550,height:24);view.addSubview(label)
            let menu=NSPopUpButton(frame:NSRect(x:0,y:y,width:550,height:26))
            menu.addItem(withTitle:"请选择，不自动猜测")
            for current in topology.displays { menu.addItem(withTitle:"\(current.name) / \(current.id.prefix(8))") }
            menus.append(menu);view.addSubview(menu)
        }
        alert.accessoryView=view;alert.addButton(withTitle:"保存映射");alert.addButton(withTitle:"取消")
        guard alert.runModal() == .alertFirstButtonReturn,engine.topology.key == topology.key else { return }
        var mapping:[String:String]=[:]
        for (index,menu) in menus.enumerated() where menu.indexOfSelectedItem > 0 {
            mapping[source.topology.displays[index].id]=topology.displays[menu.indexOfSelectedItem-1].id
        }
        engine.copyProfile(source,mapping:mapping)
    }
    @objc func pause() { engine.togglePause() }
    @objc func refresh() { engine.displayChanged() }
    @objc func toggleObserve() { engine.setPreferences { $0.autoObserve.toggle() } }
    @objc func toggleStageFill() {
        if !engine.database.preferences.stageFill && !confirm("仅台前调度开启时，自动将横屏前台窗口铺满可用工作区。左侧默认留白200 pt；拖左边缘后记住新留白。原布局基准不变，竖屏不处理。关闭后停止铺满，不立即移动窗口。") { return }
        engine.setPreferences { $0.stageFill.toggle() }
    }
    @objc func toggleRemember() {
        if !engine.database.preferences.autoRemember && !confirm("自动保存前台窗口的鼠标拖动/缩放结果，包含新显示器组合。系统自动挤压或无鼠标证据的变化不会覆盖基准。键盘调整仍需手动保存。") { return }
        engine.setPreferences { $0.autoRemember.toggle() }
    }
    @objc func toggleAuto() {
        if !engine.database.preferences.autoRestore && !confirm("开启后，已保存且身份明确的窗口将在激活、切屏或登录后被移动。此开发版尚未完成硬件验收。") { return }
        engine.setPreferences { $0.autoRestore.toggle() }
    }
    @objc func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            else { try SMAppService.mainApp.register() }
        } catch { let a=NSAlert(); a.messageText="登录启动失败：\(error)"; a.runModal() }
    }
    @objc func toggleExclude(_ sender:NSMenuItem) {
        guard let bundle=sender.representedObject as? String else { return }
        engine.setPreferences {
            if $0.excludedBundles.contains(bundle) { $0.excludedBundles.removeAll { $0 == bundle } }
            else { $0.excludedBundles.append(bundle) }
        }
    }
    @objc func bind(_ sender:NSMenuItem) {
        guard let value=sender.representedObject as? String,let id=UUID(uuidString:value) else { return }
        engine.bindFocused(to:id)
    }
    @objc func history(_ sender:NSMenuItem) {
        if let p=sender.representedObject as? Profile,confirm("替换当前基准为历史修订？不会立即移动窗口。") { engine.useHistory(p) }
    }
    @objc func authorize() {
        let key=kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _=AXIsProcessTrustedWithOptions([key:true] as CFDictionary)
        NSWorkspace.shared.open(URL(string:"x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
    @objc func showPanel() {
        if panel == nil {
            let window=NSWindow(contentRect:NSRect(x:0,y:0,width:800,height:600),styleMask:[.titled,.closable,.resizable,.miniaturizable],backing:.buffered,defer:false)
            window.title="窗口布局记忆 · 开发预览"
            window.isReleasedWhenClosed=false
            let bounds=window.contentView!.bounds
            let scroll=NSScrollView(frame:NSRect(x:0,y:50,width:bounds.width,height:bounds.height-50))
            scroll.autoresizingMask=[.width,.height]; scroll.hasVerticalScroller=true
            let text=NSTextView(frame:scroll.bounds); text.isEditable=false; text.isSelectable=true
            text.font=NSFont.monospacedSystemFont(ofSize:13,weight:.regular); text.textContainerInset=NSSize(width:18,height:18)
            text.autoresizingMask=[.width]; text.isVerticallyResizable=true; text.textContainer?.widthTracksTextView=true
            scroll.documentView=text; window.contentView?.addSubview(scroll); panel=window; textView=text
            let buttons:[(String,Selector)] = [("授权辅助功能",#selector(authorize)),("重新核对",#selector(refresh)),("保存候选",#selector(save)),("关闭面板",#selector(closePanel))]
            for (index,entry) in buttons.enumerated() {
                let button=NSButton(title:entry.0,target:self,action:entry.1)
                button.frame=NSRect(x:18+index*150,y:10,width:140,height:30); button.bezelStyle = .rounded
                window.contentView?.addSubview(button)
            }
            window.center()
            closeObserver=NotificationCenter.default.addObserver(forName:NSWindow.willCloseNotification,object:window,queue:.main) { [weak self] _ in
                // Release after AppKit finishes closing; remove the observer itself too.
                DispatchQueue.main.async {
                    if let observer=self?.closeObserver { NotificationCenter.default.removeObserver(observer) }
                    self?.closeObserver=nil; self?.textView=nil; self?.panel=nil
                }
            }
        }
        updatePanel(); panel?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps:true)
    }
    @objc func closePanel() { panel?.close() }
    @objc func showPreview() {
        if preview == nil {
            preview=LayoutPreviewController(provider:{ [weak self] id,mode in
                self?.engine.previewScene(profileID:id,mode:mode) ?? PreviewScene.make(currentTopology:Topology([]),observations:[],profile:nil,mode:mode)
            },profiles:{ [weak self] in self?.engine.database.profiles ?? [] },status:{ [weak self] in self?.engine.status ?? "" })
            preview?.onClose = { [weak self] in DispatchQueue.main.async { self?.preview=nil } }
            engine.refresh()
        }
        preview?.show()
    }
    func updatePanel() {
        guard let textView else { return }
        textView.string=engine.report()+"\n\n使用：\n1. 菜单中授权辅助功能，再点重新核对。\n2. 依次激活需要记忆的窗口并停留约2秒。\n3. 点击保存候选，建立当前屏幕组合基准。\n4. 自动恢复默认关闭；确认基准后自行启用。\n\n普通桌面与台前调度均走相同保护路径。\n未激活窗口、同标题歧义、应用不支持通知时不会猜测。\n真实多屏/重启/8小时性能验收尚未完成，不应依赖此版作唯一布局备份。\n\nMIT License · Copyright 2026 wlzh\nhttps://github.com/wlzh/window-layout-memory"
    }
    @objc func exportBackup() {
        let panel=NSSavePanel(); panel.nameFieldStringValue="window-layout-backup.json"
        panel.message="含窗口标题和文稿路径，仅供私人备份，请勿公开。"
        guard panel.runModal() == .OK,let url=panel.url else { return }
        do {
            let data=try JSONEncoder().encode(engine.database); try data.write(to:url,options:.atomic)
            try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:url.path)
        } catch { let a=NSAlert(); a.messageText="导出失败：\(error)"; a.runModal() }
    }
    @objc func importBackup() {
        let panel=NSOpenPanel(); panel.canChooseDirectories=false; panel.allowsMultipleSelection=false
        guard panel.runModal() == .OK,let url=panel.url,confirm("导入将替换布局库。请先导出当前备份。自动恢复将关闭。") else { return }
        engine.importBackup(url)
    }
    @objc func showAbout() {
        if about == nil {
            about=AboutWindowController()
            about?.onClose={ [weak self] in self?.about=nil }
        }
        NSApp.activate(ignoringOtherApps:true)
        about?.showWindow(nil);about?.window?.makeKeyAndOrderFront(nil)
    }
    @objc func quit() { NSApp.terminate(nil) }
}

if CommandLine.arguments.contains("--self-test-about") {
    #if DEBUG
    exit(runAboutChecks())
    #else
    fputs("About checks are available in debug builds only.\n",stderr);exit(2)
    #endif
} else if CommandLine.arguments.contains("--self-test-preview") {
    #if DEBUG
    exit(runPreviewChecks())
    #else
    fputs("Preview checks are available in debug builds only.\n",stderr);exit(2)
    #endif
} else if CommandLine.arguments.contains("--self-test-engine") {
    #if DEBUG
    exit(runEngineChecks())
    #else
    fputs("Engine checks are available in debug builds only.\n",stderr);exit(2)
    #endif
} else if CommandLine.arguments.contains("--diagnose") {
    let topology=displaysNow()
    let report:[String:Any] = ["version":AppVersion.marketing,"release":AppVersion.label,"accessibilityTrusted":AXIsProcessTrusted(),
                              "stageManagerEnabled":EngineEnvironment().stageManagerEnabled() as Any? ?? NSNull(),
                              "displayCount":topology.displays.count,"topologyValid":topology.valid,
                              "displays":topology.displays.map { ["name":$0.name,"width":$0.frame.width,"height":$0.frame.height,"rotation":$0.rotation] as [String:Any] },
                              "os":ProcessInfo.processInfo.operatingSystemVersionString,
                              "stageManagerAndHardwareTests":"not-run","automaticRestoreDefault":false]
    print(String(data:try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]),encoding:.utf8)!)
} else {
    let app=NSApplication.shared; let delegate=AppDelegate()
    app.setActivationPolicy(.accessory); app.delegate=delegate; app.run()
}
