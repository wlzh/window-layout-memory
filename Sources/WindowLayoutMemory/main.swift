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
    func applicationDidFinishLaunching(_ notification: Notification) {
        engine=Engine()
        item=NSStatusBar.system.statusItem(withLength:NSStatusItem.variableLength)
        item.button?.image=NSImage(systemSymbolName:"rectangle.3.group",accessibilityDescription:"窗口布局记忆")
        item.button?.toolTip="Window Layout Memory"
        engine.changed = { [weak self] in self?.updatePanel() }
        let menu=NSMenu(); menu.autoenablesItems=false; menu.delegate=self; item.menu=menu
        if !AXIsProcessTrusted() { showPanel() }
    }
    func applicationShouldHandleReopen(_ sender:NSApplication,hasVisibleWindows:Bool) -> Bool {
        engine.displayChanged(); showPanel(); return true
    }
    func menuWillOpen(_ menu: NSMenu) {
        menu.removeAllItems()
        add(menu,"Window Layout Memory 0.1.0（开发预览）",nil)
        add(menu,engine.status,nil)
        menu.addItem(.separator())
        add(menu,"保存已核对候选为基准 (\(engine.candidates.count))",#selector(save),enabled:!engine.busy && !engine.candidates.isEmpty)
        add(menu,"恢复当前前台窗口",#selector(restore),enabled:engine.profile != nil && !engine.busy)
        add(menu,"撤销最近恢复",#selector(undo),enabled:engine.canUndo)
        add(menu,engine.profile?.locked == true ? "解锁当前基准":"锁定当前基准",#selector(lock),enabled:engine.profile != nil)
        menu.addItem(.separator())
        let observe=add(menu,"自动核对变化（候选，不覆盖基准）",#selector(toggleObserve)); observe.state=engine.database.preferences.autoObserve ? .on:.off
        let auto=add(menu,"激活/登录/切屏后自动恢复",#selector(toggleAuto)); auto.state=engine.database.preferences.autoRestore ? .on:.off
        let login=add(menu,"登录时启动",#selector(toggleLogin)); login.state=SMAppService.mainApp.status == .enabled ? .on:.off
        add(menu,engine.guardState.paused ? "继续自动操作":"暂停自动操作",#selector(pause))
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
        add(menu,"GitHub / MIT / 文档",#selector(openProject))
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
    @objc func pause() { engine.togglePause() }
    @objc func refresh() { engine.displayChanged() }
    @objc func toggleObserve() { engine.setPreferences { $0.autoObserve.toggle() } }
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
    @objc func openProject() { NSWorkspace.shared.open(URL(string:"https://github.com/wlzh/window-layout-memory")!) }
    @objc func quit() { NSApp.terminate(nil) }
}

if CommandLine.arguments.contains("--diagnose") {
    let topology=displaysNow()
    let report:[String:Any] = ["version":"0.1.0","accessibilityTrusted":AXIsProcessTrusted(),
                              "displayCount":topology.displays.count,"topologyValid":topology.valid,
                              "displays":topology.displays.map { ["name":$0.name,"width":$0.frame.width,"height":$0.frame.height,"rotation":$0.rotation] as [String:Any] },
                              "os":ProcessInfo.processInfo.operatingSystemVersionString,
                              "stageManagerAndHardwareTests":"not-run","automaticRestoreDefault":false]
    print(String(data:try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]),encoding:.utf8)!)
} else {
    let app=NSApplication.shared; let delegate=AppDelegate()
    app.setActivationPolicy(.accessory); app.delegate=delegate; app.run()
}
