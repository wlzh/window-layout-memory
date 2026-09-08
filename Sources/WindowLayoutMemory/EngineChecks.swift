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
    pointer=true;service.record.frame.x=250;service.emit();pump(0.8)
    check("drag in progress is not persisted",engine.profile?.windows.first?.frame.x == 20)
    pointer=false;pump(3.5)
    check("stable released gesture automatically persists",engine.profile?.windows.first?.frame.x == 250)
    check("automatic learning updates rather than duplicates role",engine.profile?.windows.count == 1)
    check("disk matches learned geometry",(try? store.load().profiles.first?.windows.first?.frame.x) == 250)
    engine.toggleLock();pump(0.2)
    pointerPoint=CGPoint(x:300,y:45)
    pointer=true;service.record.frame.x=400;service.emit();pump(0.8);pointer=false;pump(3.5)
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
    print("ENGINE_TESTS passed=\(passed) failed=\(failed); injected adapter, not physical AX or Stage Manager validation")
    return failed == 0 ? 0:1
}
#endif
