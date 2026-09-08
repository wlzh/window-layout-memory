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
    var hold=false
    var held: [(ScanResult)->Void]=[]
    func detach(_ pid: pid_t) {}
    func scan(pid: pid_t,bundle: String,name: String,front: Bool,hidden: Bool,allowed: @escaping ()->Bool,completion: @escaping (ScanResult)->Void) {
        guard allowed() else { completion(ScanResult(pid:pid,records:[],error:"cancelled"));return }
        scans+=1
        if hold { held.append(completion) }
        else { completion(ScanResult(pid:pid,records:[record],error:nil)) }
    }
    func move(_ record: AXRecord,to target: Rect,allowed: @escaping ()->Bool,completion: @escaping (Rect?,String?)->Void) {
        guard allowed() else { completion(nil,"cancelled");return }
        moves+=1;self.record.frame=target;completion(target,nil)
    }
    func emit() { onEvent?(record.pid,kAXWindowMovedNotification,record.element) }
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
        try stageStore.save(db)
        let fake=FixtureService(),stage=Engine(service:fake,store:stageStore,environment:stageEnv)
        awaitCondition { fake.moves == 1 }
        check("stage fill takes priority over saved baseline",fake.record.frame == Rect(200,0,1000,900))
        check("stage fill never creates ordinary candidates",stage.candidates.isEmpty)
        check("stage fill preserves stored baseline",(try? stageStore.load().profiles) == db.profiles)
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
    print("ENGINE_TESTS passed=\(passed) failed=\(failed); injected adapter, not physical AX or Stage Manager validation")
    return failed == 0 ? 0:1
}
#endif
