import AppKit
import ApplicationServices
import ServiceManagement
import LayoutCore
import UniformTypeIdentifiers

struct ExceptionSection {
    let title: String
    let detail: String
    let menu: NSMenu
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    var engine: Engine!
    var item: NSStatusItem!
    var panel: NSWindow?
    var textView: NSTextView?
    var closeObserver: NSObjectProtocol?
    var preview: LayoutPreviewController?
    var about: AboutWindowController?
    var exceptionSections: [ExceptionSection]=[]
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
        let stage=NSMenu(),automation=NSMenu(),layouts=NSMenu(),settings=NSMenu()
        let state=engine.guardState.paused ? "已暂停" : engine.guardState.settling ? "核对中" : "运行中"
        let status=add(menu,engine.hasAccessibilityPermission ? "\(engine.topology.displays.count)屏 · \(state)":"需要辅助功能权限…",
                       engine.hasAccessibilityPermission ? #selector(showPanel):#selector(authorize))
        status.toolTip=engine.status
        add(menu,"布局预览…",#selector(showPreview)).toolTip="查看当前、已保存及对比布局"
        add(menu,"保存已核对窗口（\(engine.candidates.count)）",#selector(save),enabled:!engine.busy && !engine.candidates.isEmpty).toolTip="将已核对候选保存为基准，不是完整桌面快照"
        add(menu,"恢复当前窗口",#selector(restore),enabled:engine.profile != nil && !engine.busy)
        add(menu,"撤销最近恢复",#selector(undo),enabled:engine.canUndo)
        add(layouts,engine.profile?.locked == true ? "解锁当前布局":"锁定当前布局",#selector(lock),enabled:engine.profile != nil && !engine.busy)
        add(layouts,"重命名当前布局…",#selector(rename),enabled:engine.profile != nil && !engine.busy)
        let copies=NSMenu()
        for p in engine.database.profiles where p.topology.key != engine.topology.key {
            let entry=add(copies,"\(p.name) / \(p.topology.displays.count)屏 / \(p.id.uuidString.prefix(6))",#selector(copyLayout(_:)))
            entry.representedObject=p
        }
        let observe=add(automation,"自动核对窗口变化",#selector(toggleObserve),enabled:!engine.busy); observe.state=engine.database.preferences.autoObserve ? .on:.off
        let remember=add(automation,"自动记忆手动调整",#selector(toggleRemember),enabled:engine.database.preferences.autoObserve && !engine.busy); remember.state=engine.database.preferences.autoRemember ? .on:.off
        remember.toolTip="需开启自动核对；仅记忆有鼠标拖动/缩放证据的变化"
        let auto=add(automation,"自动恢复保存布局",#selector(toggleAuto),enabled:!engine.busy); auto.state=engine.database.preferences.autoRestore ? .on:.off
        let fill=add(stage,"横屏自动铺满",#selector(toggleStageFill),enabled:!engine.busy);fill.state=engine.database.preferences.stageFill ? .on:.off
        fill.toolTip="仅系统台前调度开启时生效；默认左留100 pt，可拖左边缘调整"
        let portrait=add(stage,"竖屏横向撑满",#selector(toggleStagePortraitFill),enabled:!engine.busy)
        portrait.state=engine.database.preferences.stagePortraitFill ? .on:.off
        portrait.toolTip="默认关闭；左右撑满并保留左侧留白，纵向位置和高度不变，越界时修正；共用铺满例外"
        let children=add(stage,"同时铺满子窗口",#selector(toggleStageChildren),enabled:engine.database.preferences.anyStageFill && !engine.busy)
        children.indentationLevel=1;children.state=engine.database.preferences.stageFillChildren ? .on:.off
        stage.addItem(.separator())
        let exceptions=NSMenu()
        let windowActions=NSMenu()
        if let record=engine.stageMenuRecord {
            add(windowActions,"目标应用：\(record.app)",nil)
            let temporary=add(windowActions,"当前窗口暂不铺满",#selector(toggleStageWindow(_:)),enabled:!engine.busy)
            temporary.toolTip="仅本次运行中的此窗口，不影响同应用其它窗口"
            temporary.representedObject=record.token
            temporary.state=engine.stageSessionExclusions.contains(record.token) ? .on:.off
            if let rule=engine.stageRule(for:record) {
                let entry=add(windowActions,"永久排除此类窗口…",#selector(toggleStageKind(_:)),enabled:!engine.busy)
                entry.representedObject=rule
                entry.state=engine.database.preferences.stageExcludedKinds.contains(rule) ? .on:.off
            } else {
                add(windowActions,"无法永久排除：应用未提供可靠窗口标识",nil)
            }
        } else {
            let reason = !engine.hasAccessibilityPermission ? "需要辅助功能授权" : engine.guardState.paused ? "自动操作已暂停" : engine.guardState.settling ? "显示配置仍在核对" : "请激活目标窗口并等待核对后重新打开菜单"
            add(windowActions,"无可操作目标：\(reason)",nil)
        }
        if !engine.database.preferences.stageExcludedKinds.isEmpty {
            for rule in engine.database.preferences.stageExcludedKinds {
                let entry=add(exceptions,"\(rule.bundle) / \(rule.identifier.prefix(48))",#selector(removeStageKind(_:)),enabled:!engine.busy)
                entry.state = .on;entry.toolTip="点击取消排除：\(rule.identifier)"
                entry.representedObject=rule
            }
        }
        for token in engine.stageSessionExclusions.sorted() {
            let name=engine.allRecords.first(where:{$0.token == token})?.app ?? "已不可见窗口"
            let entry=add(exceptions,"临时 · \(name) · \(token)",#selector(toggleStageWindow(_:)),enabled:!engine.busy && engine.allRecords.contains(where:{$0.token == token}))
            entry.representedObject=token;entry.state = .on
        }
        if exceptions.items.isEmpty { add(exceptions,"尚未添加窗口例外。可在上方为当前窗口添加。",nil) }
        let apps=NSMenu()
        var listed=Set<String>()
        let running=NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }.sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
        let knownNames=Dictionary(running.compactMap { app -> (String,String)? in
            guard let bundle=app.bundleIdentifier else { return nil };return (bundle,app.localizedName ?? bundle)
        },uniquingKeysWith:{ first,_ in first }).merging(engine.database.preferences.stageExcludedApplications,uniquingKeysWith:{ live,_ in live })
        let nameCounts=Dictionary(grouping:knownNames.values,by:{ $0 }).mapValues(\.count)
        func appLabel(_ app:NSRunningApplication,_ bundle:String) -> String {
            let name=app.localizedName ?? bundle
            return nameCounts[name,default:0] > 1 ? "\(name) [\(bundle)]":name
        }
        func decorate(_ entry:NSMenuItem,_ app:NSRunningApplication,_ bundle:String) {
            entry.toolTip=bundle
            if let icon=app.icon?.copy() as? NSImage { icon.size=NSSize(width:16,height:16);entry.image=icon }
        }
        for app in running {
            guard let bundle=app.bundleIdentifier,bundle != Bundle.main.bundleIdentifier,listed.insert(bundle).inserted else { continue }
            let entry=add(apps,appLabel(app,bundle),#selector(toggleStageApp(_:)),enabled:!engine.busy)
            decorate(entry,app,bundle)
            entry.representedObject=["bundle":bundle,"name":app.localizedName ?? bundle]
            entry.state=engine.database.preferences.stageExcludedApplications[bundle] != nil ? .on:.off
        }
        let stopped=engine.database.preferences.stageExcludedApplications.filter { !listed.contains($0.key) }
        if !stopped.isEmpty {
            apps.addItem(.separator())
            for (bundle,name) in stopped.sorted(by:{ $0.key < $1.key }) {
                let label=nameCounts[name,default:0] > 1 ? "\(name) [\(bundle)]":name
                let entry=add(apps,"\(label) · 未运行",#selector(toggleStageApp(_:)),enabled:!engine.busy)
                entry.toolTip=bundle
                entry.representedObject=["bundle":bundle,"name":name];entry.state = .on
            }
        }
        apps.addItem(.separator())
        add(apps,"从文件选择应用…",#selector(chooseStageApp),enabled:!engine.busy)
        for entry in exceptions.items where entry.representedObject is StageWindowRule { entry.title="永久 · " + entry.title }
        exceptionSections=[
            ExceptionSection(title:"应用级",detail:"勾选后该应用的所有窗口不自动铺满。永久保存，重启后保留。",menu:apps),
            ExceptionSection(title:"当前窗口",detail:"临时仅针对本次运行中的窗口；永久按应用与窗口标识匹配，可能影响同标识窗口。",menu:windowActions),
            ExceptionSection(title:"已添加的窗口例外",detail:"点击已勾选的规则取消排除。应用级例外显示在上方，不在这里重复列出。",menu:exceptions)]
        for section in exceptionSections { section.menu.autoenablesItems=false }
        let unified=NSMenu()
        for (index,section) in exceptionSections.enumerated() {
            if index > 0 { unified.addItem(.separator()) }
            add(unified,section.title == "应用级" ? "应用级 · 永久保存":section.title,nil).toolTip=section.detail
            for entry in section.menu.items { unified.addItem(entry.copy() as! NSMenuItem) }
        }
        let exceptionItem=add(stage,"铺满例外",nil);exceptionItem.submenu=unified;exceptionItem.isEnabled=true
        let login=add(settings,"登录时启动",#selector(toggleLogin)); login.state=SMAppService.mainApp.status == .enabled ? .on:.off
        automation.addItem(.separator())
        let exclude=NSMenu()
        var globalListed=Set<String>()
        for app in running {
            guard let bundle=app.bundleIdentifier,bundle != Bundle.main.bundleIdentifier else { continue }
            guard globalListed.insert(bundle).inserted else { continue }
            let entry=add(exclude,appLabel(app,bundle),#selector(toggleExclude(_:)),enabled:!engine.busy)
            decorate(entry,app,bundle)
            entry.representedObject=bundle; entry.state=engine.database.preferences.excludedBundles.contains(bundle) ? .on:.off
        }
        for bundle in Set(engine.database.preferences.excludedBundles).subtracting(globalListed).sorted() {
            let entry=add(exclude,"\(bundle) · 未运行",#selector(toggleExclude(_:)),enabled:!engine.busy)
            entry.representedObject=bundle;entry.state = .on
        }
        let excludedItem=add(automation,"完全忽略应用",nil); excludedItem.submenu=exclude; excludedItem.isEnabled=true
        excludedItem.toolTip="停止所选应用的全部布局核对，不只是台前调度铺满"
        add(automation,"关闭自动恢复并暂停",#selector(cancelRestores))
        let roles=NSMenu()
        for w in engine.profile?.windows ?? [] {
            let entry=add(roles,"\(w.identity.bundle) / \(w.id.uuidString.prefix(6))",#selector(bind(_:)))
            entry.representedObject=w.id.uuidString
        }
        let roleItem=add(layouts,"关联已保存窗口",nil); roleItem.submenu=roles; roleItem.isEnabled = !engine.busy && !roles.items.isEmpty
        let copyItem=add(layouts,"从其它显示器组合映射",nil);copyItem.submenu=copies;copyItem.isEnabled = !engine.busy && !copies.items.isEmpty
        let history=NSMenu()
        for p in engine.database.history.reversed().filter({ $0.id == engine.profile?.id }) {
            let entry=add(history,"修订 \(p.revision) · \(p.windows.count) 窗口 · \(p.updatedAt.formatted())",#selector(history(_:)))
            entry.representedObject=p
        }
        let historyItem=add(layouts,"恢复历史基准",nil); historyItem.submenu=history; historyItem.isEnabled = !engine.busy && !history.items.isEmpty
        historyItem.toolTip="只修改保存基准，不立即移动窗口"
        layouts.addItem(.separator())
        add(layouts,"导出布局备份…",#selector(exportBackup))
        add(layouts,"导入布局备份…",#selector(importBackup),enabled:!engine.busy)
        add(settings,"权限与运行状态…",#selector(showPanel)).toolTip="包含辅助功能授权入口及详细诊断"
        add(settings,"重新核对窗口",#selector(refresh))
        menu.addItem(.separator())
        for (title,submenu) in [("台前调度铺满",stage),("自动记忆与恢复",automation),("布局管理",layouts),("设置与诊断",settings)] {
            let entry=add(menu,title,nil);entry.submenu=submenu;entry.isEnabled=true
        }
        menu.addItem(.separator())
        add(menu,engine.guardState.paused ? "继续自动操作":"暂停自动操作",#selector(pause))
        add(menu,"关于窗口布局记忆…",#selector(showAbout))
        add(menu,"退出",#selector(quit),key:"q")
        func configure(_ current:NSMenu) {
            current.autoenablesItems=false
            for entry in current.items { if let child=entry.submenu { configure(child) } }
        }
        configure(menu)
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
        if !engine.database.preferences.stageFill && !confirm("仅台前调度开启时，自动将横屏前台窗口铺满可用工作区。左侧默认留白100 pt；拖左边缘后记住新留白。成功后更新当前组合的窗口位置、大小和显示器记录，保留历史；锁定布局不覆盖。手动换屏后以新屏幕为准。此开关仅控制横屏，竖屏由独立开关控制；关闭后停止横屏铺满，不立即移动窗口。") { return }
        engine.setPreferences { $0.stageFill.toggle() }
    }
    @objc func toggleStageChildren() { engine.setPreferences { $0.stageFillChildren.toggle() } }
    @objc func toggleStagePortraitFill() {
        if !engine.database.preferences.stagePortraitFill && !confirm("仅台前调度开启时，将竖屏前台窗口横向撑满。沿用此组合/显示器的左侧留白，默认100 pt；保留纵向位置和高度，越界时夹回工作区。共用应用与窗口例外。成功后保存实际窗口布局，锁定布局不覆盖。") { return }
        engine.setPreferences { $0.stagePortraitFill.toggle() }
    }
    @objc func toggleStageWindow(_ sender:NSMenuItem) {
        guard let token=sender.representedObject as? String else { return }
        engine.toggleStageSessionExclusion(token)
    }
    @objc func toggleStageKind(_ sender:NSMenuItem) {
        guard let rule=sender.representedObject as? StageWindowRule else { return }
        if engine.database.preferences.stageExcludedKinds.contains(rule) { removeStageKind(sender);return }
        guard !engine.busy,let record=engine.stageMenuRecord,engine.stageRule(for:record) == rule else { return }
        guard confirm("永久排除此应用中相同AX标识的窗口：\(rule.bundle) / \(rule.identifier)。应用可能复用标识，这也会排除使用相同标识的主窗口；不按标题或图片内容猜测。可从台前调度铺满 → 铺满例外撤销。") else { return }
        engine.setPreferences { if $0.stageExcludedKinds.count < 200 { $0.stageExcludedKinds.append(rule) } }
    }
    @objc func removeStageKind(_ sender:NSMenuItem) {
        guard let rule=sender.representedObject as? StageWindowRule else { return }
        engine.setPreferences { $0.stageExcludedKinds.removeAll { $0 == rule } }
    }
    @objc func toggleStageApp(_ sender:NSMenuItem) {
        guard let entry=sender.representedObject as? [String:String],let bundle=entry["bundle"],let name=entry["name"] else { return }
        engine.setStageApplicationExclusion(bundle:bundle,name:name,excluded:engine.database.preferences.stageExcludedApplications[bundle] == nil)
    }
    static func stageApplication(at url: URL) -> (bundle: String,name: String)? {
        guard url.pathExtension.lowercased() == "app",let application=Bundle(url:url),
              let id=application.bundleIdentifier,!id.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,id.utf8.count <= 1024 else { return nil }
        let name=(application.object(forInfoDictionaryKey:"CFBundleDisplayName") as? String) ??
            (application.object(forInfoDictionaryKey:"CFBundleName") as? String) ?? url.deletingPathExtension().lastPathComponent
        guard !name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,name.utf8.count <= 1024 else { return nil }
        return (id,name)
    }
    static func stageApplicationPanel() -> NSOpenPanel {
        let panel=NSOpenPanel();panel.allowedContentTypes=[.applicationBundle]
        panel.canChooseDirectories=false;panel.canChooseFiles=true;panel.allowsMultipleSelection=false
        panel.treatsFilePackagesAsDirectories=false;panel.directoryURL=URL(fileURLWithPath:"/Applications",isDirectory:true)
        panel.message="选择不参与横屏铺满的应用；按应用标识保存，不移动或启动该应用。"
        return panel
    }
    @objc func chooseStageApp() {
        let panel=Self.stageApplicationPanel()
        guard panel.runModal() == .OK,let url=panel.url else { return }
        guard let app=Self.stageApplication(at:url) else {
            let alert=NSAlert();alert.messageText="无法读取有效的应用标识，请选择完整的.app应用。";alert.runModal();return
        }
        engine.setStageApplicationExclusion(bundle:app.bundle,name:app.name,excluded:true)
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
        textView.string=engine.report()+"\n\n使用：\n1. 授权辅助功能后切换目标应用；也可手动重新核对。\n2. 依次激活需要记忆的窗口并停留约2秒。\n3. 点击保存候选，建立当前屏幕组合基准。\n4. 自动恢复默认关闭；确认基准后自行启用。\n\n普通桌面与台前调度均走相同保护路径。\n未激活窗口、同标题歧义、应用不支持通知时不会猜测。\n真实多屏/重启/8小时性能验收尚未完成，不应依赖此版作唯一布局备份。\n\nMIT License · Copyright 2026 wlzh\nhttps://github.com/wlzh/window-layout-memory"
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
