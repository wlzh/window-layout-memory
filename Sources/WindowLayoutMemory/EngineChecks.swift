#if DEBUG
import AppKit
import ApplicationServices
import LayoutCore

// Deterministic adapter double: never enumerates, moves, or saves real user windows.
private final class FixtureService: WindowService {
    var onEvent: ((pid_t,String,AXUIElement)->Void)?
    var record=AXRecord(token:"424242:1",app:"Synthetic",pid:424242,
        element:AXUIElementCreateApplication(424242),identity:WindowIdentity(bundle:"test.fixture",title:"Synthetic"),
        frame:Rect(20,40,400,300),focused:true,usable:true)
    var scans=0, moves=0
    var holdFill=false, heldFill: (() -> Void)?
    var omitWindow=false
    var hold=false
    var held: [(ScanResult)->Void]=[]
    func detach(_ pid: pid_t) {}
    func scan(pid: pid_t,bundle: String,name: String,front: Bool,hidden: Bool,allowed: @escaping ()->Bool,completion: @escaping (ScanResult)->Void) {
        guard allowed() else { completion(ScanResult(pid:pid,records:[],error:"cancelled"));return }
        scans+=1
        if hold { held.append(completion) }
        else { completion(ScanResult(pid:pid,records:omitWindow ? []:[record],error:nil)) }
    }
    func move(_ record: AXRecord,to target: Rect,allowed: @escaping ()->Bool,completion: @escaping (Rect?,String?)->Void) {
        guard allowed() else { completion(nil,"cancelled");return }
        moves+=1;self.record.frame=target;completion(target,nil)
    }
    func emit() { onEvent?(record.pid,kAXWindowMovedNotification,record.element) }
    func fill(_ record: AXRecord,to target: Rect,allowed: @escaping ()->Bool,completion: @escaping (Rect?,String?)->Void) {
        if holdFill { heldFill={ [weak self] in self?.move(record,to:target,allowed:allowed,completion:completion) } }
        else { move(record,to:target,allowed:allowed,completion:completion) }
    }
}

func runEngineChecks() -> Int32 {
    var passed=0,failed=0
    func check(_ name:String,_ condition: @autoclosure ()->Bool) {
        if condition() { passed+=1;print("PASS ENGINE \(name)") }
        else { failed+=1;print("FAIL ENGINE \(name)") }
    }
    func pump(_ seconds: TimeInterval) { RunLoop.main.run(until:Date(timeIntervalSinceNow:seconds)) }
    func awaitCondition(_ condition: ()->Bool) {
        let deadline=Date(timeIntervalSinceNow:8)
        while !condition(),Date() < deadline { pump(0.05) }
    }
    let root=FileManager.default.temporaryDirectory.appendingPathComponent("wlm-engine-tests-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at:root) }
    let display=Display(id:"fixture-a",name:"Synthetic A",frame:Rect(0,0,1200,900),primary:true)
    var topology=Topology([display]),pointer=false,trusted=true
    var env=EngineEnvironment();env.observeSystem=false
    env.topology={ topology };env.pointerDown={ pointer };env.trusted={ trusted };env.frontPID={ 424242 }
    env.applications={ [RunningAppSnapshot(pid:424242,bundle:"test.fixture",name:"Synthetic",hidden:false)] }
    let service=FixtureService(),store=LayoutStore(directory:root.appendingPathComponent("learning"))
    var pointerPoint=CGPoint(x:100,y:45)
    env.pointerLocation={ pointerPoint }
    let engine=Engine(service:service,store:store,environment:env)
    pump(3.3)
    check("stable foreground becomes a candidate",engine.candidates.count == 1)
    let previewScans=service.scans
    check("preview reads cached geometry without AX scans",engine.previewScene(profileID:nil,mode:.current).rows.count == 1 && service.scans == previewScans)
    check("activation alone never persists",engine.database.profiles.isEmpty)
    check("default never moves user windows",service.moves == 0)
    let beforeStorm=service.scans
    for _ in 0..<1000 { service.emit() }
    pump(0.8)
    check("1000 event burst coalesces into one scan",service.scans-beforeStorm == 1)
    engine.saveCandidates();pump(0.2)
    check("manual save persists baseline",(try? store.load().profiles.count) == 1)
    let revision=engine.profile?.revision
    engine.saveCandidates();pump(0.1)
    check("no-op save does not increase revision",engine.profile?.revision == revision)
    pointer=true;engine.pointerEvent(down:true);service.record.frame.x=250;service.emit();pump(0.8)
    check("drag in progress is not persisted",engine.profile?.windows.first?.frame.x == 20)
    pointerPoint.x=330;pointer=false;engine.pointerEvent(down:false)
    awaitCondition { engine.profile?.windows.first?.frame.x == 250 && !engine.busy }
    check("stable released gesture automatically persists",engine.profile?.windows.first?.frame.x == 250)
    check("automatic learning updates rather than duplicates role",engine.profile?.windows.count == 1)
    check("disk matches learned geometry",(try? store.load().profiles.first?.windows.first?.frame.x) == 250)
    engine.toggleLock();pump(0.2)
    pointerPoint=CGPoint(x:300,y:45)
    pointer=true;engine.pointerEvent(down:true);service.record.frame.x=400;service.emit();pump(0.8)
    pointerPoint.x=450;pointer=false;engine.pointerEvent(down:false);pump(3.5)
    check("locked baseline resists automatic capture",engine.profile?.windows.first?.frame.x == 250)
    check("locked baseline still permits candidates",engine.candidates.values.first?.frame.x == 400)
    engine.togglePause();let scanCount=service.scans;service.emit();pump(0.8)
    check("pause prevents scans",service.scans == scanCount)
    check("pause discards unconfirmed candidates",engine.candidates.isEmpty)
    engine.togglePause();pump(2.5)
    service.hold=true;service.emit();pump(0.8)
    check("fixture exercises in-flight scan",!service.held.isEmpty)
    topology=Topology([display,Display(id:"fixture-b",name:"Synthetic B",frame:Rect(-1000,0,1000,900))])
    engine.displayChanged()
    check("preview excludes records while topology is settling",engine.previewScene(profileID:nil,mode:.current).rows.isEmpty)
    for callback in service.held { callback(ScanResult(pid:424242,records:[service.record],error:nil)) }
    service.held=[];service.hold=false
    check("stale scan cannot publish after display invalidation",engine.candidates.isEmpty)
    pump(2.5)
    check("unknown topology does not borrow previous baseline",engine.profile == nil)
    check("original topology baseline remains intact",engine.database.profiles.first?.windows.first?.frame.x == 250)
    engine.copyProfile(engine.database.profiles[0],mapping:["fixture-a":"fixture-a"]);pump(0.2)
    check("explicit mapping creates independent current profile",engine.database.profiles.count == 2 && engine.profile?.windows.count == 1)
    check("mapping pauses operations without moving windows",engine.guardState.paused && service.moves == 0)
    engine.togglePause();pump(2.5)
    trusted=false;engine.refresh();let deniedScans=service.scans;service.emit();pump(0.8)
    check("permission denial prevents new scans",service.scans == deniedScans && !engine.guardState.trusted)
    check("preview hides observations after permission denial",engine.previewScene(profileID:nil,mode:.current).rows.isEmpty)
    check("saved preview remains accessible without AX permission",engine.previewScene(profileID:nil,mode:.saved).rows.count == 1)
    engine.togglePause()

    do {
        topology=Topology([display]);trusted=true;pointer=false
        let delayed=FixtureService(),delayedStore=LayoutStore(directory:root.appendingPathComponent("delayed"))
        let learner=Engine(service:delayed,store:delayedStore,environment:env)
        pump(3.3)
        pointerPoint=CGPoint(x:100,y:45);pointer=true;learner.pointerEvent(down:true)
        delayed.record.frame=Rect(320,140,480,360)
        pointerPoint=CGPoint(x:400,y:145);pointer=false;learner.pointerEvent(down:false)
        delayed.emit()
        awaitCondition { learner.profile?.windows.first?.frame == delayed.record.frame && !learner.busy }
        check("AX notification after release creates independent first profile",learner.profile?.windows.first?.frame == delayed.record.frame)
        check("released gesture is persisted on disk",(try? delayedStore.load().profiles.first?.windows.first?.frame) == delayed.record.frame)
        let saved=learner.profile?.windows.first?.frame,rev=learner.profile?.revision
        pointerPoint=CGPoint(x:400,y:145);pointer=true;learner.pointerEvent(down:true)
        pointer=false;learner.pointerEvent(down:false);delayed.record.frame.x=350;delayed.emit();pump(3.5)
        check("handle click without drag does not learn later system geometry",learner.profile?.windows.first?.frame == saved)
        pointerPoint=CGPoint(x:500,y:300);pointer=true;learner.pointerEvent(down:true)
        pointerPoint.x=550;pointer=false;learner.pointerEvent(down:false)
        delayed.record.frame.x=360;delayed.emit();pump(3.5)
        check("content drag does not authorize layout changes",learner.profile?.revision == rev)
        pointerPoint=CGPoint(x:400,y:145);pointer=true;learner.pointerEvent(down:true)
        pointerPoint.x=450;pointer=false;learner.pointerEvent(down:false);pump(3.5)
        check("gesture without geometry change does not save",learner.profile?.revision == rev)
        delayed.record.frame.x=370;delayed.emit();pump(3.5)
        check("unchanged gesture cannot authorize a later system change",learner.profile?.revision == rev)
        pointerPoint=CGPoint(x:400,y:145);pointer=true;learner.pointerEvent(down:true)
        trusted=false;pointerPoint.x=450;pointer=false;learner.pointerEvent(down:false);trusted=true
        delayed.record.frame.x=375;delayed.emit();pump(3.5)
        check("permission loss invalidates pointer evidence",learner.profile?.revision == rev)
        pointerPoint=CGPoint(x:400,y:145);pointer=true;learner.pointerEvent(down:true)
        learner.togglePause();pointerPoint.x=460;pointer=false;learner.pointerEvent(down:false)
        learner.togglePause();delayed.record.frame.x=380;delayed.emit();pump(3.5)
        check("pause invalidates incomplete gesture",learner.profile?.revision == rev)
        pointerPoint=CGPoint(x:400,y:145);pointer=true;learner.pointerEvent(down:true)
        topology=Topology([display,Display(id:"fixture-c",name:"Synthetic C",frame:Rect(1200,0,800,600))])
        learner.displayChanged();pointerPoint.x=450;pointer=false;learner.pointerEvent(down:false)
        delayed.record.frame.x=390;pump(3.5)
        check("display change invalidates pointer evidence without creating profile",learner.profile == nil && learner.database.profiles.count == 1)
        pointerPoint=CGPoint(x:400,y:145);pointer=true;learner.pointerEvent(down:true)
        delayed.record.frame.width=550
        pointerPoint.x=480;pointer=false;learner.pointerEvent(down:false)
        awaitCondition { learner.profile?.windows.first?.frame == delayed.record.frame && !learner.busy }
        check("mouse release triggers capture even without AX geometry notification",learner.profile?.windows.first?.frame == delayed.record.frame)
        learner.togglePause()
    }

    do {
        topology=Topology([display]);trusted=true
        let restoreStore=LayoutStore(directory:root.appendingPathComponent("restore"))
        let saved=SavedWindow(identity:service.record.identity,displayID:display.id,frame:Rect(30,40,500,300),sourceVisible:display.visible)
        var db=Database();db.profiles=[Profile(name:"Synthetic",topology:topology,windows:[saved])];db.preferences.autoRestore=true
        try restoreStore.save(db)
        let second=FixtureService(),restorer=Engine(service:second,store:restoreStore,environment:env)
        pump(2.5)
        check("known foreground is restored once",second.moves == 1 && second.record.frame == saved.frame)
        restorer.renameProfile("Renamed");pump(0.2)
        second.record.frame.x=600;second.emit();pump(2.5)
        check("revision changes do not rearm automatic restore",second.moves == 1)
        check("system change without gesture does not overwrite",restorer.profile?.windows.first?.frame == saved.frame)
        restorer.restore();pump(0.2)
        check("explicit restore can rearm movement",second.moves == 2)
        restorer.undoRestore();pump(0.2)
        check("undo restores pre-move geometry",second.record.frame.x == 600)
        restorer.setPreferences { $0.excludedBundles=["test.fixture"] };pump(2.0)
        let before=second.scans;second.emit();pump(0.8)
        check("excluded application is not scanned",second.scans == before)
        restorer.setPreferences { $0.autoRestore=true }
        restorer.cancelRestores();pump(0.3)
        check("cancellation during settings IO cannot be resumed by stale completion",restorer.guardState.paused)
    } catch { failed+=1;print("FAIL ENGINE setup: \(error)") }
    do {
        topology=Topology([display]);trusted=true;pointer=false
        var enabled: Bool?=true
        var stageEnv=env;stageEnv.stageManagerEnabled={ enabled };stageEnv.stageDisplay={ $0 }
        let stageStore=LayoutStore(directory:root.appendingPathComponent("stage"))
        let window=SavedWindow(identity:service.record.identity,displayID:display.id,frame:Rect(30,40,500,300),sourceVisible:display.visible)
        var db=Database();db.profiles=[Profile(name:"Original",topology:topology,windows:[window])]
        db.preferences.stageFill=true;db.preferences.autoRestore=true
        db.preferences.stageInsets[StageFill.insetKey(topology:topology,display:display)]=200
        try stageStore.save(db)
        let fake=FixtureService(),stage=Engine(service:fake,store:stageStore,environment:stageEnv)
        awaitCondition { fake.moves == 1 }
        check("stage fill takes priority over saved baseline",fake.record.frame == Rect(200,0,1000,900))
        check("stage fill never creates ordinary candidates",stage.candidates.isEmpty)
        check("stage fill preserves stored baseline",(try? stageStore.load().profiles) == db.profiles)
        let firstMoves=fake.moves
        fake.record.frame=Rect(230,50,700,600)
        fake.onEvent?(fake.record.pid,kAXApplicationActivatedNotification,fake.record.element)
        pump(3.3)
        check("activation during post-move protection is eventually reapplied",fake.moves == firstMoves+1 && fake.record.frame == Rect(200,0,1000,900))
        let protectedMoves=fake.moves
        fake.emit();pump(2.5)
        check("protected activation retry stops after one successful fill",fake.moves == protectedMoves)
        pump(2.2)
        pointerPoint=CGPoint(x:200,y:300);pointer=true;stage.pointerEvent(down:true)
        fake.record.frame=Rect(150,0,1050,900);pointerPoint.x=150;pointer=false;stage.pointerEvent(down:false)
        let insetKey=StageFill.insetKey(topology:topology,display:display)
        awaitCondition { stage.database.preferences.stageInsets[insetKey] == 150 && !stage.busy }
        check("left edge resize persists shared per-display inset",stage.database.preferences.stageInsets[insetKey] == 150)
        check("inset save does not modify baseline or history",stage.database.profiles == db.profiles && stage.database.history.isEmpty)
        fake.record.frame=Rect(350,40,400,300)
        fake.onEvent?(fake.record.pid,kAXApplicationActivatedNotification,fake.record.element)
        awaitCondition { fake.record.frame == Rect(150,0,1050,900) }
        check("reactivation reapplies learned inset",fake.record.frame == Rect(150,0,1050,900))
        pump(2.2)
        pointerPoint=CGPoint(x:300,y:5);pointer=true;stage.pointerEvent(down:true)
        fake.record.frame.x=180;pointerPoint.x=330;pointer=false;stage.pointerEvent(down:false)
        pump(3.5)
        check("titlebar drag stays free until next activation",fake.record.frame.x == 180)
        check("free drag does not change inset or baseline",stage.database.preferences.stageInsets[insetKey] == 150 && stage.database.profiles == db.profiles)
        let count=fake.moves
        for _ in 0..<1000 { fake.emit() };pump(0.8)
        check("stage geometry notifications never form a move loop",fake.moves == count)
        stage.setPreferences { $0.stageFill=false };pump(3.5)
        check("disabling stage fill does not immediately restore or resize",fake.moves == count && fake.record.frame.x == 180)
        stage.setPreferences { $0.stageFill=true }
        awaitCondition { fake.record.frame == Rect(150,0,1050,900) }
        check("reenabling stage fill uses persisted inset",fake.record.frame == Rect(150,0,1050,900))
        let activeCount=fake.moves
        stage.togglePause();fake.onEvent?(fake.record.pid,kAXApplicationActivatedNotification,fake.record.element);pump(0.8)
        check("pause blocks stage fill",fake.moves == activeCount)
        stage.togglePause();enabled=false;pump(3.3)
        let offCount=fake.moves
        fake.record.frame.x=210;fake.emit();pump(2)
        check("system Stage Manager off disables fill",fake.moves == offCount)
        enabled=nil;fake.record.frame.x=240;fake.emit();pump(2)
        check("unknown Stage Manager state disables fill",fake.moves == offCount)
        enabled=true
        topology=Topology([Display(id:"portrait",name:"Portrait",frame:Rect(0,0,800,1200),primary:true)])
        stage.displayChanged();pump(3.3)
        check("portrait display is never stage filled",fake.moves == offCount)
        check("new combination never borrows inset",stage.database.preferences.stageInsets.count == 1)
        stage.togglePause()
    } catch { failed+=1;print("FAIL ENGINE stage setup: \(error)") }
    do {
        let external=Display(id:"external",name:"External",frame:Rect(-1600,0,1600,1000),primary:false)
        let portrait=Display(id:"portrait",name:"Portrait",frame:Rect(-800,0,800,1200),primary:false)
        let pair=Topology([display,external]),verticalPair=Topology([display,portrait])
        let cases:[(String,Topology,Topology,Display,Bool,Bool,Rect)] = [
            ("reconnect restores saved external display before filling",pair,pair,external,true,false,Rect(-1500,0,1500,1000)),
            ("saved portrait restores original frame instead of filling internal",verticalPair,verticalPair,portrait,true,false,Rect(-700,40,500,600)),
            ("disabled auto restore fills current screen without crossing",pair,pair,external,false,false,Rect(100,0,1100,900)),
            ("unknown combination never borrows saved display",Topology([display]),pair,external,true,false,Rect(100,0,1100,900)),
            ("ambiguous saved roles never choose a destination screen",pair,pair,external,true,true,Rect(100,0,1100,900))
        ]
        for (index,item) in cases.enumerated() {
            let (name,current,savedTopology,destination,autoRestore,ambiguous,expected)=item
            topology=current;trusted=true;pointer=false
            let fake=FixtureService()
            let saved=SavedWindow(identity:fake.record.identity,displayID:destination.id,
                frame:destination.id == "portrait" ? Rect(-700,40,500,600):Rect(-1500,40,900,600),sourceVisible:destination.visible)
            var db=Database();db.preferences.stageFill=true;db.preferences.autoRestore=autoRestore
            var windows=[saved]
            if ambiguous { windows.append(SavedWindow(identity:saved.identity,displayID:display.id,frame:Rect(30,40,500,300),sourceVisible:display.visible)) }
            db.profiles=[Profile(name:"Saved setup",topology:savedTopology,windows:windows)]
            let store=LayoutStore(directory:root.appendingPathComponent("routing-\(index)"));try store.save(db)
            var routedEnv=env;routedEnv.stageManagerEnabled={ true };routedEnv.stageDisplay={ $0 }
            let engine=Engine(service:fake,store:store,environment:routedEnv)
            awaitCondition { fake.moves > 0 }
            check(name,fake.record.frame == expected && fake.moves == 1)
            check("routing \(index) preserves profiles and history",(try? store.load()) == db)
            if index == 0 {
                pump(2.2)
                pointerPoint=CGPoint(x:-1300,y:5);pointer=true;engine.pointerEvent(down:true)
                fake.record.frame=Rect(100,50,900,700)
                pointerPoint=CGPoint(x:400,y:55);pointer=false;engine.pointerEvent(down:false)
                pump(3.3)
                check("manual cross-screen drag is not immediately snapped back",fake.record.frame == Rect(100,50,900,700))
                fake.onEvent?(fake.record.pid,kAXApplicationActivatedNotification,fake.record.element)
                awaitCondition { fake.record.frame == expected }
                check("next activation returns temporary move to saved display",fake.record.frame == expected && (try? store.load()) == db)
            }
            engine.togglePause()
        }
        topology=verticalPair
        let fake=FixtureService();fake.record.frame=Rect(-700,100,500,700)
        let store=LayoutStore(directory:root.appendingPathComponent("portrait-to-landscape"))
        var db=Database();db.preferences.stageFill=true;db.preferences.autoRestore=true
        db.profiles=[Profile(name:"Return",topology:verticalPair,windows:[SavedWindow(identity:fake.record.identity,displayID:display.id,frame:Rect(30,40,500,300),sourceVisible:display.visible)])]
        try store.save(db)
        var routedEnv=env;routedEnv.stageManagerEnabled={ true };routedEnv.stageDisplay={ $0 }
        let routed=Engine(service:fake,store:store,environment:routedEnv)
        awaitCondition { fake.moves > 0 }
        check("window stranded on portrait returns to saved landscape",fake.record.frame == Rect(100,0,1100,900))
        routed.togglePause()
    } catch { failed+=1;print("FAIL ENGINE destination routing: \(error)") }
    do {
        topology=Topology([display]);trusted=true;pointer=false
        let fake=FixtureService(),store=LayoutStore(directory:root.appendingPathComponent("child-policy"))
        fake.record.stageTraits=StageWindowTraits(parentRole:"AXWindow")
        fake.record.identity.identifier="viewer"
        let original=fake.record.frame
        var db=Database();db.preferences.stageFill=true;db.preferences.autoRestore=true
        db.profiles=[Profile(name:"Do not overwrite",topology:topology,windows:[SavedWindow(identity:fake.record.identity,displayID:display.id,frame:Rect(40,50,600,400),sourceVisible:display.visible)])]
        try store.save(db)
        var enabled=true,childEnv=env
        childEnv.stageManagerEnabled={ enabled };childEnv.stageDisplay={ $0 }
        let child=Engine(service:fake,store:store,environment:childEnv)
        pump(2.2)
        check("child default blocks fill and automatic restore fallback",fake.moves == 0 && fake.record.frame == original)
        check("child default does not learn candidate or mutate baseline",child.candidates.isEmpty && child.database.profiles == db.profiles)
        let delegate=AppDelegate();delegate.engine=child
        let menu=NSMenu();menu.autoenablesItems=false;delegate.menuWillOpen(menu)
        let option=menu.items.first { $0.title == "同时铺满子窗口" }
        check("child menu is indented unchecked and enabled under master",option?.state == .off && option?.indentationLevel == 1 && option?.isEnabled == true)
        check("redundant 100 point menu removed",!menu.items.contains { $0.title.contains("留白设为100") })
        let exclusions=menu.items.first { $0.title == "铺满排除" }?.submenu
        check("identified window offers persistent and session exclusion",exclusions?.items.contains { $0.title == "排除此标识的窗口…" } == true && exclusions?.items.contains { $0.title == "当前窗口不铺满（本次运行）" } == true)
        child.setPreferences { $0.stageFillChildren=true };awaitCondition { fake.moves > 0 }
        check("opt in allows standard child fill",fake.record.frame == Rect(100,0,1100,900))
        let rule=child.stageRule(for:fake.record)!
        child.setPreferences { $0.stageExcludedKinds=[rule] };pump(2.2)
        let before=fake.moves
        fake.record.frame=original;fake.emit();pump(2.2)
        check("explicit exclusion overrides child opt in without restore fallback",fake.moves == before && fake.record.frame == original)
        let reloaded=try store.load()
        check("persistent exclusions survive restart read without profile changes",reloaded.preferences.stageExcludedKinds == [rule] && child.database.profiles == db.profiles)
        child.setPreferences { $0.stageExcludedKinds=[] };awaitCondition { fake.moves > before }
        check("removing persistent rule permits fill again",fake.moves > before)
        child.toggleStageSessionExclusion(fake.record.token);pump(2.2)
        let sessionMoves=fake.moves;fake.record.frame=original;fake.emit();pump(2.2)
        check("session exclusion blocks current window",fake.moves == sessionMoves && child.stageSessionExclusions.contains(fake.record.token))
        check("session exclusion never writes stored type rules",child.database.preferences.stageExcludedKinds.isEmpty)
        child.toggleStageSessionExclusion(fake.record.token);awaitCondition { fake.moves > sessionMoves }
        check("removing session exclusion permits fill",fake.moves > sessionMoves)
        fake.record.identity.identifier=""
        check("missing identifier never creates broad persistent rule",child.stageRule(for:fake.record) == nil)
        fake.emit();pump(2.2);delegate.menuWillOpen(menu)
        check("menu offers only session fallback without identifier",menu.items.first { $0.title == "铺满排除" }?.submenu?.items.contains { $0.title == "无可靠标识，仅可临时排除当前窗口" } == true)
        child.toggleStageSessionExclusion(fake.record.token);pump(2.2)
        fake.omitWindow=true;fake.emit();pump(0.6)
        check("complete scan clears closed window session exclusion",child.stageSessionExclusions.isEmpty)
        fake.omitWindow=false;fake.record.identity.identifier="viewer"
        fake.record.stageTraits=StageWindowTraits();fake.record.frame=original;fake.holdFill=true
        child.setPreferences { $0.stageFillChildren=false };awaitCondition { fake.heldFill != nil }
        check("independent main window allowed with child option off",fake.heldFill != nil)
        let pendingMoves=fake.moves
        child.toggleStageSessionExclusion(fake.record.token)
        fake.heldFill?();fake.heldFill=nil;fake.holdFill=false;pump(2.2)
        check("exclusion cancels an in flight fill before mutation",fake.moves == pendingMoves)
        child.toggleStageSessionExclusion(fake.record.token);pump(2.2)
        child.setPreferences { $0.stageFill=false };pump(2.2)
        delegate.menuWillOpen(menu)
        check("child option disabled while master is off",menu.items.first { $0.title == "同时铺满子窗口" }?.isEnabled == false)
        enabled=false;fake.record.frame=original
        child.setPreferences { $0.stageFill=true }
        awaitCondition { fake.record.frame == db.profiles[0].windows[0].frame }
        check("system stage off performs ordinary restore despite master on",fake.record.frame == db.profiles[0].windows[0].frame)
        child.togglePause()
    } catch { failed+=1;print("FAIL ENGINE child policy: \(error)") }
    do {
        topology=Topology([display]);trusted=true;pointer=false
        var appEnv=env;appEnv.stageManagerEnabled={ true };appEnv.stageDisplay={ $0 }
        let appStore=LayoutStore(directory:root.appendingPathComponent("app-exclusion"))
        var db=Database();db.preferences.stageFill=true
        db.preferences.stageExcludedApplications=["test.fixture":"Synthetic"]
        try appStore.save(db)
        let fake=FixtureService(),excluded=Engine(service:fake,store:appStore,environment:appEnv)
        pump(2.2)
        check("saved app exclusion blocks fill after engine restart",fake.moves == 0 && fake.scans > 0)
        check("app exclusion keeps ordinary app observation preferences intact",excluded.database.preferences.excludedBundles.isEmpty && excluded.candidates.isEmpty)
        let delegate=AppDelegate();delegate.engine=excluded
        let menu=NSMenu();menu.autoenablesItems=false;delegate.menuWillOpen(menu)
        let submenu=menu.items.first { $0.title == "横屏铺满排除应用" }?.submenu
        check("app menu includes persisted stopped app as checked",submenu?.items.contains { $0.title.contains("test.fixture") && $0.state == .on } == true)
        check("app menu includes file picker entry",submenu?.items.contains { $0.title == "从文件选择应用…" } == true)
        excluded.setStageApplicationExclusion(bundle:"test.fixture",name:"Synthetic",excluded:false)
        awaitCondition { fake.moves > 0 }
        check("removing app exclusion re enables fill",fake.record.frame == Rect(100,0,1100,900))
        excluded.setStageApplicationExclusion(bundle:"test.fixture",name:"Synthetic",excluded:true);pump(2.2)
        let loaded=try appStore.load()
        check("selected app persists by bundle not path",loaded.preferences.stageExcludedApplications == ["test.fixture":"Synthetic"])
        var other=fake.record;other.identity.bundle="other.app"
        check("app exclusion does not affect other bundle",excluded.stagePermits(other))
        excluded.setStageApplicationExclusion(bundle:"",name:"Bad",excluded:true)
        check("invalid app identity is rejected",excluded.database.preferences.stageExcludedApplications.count == 1)
        let appURL=root.appendingPathComponent("Fixture.app"),contents=appURL.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at:contents,withIntermediateDirectories:true)
        let info:[String:String]=["CFBundleIdentifier":"test.file.app","CFBundleName":"File App","CFBundlePackageType":"APPL"]
        try PropertyListSerialization.data(fromPropertyList:info,format:.xml,options:0).write(to:contents.appendingPathComponent("Info.plist"))
        let selected=AppDelegate.stageApplication(at:appURL)
        check("file app selection extracts stable bundle identity",selected?.bundle == "test.file.app" && selected?.name == "File App")
        check("file selection rejects missing and non app bundles",AppDelegate.stageApplication(at:root) == nil && AppDelegate.stageApplication(at:root.appendingPathComponent("Missing.app")) == nil)
        let picker=AppDelegate.stageApplicationPanel()
        check("native file picker restricts selection to application bundles",picker.allowedContentTypes.first?.identifier == "com.apple.application-bundle" && picker.canChooseFiles && !picker.canChooseDirectories && !picker.allowsMultipleSelection && !picker.treatsFilePackagesAsDirectories)
        picker.close();excluded.togglePause()
    } catch { failed+=1;print("FAIL ENGINE application exclusions: \(error)") }
    print("ENGINE_TESTS passed=\(passed) failed=\(failed); injected adapter, not physical AX or Stage Manager validation")
    return failed == 0 ? 0:1
}
#endif
