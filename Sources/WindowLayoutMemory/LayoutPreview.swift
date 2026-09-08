import AppKit
import LayoutCore

final class LayoutCanvas: NSView {
    var scene: PreviewScene? { didSet { needsDisplay=true } }
    var selectedID: String? { didSet { needsDisplay=true } }
    var selected: ((String)->Void)?
    override var isFlipped: Bool { true }
    private var hitRegions: [(String,NSRect)]=[]
    override init(frame: NSRect) {
        super.init(frame:frame)
        setAccessibilityLabel("显示器与窗口布局示意图；使用右侧窗口列表选择和查看坐标")
        setAccessibilityRole(.image)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func setFrameSize(_ newSize: NSSize) { super.setFrameSize(newSize);needsDisplay=true }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.controlBackgroundColor.setFill();bounds.fill()
        hitRegions=[]
        guard let scene,let transform=PreviewTransform(displays:scene.topology.displays,width:bounds.width,height:bounds.height) else { return }
        func rect(_ value: Rect) -> NSRect {
            let r=transform.project(value);return NSRect(x:r.x,y:r.y,width:r.width,height:r.height)
        }
        for display in scene.topology.displays {
            let r=rect(display.frame),path=NSBezierPath(rect:r)
            NSColor.separatorColor.withAlphaComponent(0.15).setFill();path.fill()
            NSColor.secondaryLabelColor.setStroke();path.lineWidth=1.5;path.stroke()
        }
        for row in scene.rows {
            for (geometry,saved) in [(row.saved,true),(row.current,false)] {
                guard let geometry else { continue }
                let r=rect(geometry),path=NSBezierPath(rect:r)
                let color=saved ? NSColor.systemOrange:NSColor.controlAccentColor
                color.withAlphaComponent(saved ? 0.04:0.12).setFill();path.fill()
                color.setStroke();path.lineWidth=row.id == selectedID ? 3:1.2
                if saved { path.setLineDash([5,3],count:2,phase:0) }
                path.stroke()
                if r.width > 38 && r.height > 20 && (!saved || row.current == nil) {
                    let paragraph=NSMutableParagraphStyle();paragraph.lineBreakMode = .byTruncatingTail
                    let text=row.name+(saved ? " · 已存":"")
                    (text as NSString).draw(in:r.insetBy(dx:4,dy:3),withAttributes:[.font:NSFont.systemFont(ofSize:11),.foregroundColor:NSColor.labelColor,.paragraphStyle:paragraph])
                }
                hitRegions.append((row.id,r))
            }
        }
        for display in scene.topology.displays {
            let r=rect(display.frame)
            let label="\(display.name) · \(Int(display.frame.width))×\(Int(display.frame.height))"
            let paragraph=NSMutableParagraphStyle();paragraph.lineBreakMode = .byTruncatingTail
            (label as NSString).draw(in:NSRect(x:r.minX,y:max(2,r.minY-22),width:r.width,height:20),withAttributes:
                [.font:NSFont.systemFont(ofSize:11,weight:.semibold),.foregroundColor:NSColor.labelColor,.paragraphStyle:paragraph])
        }
    }
    override func mouseDown(with event: NSEvent) {
        let point=convert(event.locationInWindow,from:nil)
        let ids=hitRegions.reversed().filter { $0.1.contains(point) }.map(\.0)
        let unique=ids.reduce(into:[String]()) { if !$0.contains($1) { $0.append($1) } }
        guard !unique.isEmpty else { return }
        let index=selectedID.flatMap { unique.firstIndex(of:$0) }.map { ($0+1)%unique.count } ?? 0
        selected?(unique[index])
    }
}

private final class PreviewRoot: NSView {
    var arrange: ((NSRect)->Void)?
    override func layout() { super.layout();arrange?(bounds) }
    override func draw(_ dirtyRect: NSRect) { NSColor.windowBackgroundColor.setFill();dirtyRect.fill() }
}

final class LayoutPreviewController: NSObject, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate {
    private(set) var window: NSWindow?
    let canvas=LayoutCanvas(frame:.zero)
    let modes=NSSegmentedControl(labels:["当前布局","已保存布局","对比"],trackingMode:.selectOne,target:nil,action:nil)
    let combinations=NSPopUpButton(frame:.zero)
    private let table=NSTableView()
    private let detail=NSTextField(wrappingLabelWithString:"")
    private let statusLabel=NSTextField(wrappingLabelWithString:"")
    private let legend=NSTextField(labelWithString:"蓝色实线：最近读取    橙色虚线：已保存    只读，不表示遮挡顺序")
    private var scene: PreviewScene?
    private var profileIDs: [UUID?]=[nil]
    private var profileLabels: [String]=[]
    private var selectedID: String?
    private var pending: DispatchWorkItem?
    private(set) var closed=false
    private(set) var renderCount=0
    var onClose: (()->Void)?
    private var provider: ((UUID?,PreviewMode)->PreviewScene)?
    private var profiles: (()->[Profile])?
    private var status: (()->String)?
    init(provider: @escaping (UUID?,PreviewMode)->PreviewScene,profiles: @escaping ()->[Profile],status: @escaping ()->String) {
        self.provider=provider;self.profiles=profiles;self.status=status
        super.init()
        let window=NSWindow(contentRect:NSRect(x:0,y:0,width:1120,height:720),styleMask:[.titled,.closable,.resizable,.miniaturizable],backing:.buffered,defer:false)
        window.title="布局预览 · 只读";window.minSize=NSSize(width:860,height:540)
        window.isReleasedWhenClosed=false;window.delegate=self;self.window=window
        let root=PreviewRoot(frame:window.contentView!.bounds);window.contentView=root
        modes.selectedSegment=0;modes.target=self;modes.action=#selector(controlsChanged)
        combinations.target=self;combinations.action=#selector(combinationChanged)
        modes.setAccessibilityLabel("布局视图");combinations.setAccessibilityLabel("显示器组合")
        let scroll=NSScrollView();scroll.hasVerticalScroller=true;scroll.borderType = .bezelBorder
        let column=NSTableColumn(identifier:NSUserInterfaceItemIdentifier("window"));column.title="窗口列表（不显示私人标题）";column.width=290
        table.addTableColumn(column);table.headerView=nil;table.rowHeight=36;table.delegate=self;table.dataSource=self
        table.setAccessibilityLabel("窗口列表，方向键选择后查看下方详情")
        scroll.documentView=table
        detail.font=NSFont.monospacedSystemFont(ofSize:12,weight:.regular);detail.isSelectable=true
        statusLabel.font=NSFont.systemFont(ofSize:12);legend.font=NSFont.systemFont(ofSize:11)
        for view in [modes,combinations,statusLabel,canvas,scroll,detail,legend] { root.addSubview(view) }
        root.arrange = { [weak self,weak scroll] bounds in
            guard let self,let scroll else { return }
            let side=310.0,pad=18.0,contentWidth=bounds.width-side-pad*3
            self.modes.frame=NSRect(x:pad,y:bounds.height-48,width:300,height:28)
            self.combinations.frame=NSRect(x:334,y:bounds.height-48,width:bounds.width-352,height:28)
            self.statusLabel.frame=NSRect(x:pad,y:bounds.height-98,width:bounds.width-2*pad,height:42)
            self.canvas.frame=NSRect(x:pad,y:204,width:contentWidth,height:max(120,bounds.height-312))
            scroll.frame=NSRect(x:bounds.width-side-pad,y:204,width:side,height:max(120,bounds.height-312))
            self.legend.frame=NSRect(x:pad,y:175,width:bounds.width-2*pad,height:22)
            self.detail.frame=NSRect(x:pad,y:18,width:bounds.width-2*pad,height:150)
        }
        canvas.selected = { [weak self] id in self?.select(id) }
        root.needsLayout=true;window.center();refreshNow()
    }
    func show() { guard !closed else { return };window?.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true) }
    func requestRefresh() {
        guard !closed,pending == nil else { return }
        let task=DispatchWorkItem { [weak self] in self?.pending=nil;self?.refreshNow() }
        pending=task;DispatchQueue.main.asyncAfter(deadline:.now()+0.1,execute:task)
    }
    @objc func combinationChanged() { modes.selectedSegment=1;selectedID=nil;refreshNow() }
    @objc func controlsChanged() { selectedID=nil;refreshNow() }
    func refreshNow() {
        guard !closed,let provider else { return }
        let previous=profileIDs.indices.contains(combinations.indexOfSelectedItem) ? profileIDs[combinations.indexOfSelectedItem]:nil
        let available=profiles?() ?? []
        let ids:[UUID?]=[nil]+available.map { Optional($0.id) }
        let labels=["当前显示器组合"]+available.map { "\($0.name) · \($0.topology.displays.count)屏 · \($0.id.uuidString.prefix(6))" }
        if ids != profileIDs || labels != profileLabels {
            profileIDs=ids;profileLabels=labels;combinations.removeAllItems();combinations.addItems(withTitles:labels)
            combinations.selectItem(at:ids.firstIndex(of:previous) ?? 0)
        }
        let id=profileIDs[max(0,combinations.indexOfSelectedItem)]
        var scene=provider(id,PreviewMode(rawValue:modes.selectedSegment) ?? .current)
        if !scene.sameCombination && modes.selectedSegment != 1 {
            modes.selectedSegment=1;scene=provider(id,.saved)
        }
        modes.setEnabled(scene.sameCombination,forSegment:0);modes.setEnabled(scene.sameCombination,forSegment:2)
        self.scene=scene;canvas.scene=scene;renderCount+=1
        statusLabel.stringValue="\(scene.topology.displays.count)屏 · \(scene.rows.count)个窗口条目 · \(scene.sameCombination ? "当前组合":"其它组合：仅显示其独立保存布局")\n\(status?() ?? "") · 事件驱动更新；时间是读取时间，不保证后台窗口当前可见"
        table.reloadData()
        if let selectedID,scene.rows.contains(where: { $0.id == selectedID }) { select(selectedID) }
        else if let first=scene.rows.first { select(first.id) }
        else { selectedID=nil;canvas.selectedID=nil;detail.stringValue="暂无可显示窗口。当前视图需要辅助功能权限；尚未保存基准时，保存视图为空。后台组请激活后读取。" }
    }
    func numberOfRows(in tableView: NSTableView) -> Int { scene?.rows.count ?? 0 }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let item=scene?.rows[row] else { return nil }
        let label=NSTextField(labelWithString:"\(item.name)\n\(item.ambiguous ? "匹配歧义":item.current != nil ? "最近读取": "已保存 / 待出现")")
        label.font=NSFont.systemFont(ofSize:11);label.lineBreakMode = .byTruncatingTail
        return label
    }
    func tableViewSelectionDidChange(_ notification: Notification) {
        guard let rows=scene?.rows,rows.indices.contains(table.selectedRow) else { return }
        selectedID=rows[table.selectedRow].id;canvas.selectedID=selectedID;updateDetail()
    }
    private func select(_ id: String) {
        guard let index=scene?.rows.firstIndex(where: { $0.id == id }) else { return }
        selectedID=id;canvas.selectedID=id;table.selectRowIndexes(IndexSet(integer:index),byExtendingSelection:false);updateDetail()
    }
    private func updateDetail() {
        guard let scene,let row=scene.rows.first(where: { $0.id == selectedID }) else { return }
        func geometry(_ frame: Rect?) -> String {
            guard let frame else { return "无可信对应记录" }
            let display=scene.topology.owner(of:frame)
            return String(format:"位置 (%.1f, %.1f)，尺寸 %.1f × %.1f pt",frame.x,frame.y,frame.width,frame.height)+"；显示器：\(display?.name ?? "归属待确认") [\(display?.id.prefix(8) ?? "未知")]"
        }
        let delta=row.delta.map { String(format:"差异（读取值 - 保存值）：Δx %.1f，Δy %.1f，Δ宽 %.1f，Δ高 %.1f pt",$0.x,$0.y,$0.width,$0.height) } ?? "没有唯一对应数据，不计算差异"
        detail.stringValue="\(row.name) [\(row.bundle)]\n最近读取：\(geometry(row.current))\n已保存原始坐标：\(geometry(row.saved))\n\(delta)\n读取时间：\(row.observedAt?.formatted() ?? "无")；\(row.usable ? "读取时可操作（不证明当前可见）":"后台、不可操作或待出现")\(row.ambiguous ? "；匹配歧义":"")\n坐标为全局左上角原点、逻辑点；示意图不含屏幕内容，也不代表窗口遮挡顺序。"
    }
    func windowWillClose(_ notification: Notification) { dispose() }
    func dispose() {
        guard !closed else { return };closed=true
        pending?.cancel();pending=nil;provider=nil;profiles=nil;status=nil
        scene=nil;canvas.scene=nil;canvas.selected=nil;table.delegate=nil;table.dataSource=nil
        window?.delegate=nil;window?.orderOut(nil);window=nil
        let close=onClose;onClose=nil;close?()
    }
    deinit { pending?.cancel() }
}
