import AppKit
import ApplicationServices
import LayoutCore

final class Engine {
    let service: WindowService
    private let environment: EngineEnvironment
    let store: LayoutStore
    private let io=DispatchQueue(label:"uk.869hr.WindowLayoutMemory.storage",qos:.utility)
    private(set) var database=Database()
    private(set) var topology: Topology
    private(set) var guardState=GuardState()
    private(set) var records: [pid_t:[AXRecord]]=[:]
    private var recordContexts: [pid_t:(String,Date)]=[:]
    private(set) var candidates: [String:SavedWindow]=[:]
    private var evidence: [String:(Rect,TimeInterval)]=[:]
    private var bindings: [UUID:String]=[:]
    private var attempted: Set<String>=[]
    private var moving: Set<String>=[]
    private var pending: Set<pid_t>=[]
    private var inFlight: Set<pid_t>=[]
    private var rescan: Set<pid_t>=[]
    private var timer: DispatchWorkItem?
    private var settleTask: DispatchWorkItem?
    private var saveTask: DispatchWorkItem?
    private var learning=LearningGate()
    private var mouseMonitor: Any?
    private var pointerStart: (token:String,pid:pid_t,frame:Rect,point:CGPoint,time:TimeInterval)?
    private var gestureOrigins: [String:Rect]=[:]
    private var leftEdgeGestures: Set<String>=[]
    private var stageAttempted: Set<String>=[]
    private var stageFocus: String?
    private var stageUserDisplays: [String:String]=[:]
    private var stageSaveQueue: [String:AXRecord]=[:]
    private(set) var stageSessionExclusions: Set<String>=[]
    private var lastStageState=false
    private var skipRestoreAfterModeOff: String?
    private var learnAfter: TimeInterval=0
    private var observers: [NSObjectProtocol]=[]
    private var undo: [(AXRecord,Rect)]=[]
    private var undoGeneration: UInt64=0
    private var suppressUntil: [String:TimeInterval]=[:]
    private(set) var busy=false
    private(set) var storageFailed=false
    private(set) var status="启动中"
    private(set) var issues: [String:String]=[:]
    var changed: (()->Void)?
    var profile: Profile? { database.profiles.first { $0.topology.key == topology.key } }
    var allRecords: [AXRecord] { records.values.flatMap { $0 } }
    var canUndo: Bool { !undo.isEmpty && undoGeneration == guardState.generation }
    var hasAccessibilityPermission: Bool { environment.trusted() }
    init(service: WindowService = AXService(), store: LayoutStore? = nil, environment: EngineEnvironment = EngineEnvironment()) {
        self.service=service;self.environment=environment;self.topology=environment.topology()
        self.store=store ?? LayoutStore(directory:FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("WindowLayoutMemory",isDirectory:true))
        do { database=try self.store.load() } catch { storageFailed=true; status="数据读取失败，禁止覆盖"; issues["storage"]="\(error)" }
        service.onEvent = { [weak self] pid,name,element in
            guard let self else { return }
            if name == kAXFocusedWindowChangedNotification || name == kAXApplicationActivatedNotification || name == kAXApplicationDeactivatedNotification {
                self.stageFocus=nil
                self.stageAttempted.removeAll(keepingCapacity:true)
                self.evidence = self.evidence.filter { !$0.key.hasPrefix("\(pid):") }
                if self.pointerStart?.pid == pid { self.pointerStart=nil }
                self.learnAfter=self.environment.now()+1
            }
            self.enqueue(pid)
        }
        if environment.observeSystem {
        mouseMonitor=NSEvent.addGlobalMonitorForEvents(matching:[.leftMouseDown,.leftMouseUp]) { [weak self] event in
            self?.pointerEvent(down:event.type == .leftMouseDown)
        }
        if mouseMonitor == nil { issues["mouse"]="鼠标手势监听不可用，自动记忆不可用；仍可手动保存" }
        let center=NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification,NSWorkspace.didActivateApplicationNotification,
                     NSWorkspace.didHideApplicationNotification,NSWorkspace.didUnhideApplicationNotification] {
            observers.append(center.addObserver(forName:name,object:nil,queue:.main) { [weak self] note in
                guard let app=note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
                if name == NSWorkspace.didActivateApplicationNotification {
                    self?.stageFocus=nil;self?.stageAttempted.removeAll(keepingCapacity:true)
                }
                self?.enqueue(app.processIdentifier)
            })
        }
        observers.append(center.addObserver(forName:NSWorkspace.didTerminateApplicationNotification,object:nil,queue:.main) { [weak self] note in
            guard let self,let app=note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            let pid=app.processIdentifier
            self.service.detach(pid); self.records[pid]=nil; self.recordContexts[pid]=nil; self.pending.remove(pid)
            self.stageUserDisplays=self.stageUserDisplays.filter { !$0.key.hasPrefix("\(pid):") }
            self.stageSaveQueue=self.stageSaveQueue.filter { !$0.key.hasPrefix("\(pid):") }
            self.stageSessionExclusions=self.stageSessionExclusions.filter { !$0.hasPrefix("\(pid):") }
            self.evidence=self.evidence.filter { !$0.key.hasPrefix("\(pid):") }
            self.candidates=self.candidates.filter { !$0.key.hasPrefix("\(pid):") }
            self.bindings=self.bindings.filter { !$0.value.hasPrefix("\(pid):") }
            self.changed?()
        })
        observers.append(center.addObserver(forName:NSWorkspace.willSleepNotification,object:nil,queue:.main) { [weak self] _ in
            self?.guardState.sleeping=true; self?.invalidate("睡眠，已暂停")
        })
        observers.append(center.addObserver(forName:NSWorkspace.didWakeNotification,object:nil,queue:.main) { [weak self] _ in
            self?.guardState.sleeping=false; self?.displayChanged()
        })
        observers.append(NotificationCenter.default.addObserver(forName:NSApplication.didChangeScreenParametersNotification,object:nil,queue:.main) { [weak self] _ in self?.displayChanged() })
        CGDisplayRegisterReconfigurationCallback(Self.screenCallback,Unmanaged.passUnretained(self).toOpaque())
        }
        displayChanged()
    }
    private static let screenCallback: CGDisplayReconfigurationCallBack = { _,_,context in
            guard let context else { return }
            let engine=Unmanaged<Engine>.fromOpaque(context).takeUnretainedValue()
            DispatchQueue.main.async { engine.displayChanged() }
        }
    deinit {
        if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
        timer?.cancel();settleTask?.cancel();saveTask?.cancel()
        for observer in observers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            NotificationCenter.default.removeObserver(observer)
        }
        if environment.observeSystem { CGDisplayRemoveReconfigurationCallback(Self.screenCallback,Unmanaged.passUnretained(self).toOpaque()) }
        for pid in records.keys { service.detach(pid) }
    }
    private func invalidate(_ message: String) {
        guardState.invalidate(); timer?.cancel(); timer=nil; settleTask?.cancel(); pending=[]
        saveTask?.cancel(); saveTask=nil; learning.reset()
        pointerStart=nil;gestureOrigins.removeAll(keepingCapacity:true)
        leftEdgeGestures=[];stageAttempted=[];stageFocus=nil
        stageUserDisplays=[:];stageSaveQueue=[:]
        evidence=[:]; candidates=[:]; attempted=[]; suppressUntil=[:]; undo=[]; rescan=[]
        issues=issues.filter { !$0.key.hasPrefix("restore:") }
        status=message; changed?()
    }
    // Capture the handle before movement; AX geometry notifications may arrive after mouse-up.
    func pointerEvent(down: Bool) {
        let now=environment.now()
        let stageGesture=database.preferences.anyStageFill && environment.stageManagerEnabled() == true
        guard guardState.permits(guardState.generation,key:topology.key),environment.trusted(),
              environment.topology().key == topology.key,let point=environment.pointerLocation() else {
            pointerStart=nil;learning.reset();gestureOrigins.removeAll();return
        }
        if down {
            pointerStart=nil
            guard now >= learnAfter,let pid=environment.frontPID(),
                  let record=records[pid]?.first(where:{ $0.focused && $0.usable }),
                  !database.preferences.excludedBundles.contains(record.identity.bundle),
                  !moving.contains(record.token),(stageGesture || now >= suppressUntil[record.token,default:0]),
                  record.frame.isDragHandle(x:point.x,y:point.y) else { return }
            learning.discard(record.token);gestureOrigins[record.token]=nil
            leftEdgeGestures.remove(record.token)
            pointerStart=(record.token,pid,record.frame,point,now)
        } else {
            guard let start=pointerStart else { return }
            pointerStart=nil
            guard environment.frontPID() == start.pid,now >= start.time,now-start.time <= 120,
                  hypot(point.x-start.point.x,point.y-start.point.y) >= 3,
                  !moving.contains(start.token),(stageGesture || now >= suppressUntil[start.token,default:0]) else { return }
            if stageGesture { suppressUntil[start.token]=nil }
            if gestureOrigins.count >= 500 { gestureOrigins.removeAll();learning.reset() }
            gestureOrigins[start.token]=start.frame
            if StageFill.isLeftEdge(start.frame,x:start.point.x,y:start.point.y) { leftEdgeGestures.insert(start.token) }
            learning.note(start.token,now:now,pointerDown:true,eligible:true)
            enqueue(start.pid)
        }
    }
    func displayChanged() {
        invalidate("等待显示配置稳定")
        guard !guardState.sleeping else { return }
        let generation=guardState.generation
        let first=environment.topology()
        let task=DispatchWorkItem { [weak self] in
            guard let self,self.guardState.generation == generation else { return }
            let latest=self.environment.topology()
            guard first.key == latest.key else { self.displayChanged(); return }
            self.topology=latest; self.guardState.topologyKey=latest.key
            self.guardState.settling = !latest.valid
            self.guardState.trusted=self.environment.trusted()
            self.learnAfter=self.environment.now()+2
            self.status = !latest.valid ? "显示配置不可用或镜像模式" : !self.guardState.trusted ? "需要辅助功能权限" : "就绪；前台核对后记录候选"
            self.refresh(); self.changed?()
        }
        settleTask=task; DispatchQueue.main.asyncAfter(deadline:.now()+1,execute:task)
    }
    func refresh() {
        guardState.trusted=environment.trusted()
        if !guardState.trusted { status="需要辅助功能权限"; changed?(); return }
        for app in environment.applications() { enqueue(app.pid) }
    }
    private func enqueue(_ pid: pid_t) {
        let trusted=environment.trusted()
        if trusted != guardState.trusted {
            guardState.trusted=trusted
            displayChanged()
            return
        }
        guard pid != ProcessInfo.processInfo.processIdentifier, !guardState.paused,!guardState.sleeping,
              !guardState.settling,guardState.trusted, pending.count < 128 else { return }
        pending.insert(pid)
        if inFlight.contains(pid) { pending.remove(pid); rescan.insert(pid); return }
        guard timer == nil else { return }
        let task=DispatchWorkItem { [weak self] in self?.drain() }
        timer=task; DispatchQueue.main.asyncAfter(deadline:.now()+0.6,execute:task)
    }
    private func drain() {
        timer=nil
        let front=environment.frontPID()
        let work=pending.sorted { ($0 == front ? 0:1,$0) < ($1 == front ? 0:1,$1) }; pending=[]
        for pid in work where !inFlight.contains(pid) {
            guard let app=environment.applications().first(where: { $0.pid == pid }),
                  !database.preferences.excludedBundles.contains(app.bundle) else { continue }
            let bundle=app.bundle
            let generation=guardState.generation,key=topology.key
            guard guardState.permits(generation,key:key) else { continue }
            inFlight.insert(pid)
            service.scan(pid:pid,bundle:bundle,name:app.name,
                         front:environment.frontPID() == pid,hidden:app.hidden,allowed:{ [weak self] in
                guard let self else { return false }
                return self.guardState.permits(generation,key:key) && self.environment.topology().key == key
            }) { [weak self] result in
                guard let self else { return }
                self.inFlight.remove(pid)
                if self.rescan.remove(pid) != nil { self.enqueue(pid) }
                guard self.guardState.permits(generation,key:key),self.environment.topology().key == key else { return }
                let tokens=Set(result.records.map(\.token))
                if result.error == nil {
                    self.stageUserDisplays=self.stageUserDisplays.filter { !$0.key.hasPrefix("\(pid):") || tokens.contains($0.key) }
                    self.stageSessionExclusions=self.stageSessionExclusions.filter { !$0.hasPrefix("\(pid):") || tokens.contains($0) }
                    self.evidence=self.evidence.filter { !$0.key.hasPrefix("\(pid):") || tokens.contains($0.key) }
                    self.candidates=self.candidates.filter { !$0.key.hasPrefix("\(pid):") || tokens.contains($0.key) }
                }
                self.records[pid]=result.records
                self.recordContexts[pid]=(key,Date())
                self.issues[bundle]=result.error
                self.ingest(result.records)
                self.changed?()
            }
        }
    }
    private func ingest(_ batch: [AXRecord]) {
        let now=environment.now()
        let stageEnabled=database.preferences.anyStageFill && environment.stageManagerEnabled() == true
        if lastStageState != stageEnabled {
            lastStageState=stageEnabled;stageFocus=nil;stageAttempted=[];candidates=[:]
            stageUserDisplays=[:];stageSaveQueue=[:]
            learning.reset();gestureOrigins=[:];leftEdgeGestures=[]
        }
        let matching=Matcher.assign(profile?.windows ?? [],allRecords.map(\.live),bindings:bindings)
        for record in batch where record.focused && record.usable {
            guard environment.frontPID() == record.pid else { continue }
            if stageEnabled,let owner=topology.owner(of:record.frame),stageTarget(owner) != nil,!stagePermits(record) {
                // Excluded popups must not fall through to restore or baseline learning.
                candidates[record.token]=nil;evidence[record.token]=nil
                learning.discard(record.token);gestureOrigins[record.token]=nil;leftEdgeGestures.remove(record.token)
                continue
            }
            guard evidence[record.token] != nil || evidence.count < 500 else { issues["capacity"]="已达到500个候选上限，请保存并重新核对"; continue }
            if now < suppressUntil[record.token,default:0] {
                // Keep a newly activated window pending through the finite move guard.
                // Ordinary geometry notifications must not rearm a completed fill.
                if stageEnabled,!stageAttempted.contains(record.token) { enqueue(record.pid) }
                continue
            }
            if let old=evidence[record.token],old.0.close(to:record.frame,tolerance:0.5),now-old.1 >= 0.45 {
                let pointerDown=environment.pointerDown()
                if pointerDown { enqueue(record.pid); continue }
                if gestureOrigins[record.token]?.close(to:record.frame,tolerance:0.5) == true {
                    learning.discard(record.token);gestureOrigins[record.token]=nil
                }
                let userMoved=learning.permits(record.token,now:now,pointerDown:false,stable:true,
                    eligible:gestureOrigins[record.token].map { !$0.close(to:record.frame,tolerance:0.5) } == true)
                if stageEnabled,let owner=topology.owner(of:record.frame),
                   let target=stageDestination(record) {
                    candidates[record.token]=nil
                    if stageFocus != record.token { stageFocus=record.token;stageAttempted.remove(record.token) }
                    if userMoved {
                        if busy { enqueue(record.pid);continue }
                        stageAttempted.insert(record.token)
                        if let origin=gestureOrigins[record.token],topology.owner(of:origin)?.id != owner.id {
                            guard stageUserDisplays[record.token] != nil || stageUserDisplays.count < 500 else {
                                status="手动换屏跟踪已达上限，未执行自动移动";continue
                            }
                            stageUserDisplays[record.token]=owner.id
                            if let localTarget=stageTarget(owner,frame:record.frame) { applyStageFill(record,target:localTarget) }
                            else if database.preferences.autoRemember {
                                let role=matching.resolved.first(where:{$0.value == record.token})?.key
                                if role != nil || matching.ambiguous.isEmpty {
                                    save([(record.token,SavedWindow(id:role ?? UUID(),identity:record.identity,displayID:owner.id,frame:record.frame,sourceVisible:owner.visible))],automatic:true)
                                }
                            }
                        } else if stageTarget(owner,frame:record.frame) != nil,
                           leftEdgeGestures.contains(record.token),let origin=gestureOrigins[record.token],
                           topology.owner(of:origin)?.id == owner.id,
                           let inset=StageFill.learnedInset(origin:origin,current:record.frame,display:environment.stageDisplay(owner)) {
                            if busy { enqueue(record.pid);continue }
                            rememberStageInset(inset,display:owner,record:record)
                        } else if database.preferences.stagePortraitFill,owner.frame.height > owner.frame.width,
                                  let localTarget=stageTarget(owner,frame:record.frame) {
                            applyStageFill(record,target:localTarget)
                        }
                        learning.discard(record.token);gestureOrigins[record.token]=nil;leftEdgeGestures.remove(record.token)
                    } else if !stageAttempted.contains(record.token) {
                        stageAttempted.insert(record.token)
                        applyStageFill(record,target:target,followSavedDisplay:true)
                    }
                    continue
                }
                if userMoved { attempted.insert("\(guardState.generation):\(record.token)") }
                if skipRestoreAfterModeOff == record.token {
                    attempted.insert("\(guardState.generation):\(record.token)");skipRestoreAfterModeOff=nil
                }
                if !userMoved,database.preferences.autoRestore,let p=profile { restoreRecord(record,profile:p,matching:matching,manual:false) }
                guard database.preferences.autoObserve,now >= suppressUntil[record.token,default:0],
                      let owner=topology.owner(of:record.frame) else { continue }
                let role=matching.resolved.first(where:{ $0.value == record.token })?.key
                if let role { bindings[role]=record.token }
                candidates[record.token]=SavedWindow(id:role ?? candidates[record.token]?.id ?? UUID(),identity:record.identity,
                                                    displayID:owner.id,frame:record.frame,sourceVisible:owner.visible)
                if userMoved && database.preferences.autoRemember { scheduleRemember() }
            } else {
                evidence[record.token]=(record.frame,now); enqueue(record.pid)
            }
        }
        if let p=profile {
            status="已保存 \(p.windows.count)；已核对候选 \(candidates.count)；待激活/匹配窗口在详情中查看"
        } else { status="新配置：已核对 \(candidates.count) 个窗口，保存后建立基准" }
    }
    func saveCandidates() {
        guard !busy,!storageFailed,guardState.permits(guardState.generation,key:topology.key),!candidates.isEmpty else { status="没有可信候选或暂不可保存"; changed?(); return }
        save(Array(candidates),automatic:false)
    }
    private func stageTarget(_ display: Display, frame: Rect? = nil) -> Rect? {
        guard database.preferences.anyStageFill,environment.stageManagerEnabled() == true else { return nil }
        let work=environment.stageDisplay(display)
        let inset=database.preferences.stageInsets[StageFill.insetKey(topology:topology,display:display)] ?? StageFill.defaultInset
        if display.frame.height > display.frame.width {
            guard database.preferences.stagePortraitFill else { return nil }
            return StageFill.portraitTarget(display:work,frame:frame ?? work.visible,inset:inset)
        }
        guard database.preferences.stageFill else { return nil }
        return StageFill.target(display:work,inset:inset)
    }
    // Explicit mouse relocation wins until the verified replacement has been saved.
    private func stageDestination(_ record: AXRecord) -> Rect? {
        guard stagePermits(record) else { return nil }
        guard database.preferences.anyStageFill,environment.stageManagerEnabled() == true,
              let current=topology.owner(of:record.frame) else { return nil }
        if stageUserDisplays[record.token] == current.id { return stageTarget(current,frame:record.frame) ?? record.frame }
        if database.preferences.autoRestore,let profile {
            let matching=Matcher.assign(profile.windows,allRecords.map(\.live),bindings:bindings)
            if let role=matching.resolved.first(where:{ $0.value == record.token })?.key,
               let saved=profile.windows.first(where:{ $0.id == role }),
               let destination=topology.displays.first(where:{ $0.id == saved.displayID }) {
                if let filled=stageTarget(destination,frame:current.id == destination.id ? record.frame : saved.target(in:topology)) { return filled }
                // A destination with its fill mode disabled retains ordinary restoration.
                if current.id != destination.id { return saved.target(in:topology) }
                return nil
            }
        }
        // Unknown or ambiguous windows may fill locally, but never guess another screen.
        return stageTarget(current,frame:record.frame)
    }
    private func rememberStageInset(_ inset: Double, display: Display, record: AXRecord) {
        guard !storageFailed else { return }
        let key=StageFill.insetKey(topology:topology,display:display)
        var next=database
        next.preferences.stageInsets[key]=inset
        let generation=guardState.generation
        let finish: (Bool)->Void = { [weak self] success in
            guard let self,success,self.guardState.generation == generation,
                  let target=self.stageTarget(display,frame:record.frame) else { return }
            self.applyStageFill(record,target:target)
        }
        if next == database { finish(true) }
        else { persist(next,message:"已记忆此组合/显示器的左侧留白：\(Int(inset)) pt",completion:finish) }
    }
    private func applyStageFill(_ record: AXRecord, target: Rect, followSavedDisplay: Bool = false) {
        guard stagePermits(record),!moving.contains(record.token) else { return }
        if record.frame.close(to:target,tolerance:0.5) {
            queueStageSave(record,target:target);return
        }
        let generation=guardState.generation,key=topology.key,revision=profile?.revision
        moving.insert(record.token);suppressUntil[record.token]=environment.now()+2
        candidates[record.token]=nil;learning.discard(record.token);gestureOrigins[record.token]=nil
        // Only destinations without an enabled fill mode use ordinary restoration.
        let destination=topology.owner(of:target)
        let fillsDestination=destination.map { stageTarget($0,frame:target) != nil } == true
        let placement = fillsDestination ? service.fill : service.move
        placement(record,target,{ [weak self] in
            guard let self else { return false }
            let latest=self.environment.topology()
            guard self.guardState.permits(generation,key:key),self.environment.trusted(),latest.key == key,
                  self.stagePermits(record),
                  !self.environment.pointerDown(),self.environment.frontPID() == record.pid,
                  !self.database.preferences.excludedBundles.contains(record.identity.bundle),
                  self.profile?.revision == revision,
                  let owner=latest.owner(of:record.frame),
                  let currentTarget=followSavedDisplay ? self.stageDestination(record) : self.stageTarget(owner,frame:record.frame) else { return false }
            return currentTarget.close(to:target,tolerance:0.5)
        }) { [weak self] actual,error in
            guard let self else { return }
            self.moving.remove(record.token)
            guard self.guardState.generation == generation else { return }
            let verified=error == nil && actual?.close(to:target,tolerance:2) == true
            let resultError=error ?? (verified ? nil:"铺满未达到目标，未保存")
            self.issues["stage:\(record.token)"]=resultError
            self.status=resultError ?? "已核验自动铺满：\(record.app)；准备更新当前组合记录"
            if let actual,let index=self.records[record.pid]?.firstIndex(where:{ $0.token == record.token }) {
                self.records[record.pid]?[index].frame=actual
            }
            if verified,let actual,
               self.guardState.permits(generation,key:key),self.environment.topology().key == key,
               self.profile?.revision == revision {
                var verified=record;verified.frame=actual
                self.queueStageSave(verified,target:target)
            }
            self.evidence[record.token]=nil;self.changed?()
        }
    }
    private func queueStageSave(_ record: AXRecord,target: Rect) {
        guard let display=topology.owner(of:record.frame),let filled=stageTarget(display,frame:record.frame),
              filled.close(to:target,tolerance:0.5),record.frame.close(to:target,tolerance:2),
              stagePermits(record),!storageFailed,profile?.locked != true,
              stageSaveQueue.count < 500 || stageSaveQueue[record.token] != nil else { return }
        stageSaveQueue[record.token]=record
        drainStageSaves()
    }
    private func drainStageSaves() {
        guard !busy,!storageFailed,!stageSaveQueue.isEmpty else { return }
        let queued=stageSaveQueue;stageSaveQueue=[:]
        guard guardState.permits(guardState.generation,key:topology.key),environment.trusted(),
              environment.topology().key == topology.key,!environment.pointerDown(),profile?.locked != true else { return }
        let matching=Matcher.assign(profile?.windows ?? [],allRecords.map(\.live),bindings:bindings)
        var captures:[(String,SavedWindow)]=[]
        for record in queued.values {
            guard environment.frontPID() == record.pid,stagePermits(record),
                  !database.preferences.excludedBundles.contains(record.identity.bundle),
                  allRecords.contains(where:{$0.token == record.token && $0.frame.close(to:record.frame,tolerance:2)}),
                  let display=topology.owner(of:record.frame),let target=stageTarget(display,frame:record.frame),
                  record.frame.close(to:target,tolerance:2) else { continue }
            let role=matching.resolved.first(where:{$0.value == record.token})?.key
            if role == nil,profile?.windows.contains(where:{matching.ambiguous.contains($0.id) && $0.identity.bundle == record.identity.bundle}) == true {
                issues["stage-save:\(record.token)"]="窗口匹配有歧义，未覆盖记录";continue
            }
            guard role != nil || !record.identity.title.isEmpty || !record.identity.identifier.isEmpty || !record.identity.document.isEmpty else { continue }
            captures.append((record.token,SavedWindow(id:role ?? UUID(),identity:record.identity,displayID:display.id,frame:record.frame,sourceVisible:display.visible)))
        }
        guard !captures.isEmpty else { return }
        var next=database
        do {
            guard let updated=try CaptureMerge.updated(profile,topology:topology,windows:captures.map(\.1)) else { return }
            try next.replace(updated,expectedRevision:profile?.revision)
        } catch { status="自动铺满记录未保存：\(error)";changed?();return }
        let generation=guardState.generation
        persist(next,message:"已保存自动铺满结果到当前显示器组合") { [weak self] success in
            guard let self,success,self.guardState.generation == generation else { return }
            for (token,window) in captures { self.bindings[window.id]=token;self.issues["stage-save:\(token)"]=nil }
        }
    }
    private func scheduleRemember() {
        guard saveTask == nil,!storageFailed else { return }
        let generation=guardState.generation,key=topology.key
        let task=DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.saveTask=nil
            guard self.guardState.permits(generation,key:key),self.environment.topology().key == key,
                  self.database.preferences.autoRemember,self.database.preferences.autoObserve,self.profile?.locked != true else { return }
            if self.busy { self.scheduleRemember(); return }
            let now=self.environment.now()
            let eligible=self.candidates.filter { token,window in
                self.learning.permits(token,now:now,pointerDown:self.environment.pointerDown(),
                    stable:self.allRecords.contains(where: { $0.token == token && $0.frame.close(to:window.frame,tolerance:0.5) }),
                    eligible:self.gestureOrigins[token].map { !$0.close(to:window.frame,tolerance:0.5) } == true)
            }
            self.save(Array(eligible),automatic:true)
        }
        saveTask=task; DispatchQueue.main.asyncAfter(deadline:.now()+2,execute:task)
    }
    private func save(_ captures: [(key:String,value:SavedWindow)], automatic: Bool) {
        let captures=captures.filter { entry in
            guard let owner=topology.owner(of:entry.value.frame) else { return false }
            return stageTarget(owner) == nil
        }
        guard !captures.isEmpty else { return }
        let generation=guardState.generation
        var next=database
        do {
            guard let p=try CaptureMerge.updated(profile,topology:topology,windows:captures.map(\.value)) else {
                status="布局未变化，无需写入"; changed?(); return
            }
            try next.replace(p,expectedRevision:profile?.revision)
        } catch { status="保存校验失败：\(error)"; changed?(); return }
        persist(next,message:automatic ? "已自动记忆手动调整的布局":"已保存基准；其他窗口请依次激活后再保存") { [weak self] success in
            guard let self,success,self.guardState.generation == generation else { return }
            for (token,window) in captures {
                self.bindings[window.id]=token
                self.attempted.insert("\(generation):\(token)")
                if self.candidates[token] == window { self.learning.discard(token);self.gestureOrigins[token]=nil }
            }
        }
    }
    private func persist(_ next: Database, message: String, completion: ((Bool)->Void)? = nil) {
        guard !busy,!storageFailed else { return }
        busy=true; changed?()
        io.async { [weak self] in
            guard let self else { return }
            do {
                try self.store.save(next)
                DispatchQueue.main.async { self.database=next; self.busy=false; self.status=message; completion?(true); self.drainStageSaves(); self.changed?() }
            } catch {
                DispatchQueue.main.async { self.busy=false; self.stageSaveQueue=[:]; self.status="写入失败，旧数据保留：\(error)"; completion?(false); self.changed?() }
            }
        }
    }
    func setPreferences(_ edit: (inout Preferences)->Void) {
        guard !busy,!storageFailed else { return }
        var next=database; edit(&next.preferences)
        if (database.preferences.stageFill && !next.preferences.stageFill) || (database.preferences.stagePortraitFill && !next.preferences.stagePortraitFill) { skipRestoreAfterModeOff=stageFocus }
        if (!database.preferences.stageFill && next.preferences.stageFill) || (!database.preferences.stagePortraitFill && next.preferences.stagePortraitFill) { skipRestoreAfterModeOff=nil }
        let wasPaused=guardState.paused
        guardState.paused=true
        invalidate("设置已改变，重新核对")
        let generation=guardState.generation
        persist(next,message:"设置已保存") { [weak self] success in
            guard let self else { return }
            if success,self.guardState.generation == generation { self.guardState.paused=wasPaused; self.displayChanged() }
        }
    }
    func stagePermits(_ record: AXRecord) -> Bool {
        record.stageTraits.permits(includeChildren:database.preferences.stageFillChildren) &&
        database.preferences.stageExcludedApplications[record.identity.bundle] == nil &&
        !stageSessionExclusions.contains(record.token) &&
        !database.preferences.stageExcludedKinds.contains { $0.matches(record.identity,traits:record.stageTraits) }
    }
    var stageMenuRecord: AXRecord? {
        guard environment.trusted(),!guardState.settling,!guardState.paused else { return nil }
        return allRecords.first { $0.focused && $0.usable && $0.pid == environment.frontPID() }
    }
    func stageRule(for record: AXRecord) -> StageWindowRule? {
        let rule=StageWindowRule(bundle:record.identity.bundle,identifier:record.identity.identifier,
                                 role:record.stageTraits.role,subrole:record.stageTraits.subrole)
        return rule.valid ? rule:nil
    }
    func toggleStageSessionExclusion(_ token: String) {
        guard !busy,allRecords.contains(where:{ $0.token == token }) else { return }
        if stageSessionExclusions.contains(token) { stageSessionExclusions.remove(token) }
        else {
            guard stageSessionExclusions.count < 500 else { status="临时排除已达500个上限";changed?();return }
            stageSessionExclusions.insert(token)
        }
        invalidate("窗口铺满排除已更新");displayChanged()
    }
    func setStageApplicationExclusion(bundle: String, name: String, excluded: Bool) {
        guard !bundle.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,bundle.utf8.count <= 1024,
              !name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,name.utf8.count <= 1024 else { return }
        guard !excluded || database.preferences.stageExcludedApplications[bundle] != nil || database.preferences.stageExcludedApplications.count < 200 else {
            status="铺满排除应用已达200个上限";changed?();return
        }
        setPreferences { $0.stageExcludedApplications[bundle]=excluded ? name:nil }
    }
    func toggleLock() {
        guard var p=profile,!busy else { return }
        let revision=p.revision; p.locked.toggle(); p.revision+=1; p.updatedAt=Date()
        var next=database
        do { try next.replace(p,expectedRevision:revision); persist(next,message:p.locked ? "基准已锁定":"基准已解锁") }
        catch { status="\(error)"; changed?() }
    }
    func renameProfile(_ name: String) {
        let name=name.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !name.isEmpty,name.count <= 100,var p=profile,!busy else { return }
        guard p.name != name else { return }
        let revision=p.revision;p.name=name;p.revision+=1;p.updatedAt=Date()
        var next=database
        do { try next.replace(p,expectedRevision:revision);persist(next,message:"布局已重命名") }
        catch { status="\(error)";changed?() }
    }
    func copyProfile(_ source: Profile, mapping: [String:String]) {
        guard !busy,!storageFailed,profile?.locked != true,
              guardState.permits(guardState.generation,key:topology.key),environment.topology().key == topology.key else { return }
        do {
            var copy=try ProfileMapping.copy(source,to:topology,mapping:mapping)
            if let current=profile { copy.id=current.id;copy.revision=current.revision+1 }
            var next=database;try next.replace(copy,expectedRevision:profile?.revision)
            let paused=guardState.paused
            guardState.paused=true;invalidate("正在复制映射布局")
            persist(next,message:"映射布局已保存，保持暂停；确认后从菜单继续") { [weak self] success in
                if !success { self?.guardState.paused=paused }
            }
        } catch { status="映射失败：\(error)";changed?() }
    }
    func cancelRestores() {
        guardState.paused=true;invalidate("已取消待恢复并暂停自动操作")
        guard !busy,!storageFailed else { return }
        var next=database;next.preferences.autoRestore=false
        persist(next,message:"已取消待恢复，自动恢复关闭，保持暂停")
    }
    func togglePause() {
        guardState.paused.toggle()
        if guardState.paused { invalidate("已暂停自动记录和恢复") }
        else { displayChanged() }
    }
    func restore() {
        if let record=allRecords.first(where:{ $0.focused && $0.usable && $0.pid == environment.frontPID() }),
           let owner=topology.owner(of:record.frame),stageTarget(owner) != nil {
            status="台前调度铺满模式优先；请关闭后恢复原布局";changed?();return
        }
        guard let p=profile,!busy,guardState.permits(guardState.generation,key:topology.key) else { status="当前无法恢复"; changed?(); return }
        attempted=[]; undo=[]; undoGeneration=guardState.generation
        let matching=Matcher.assign(p.windows,allRecords.map(\.live),bindings:bindings)
        let current=allRecords.filter { $0.focused && $0.usable && $0.pid == environment.frontPID() }
        for record in current { restoreRecord(record,profile:p,matching:matching,manual:true) }
        if current.isEmpty { status="请先激活需要恢复的窗口，再从菜单恢复；后台窗口不强行展开" }
        changed?()
    }
    private func restoreRecord(_ record: AXRecord, profile p: Profile, matching: MatchResult, manual: Bool) {
        guard let role=matching.resolved.first(where:{ $0.value == record.token })?.key,
              let saved=p.windows.first(where:{$0.id == role}),let target=saved.target(in:topology) else { return }
        let ticket="\(guardState.generation):\(record.token)"
        guard !attempted.contains(ticket),!moving.contains(record.token),attempted.count < 2000 else { return }
        attempted.insert(ticket)
        if record.frame.close(to:target) { return }
        let generation=guardState.generation,key=topology.key
        suppressUntil[record.token]=environment.now()+3
        learning.discard(record.token)
        undoGeneration=generation
        moving.insert(record.token)
        service.move(record,to:target,allowed:{ [weak self] in
            guard let self else { return false }
            return self.guardState.permits(generation,key:key) && self.environment.topology().key == key &&
                self.topology.owner(of:record.frame).map { self.stageTarget($0) == nil } == true &&
                self.profile?.revision == p.revision && !self.database.preferences.excludedBundles.contains(record.identity.bundle) &&
                self.environment.frontPID() == record.pid &&
                (manual || self.database.preferences.autoRestore)
        }) { [weak self] actual,error in
            guard let self else { return }
            self.moving.remove(record.token)
            guard self.guardState.generation == generation else { return }
            if let actual,!actual.close(to:record.frame,tolerance:0.5) {
                var moved=record; moved.frame=actual
                self.undo.append((moved,record.frame))
                self.undo=Array(self.undo.suffix(20))
            }
            self.status=error ?? "已核验恢复：\(record.app)"
            self.issues["restore:\(record.token)"]=error
            self.candidates[record.token]=nil; self.evidence[record.token]=nil
            self.changed?()
        }
    }
    func undoRestore() {
        guard canUndo else { return }
        let previous=undo; undo=[]
        let generation=guardState.generation,key=topology.key
        for (record,frame) in previous {
            suppressUntil[record.token]=environment.now()+3
            service.move(record,to:frame,allowed:{ [weak self] in
                guard let self else { return false }
                return self.guardState.permits(generation,key:key) && self.environment.topology().key == key &&
                    self.environment.frontPID() == record.pid
            }) { [weak self] _,error in self?.status=error ?? "撤销完成"; self?.changed?() }
        }
    }
    func useHistory(_ old: Profile) {
        guard let current=profile,current.id == old.id,!current.locked,!busy else { return }
        var replacement=old; replacement.revision=current.revision+1; replacement.updatedAt=Date()
        var next=database
        do { try next.replace(replacement,expectedRevision:current.revision); persist(next,message:"历史基准已恢复；未移动窗口") }
        catch { status="\(error)"; changed?() }
    }
    func bindFocused(to role: UUID) {
        guard var p=profile,!p.locked,!busy,
              let record=allRecords.first(where:{$0.focused && $0.usable && $0.pid == environment.frontPID()}),
              let index=p.windows.firstIndex(where:{$0.id == role}),p.windows[index].identity.bundle == record.identity.bundle else {
            status="请激活同一应用的真实窗口；基准不可锁定"; changed?(); return
        }
        bindings[role]=record.token
        let revision=p.revision; p.windows[index].identity=record.identity; p.revision+=1; p.updatedAt=Date()
        var next=database
        do { try next.replace(p,expectedRevision:revision); persist(next,message:"已绑定窗口角色；重启后仍需唯一身份线索") }
        catch { status="\(error)"; changed?() }
    }
    func importBackup(_ url: URL) {
        guard !busy,!storageFailed else { return }
        do {
            var db=try store.decode(url); db.preferences.autoRestore=false; db.preferences.autoRemember=false;db.preferences.stageFill=false;db.preferences.stagePortraitFill=false
            guardState.paused=true; invalidate("导入备份")
            persist(db,message:"备份已导入，自动恢复请重新确认") { [weak self] _ in self?.changed?() }
        }
        catch { status="导入失败：\(error)"; changed?() }
    }
    func previewScene(profileID: UUID?, mode: PreviewMode) -> PreviewScene {
        let selected=profileID.flatMap { id in database.profiles.first { $0.id == id } } ?? profile
        let observations: [PreviewObservation] = guardState.settling || !environment.trusted() ? [] : allRecords.compactMap { record in
            guard let (key,time)=recordContexts[record.pid],key == topology.key else { return nil }
            return PreviewObservation(token:record.token,name:record.app,identity:record.identity,frame:record.frame,
                observedAt:time,usable:record.usable)
        }
        return PreviewScene.make(currentTopology:topology,observations:observations,profile:selected,mode:mode,bindings:bindings)
    }
    func report() -> String {
        let matching=Matcher.assign(profile?.windows ?? [],allRecords.map(\.live),bindings:bindings)
        let screenLines=topology.displays.map { "\($0.name) [UUID \($0.id.prefix(8))…]: \(Int($0.frame.width))×\(Int($0.frame.height)) @ (\(Int($0.frame.x)),\(Int($0.frame.y)))；铺满留白 \(Int(database.preferences.stageInsets[StageFill.insetKey(topology:topology,display:$0)] ?? StageFill.defaultInset)) pt\($0.frame.width > $0.frame.height ? "":($0.frame.height > $0.frame.width ? "（竖屏横向撑满由独立开关控制）":"（正方形，不铺满）"))" }
        let windowLines=allRecords.sorted { $0.app < $1.app }.map { r in
            let owner=topology.owner(of:r.frame)?.name ?? "归属待确认"
            return "\(r.app) | \(owner) | (\(Int(r.frame.x)),\(Int(r.frame.y))) \(Int(r.frame.width))×\(Int(r.frame.height)) | \(candidates[r.token] != nil ? "已核对候选":r.usable && r.focused ? "核对中":"等待激活")"
        }
        var lines: [String] = ["Window Layout Memory \(AppVersion.label)",status,
                 "辅助功能：\(AXIsProcessTrusted() ? "已授权":"未授权")；显示器：\(topology.displays.count)",
                 "布局：\(database.profiles.count)；当前基准：\(profile?.windows.count ?? 0)；候选：\(candidates.count)",
                 "当前组合：\(profile?.name ?? "未建立基准")；各组合包含独立的内屏和外屏窗口记录",
                 "匹配：\(matching.resolved.count)；歧义：\(matching.ambiguous.count)；待出现：\(matching.missing.count)",
                 "拖动自动记忆：\(database.preferences.autoRemember ? "开启":"关闭")；自动恢复：\(database.preferences.autoRestore ? "开启":"关闭")。不展开后台组。",
                 "台前调度横屏铺满：\(database.preferences.stageFill ? "开启":"关闭")；系统状态：\(environment.stageManagerEnabled().map { $0 ? "开启":"关闭" } ?? "未知（不铺满）")；默认留白100 pt，拖左边缘调整。",
                 "竖屏横向撑满：\(database.preferences.stagePortraitFill ? "开启":"关闭")；保留纵向位置和高度，越界时夹回工作区。",
                 "子窗口铺满：\(database.preferences.stageFillChildren ? "开启":"关闭")；排除应用：\(database.preferences.stageExcludedApplications.count)；永久窗口规则：\(database.preferences.stageExcludedKinds.count)；临时窗口排除：\(stageSessionExclusions.count)。类型未知、对话框和浮动面板不铺满。",
                 "此版本尚未通过完整硬件与性能验收。", "\n显示器"]
        lines += screenLines
        lines.append("\n窗口（不含标题与路径）")
        lines += windowLines
        lines.append("\n读取/恢复问题")
        lines += issues.sorted { $0.key < $1.key }.map { "\($0.key): \($0.value)" }
        return lines.joined(separator:"\n")
    }
}
