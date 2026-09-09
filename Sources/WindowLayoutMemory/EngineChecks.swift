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
    var failFill=false,wrongFill=false
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
        if failFill || wrongFill { moves+=1;completion(record.frame,failFill ? "fixture failure":nil);return }
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
    func items(_ menu:NSMenu) -> [NSMenuItem] {
        menu.items.flatMap { [$0] + ($0.submenu.map(items) ?? []) }
    }
    func find(_ menu:NSMenu,_ title:String) -> NSMenuItem? { items(menu).first { $0.title == title } }
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
    trusted=true;service.emit();pump(2.5)
    check("permission grant resumes scans on next event without manual refresh",engine.guardState.trusted && service.scans > deniedScans)
    trusted=false;service.emit();pump(1.2)
    let revokedScans=service.scans
    service.emit();pump(0.8)
    check("permission revocation via event blocks further scans",!engine.guardState.trusted && service.scans == revokedScans)
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
        awaitCondition { !stage.busy && stage.profile?.windows.first?.frame == fake.record.frame }
        check("stage fill replaces stored size while preserving window identity",stage.profile?.windows.first?.frame == fake.record.frame && stage.profile?.windows.first?.id == window.id)
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
        awaitCondition { !stage.busy && stage.profile?.windows.first?.frame == Rect(150,0,1050,900) }
        check("inset fill updates baseline and retains recoverable history",stage.profile?.windows.first?.frame == Rect(150,0,1050,900) && !stage.database.history.isEmpty)
        fake.record.frame=Rect(350,40,400,300)
        fake.onEvent?(fake.record.pid,kAXApplicationActivatedNotification,fake.record.element)
        awaitCondition { fake.record.frame == Rect(150,0,1050,900) }
        check("reactivation reapplies learned inset",fake.record.frame == Rect(150,0,1050,900))
        pump(2.2)
        pointerPoint=CGPoint(x:300,y:5);pointer=true;stage.pointerEvent(down:true)
        fake.record.frame.x=180;pointerPoint.x=330;pointer=false;stage.pointerEvent(down:false)
        pump(3.5)
        check("titlebar drag stays free until next activation",fake.record.frame.x == 180)
        check("free same screen drag waits for verified fill before saving",stage.database.preferences.stageInsets[insetKey] == 150 && stage.profile?.windows.first?.frame == Rect(150,0,1050,900))
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
        check("portrait default remains opt in",fake.moves == offCount)
        check("new combination never borrows inset",stage.database.preferences.stageInsets.count == 1)
        fake.record.frame=Rect(220,170,500,600)
        stage.setPreferences { $0.stageFill=false;$0.stagePortraitFill=true }
        awaitCondition { fake.record.frame == Rect(100,170,700,600) }
        check("portrait only mode preserves vertical geometry",fake.record.frame == Rect(100,170,700,600))
        awaitCondition { !stage.busy && stage.profile?.windows.first?.frame == fake.record.frame }
        check("portrait verified result persists in current combination",stage.profile?.windows.first?.frame == Rect(100,170,700,600))
        let portraitDelegate=AppDelegate();portraitDelegate.engine=stage
        let portraitMenu=NSMenu();portraitDelegate.menuWillOpen(portraitMenu)
        check("portrait switch and child dependency work without landscape",find(portraitMenu,"竖屏横向撑满")?.state == .on && find(portraitMenu,"同时铺满子窗口")?.isEnabled == true)
        pump(2.2)
        pointerPoint=CGPoint(x:300,y:180);pointer=true;stage.pointerEvent(down:true)
        fake.record.frame=Rect(220,240,500,440);pointerPoint=CGPoint(x:420,y:250);pointer=false;stage.pointerEvent(down:false)
        awaitCondition { !stage.busy && stage.profile?.windows.first?.frame == Rect(100,240,700,440) }
        check("portrait manual vertical change is preserved and saved",fake.record.frame == Rect(100,240,700,440) && stage.profile?.windows.first?.frame == fake.record.frame)
        pump(2.2)
        pointerPoint=CGPoint(x:100,y:400);pointer=true;stage.pointerEvent(down:true)
        fake.record.frame=Rect(150,240,650,440);pointerPoint.x=150;pointer=false;stage.pointerEvent(down:false)
        let portraitInsetKey=StageFill.insetKey(topology:topology,display:topology.displays[0])
        awaitCondition { !stage.busy && stage.database.preferences.stageInsets[portraitInsetKey] == 150 }
        check("portrait learns same inset without vertical expansion",stage.database.preferences.stageInsets[portraitInsetKey] == 150 && fake.record.frame == Rect(150,240,650,440))
        let portraitCount=fake.moves
        for _ in 0..<1000 { fake.emit() };pump(0.8)
        check("portrait geometry events do not loop",fake.moves == portraitCount)
        stage.setStageApplicationExclusion(bundle:fake.record.identity.bundle,name:fake.record.app,excluded:true)
        awaitCondition { !stage.busy && stage.database.preferences.stageExcludedApplications[fake.record.identity.bundle] != nil }
        fake.record.frame=Rect(230,200,500,500);fake.emit();pump(2.2)
        check("portrait reuses application exclusions",fake.moves == portraitCount && fake.record.frame == Rect(230,200,500,500))
        stage.togglePause()
    } catch { failed+=1;print("FAIL ENGINE stage setup: \(error)") }
    let baselineDisplay=display
    for portraitMode in [false,true] {
      let display=portraitMode ? Display(id:"portrait-save",name:"Portrait",frame:Rect(0,0,800,1200),primary:true):baselineDisplay
      for mode in ["failed","wrongGeometry","locked","disabledRemember"] {
        do {
            topology=Topology([display]);trusted=true;pointer=false
            var localEnv=env;localEnv.stageManagerEnabled={true};localEnv.stageDisplay={$0}
            let fake=FixtureService();fake.failFill=mode == "failed";fake.wrongFill=mode == "wrongGeometry"
            let store=LayoutStore(directory:root.appendingPathComponent("stage-save-\(portraitMode)-\(mode)"))
            var db=Database();db.preferences.stageFill = !portraitMode;db.preferences.stagePortraitFill=portraitMode
            let expected=portraitMode ? StageFill.portraitTarget(display:display,frame:fake.record.frame)!:Rect(100,0,1100,900)
            db.preferences.autoRemember=mode != "disabledRemember"
            db.profiles=[Profile(name:"Baseline",topology:topology,windows:[SavedWindow(identity:fake.record.identity,displayID:display.id,frame:fake.record.frame,sourceVisible:display.visible)])]
            db.profiles[0].locked=mode == "locked"
            try store.save(db)
            let engine=Engine(service:fake,store:store,environment:localEnv)
            awaitCondition { fake.moves > 0 };pump(0.4);awaitCondition { !engine.busy }
            if mode == "disabledRemember" {
                check("verified fill save independent of auto remember portrait=\(portraitMode)",engine.profile?.windows.first?.frame == expected)
                let revision=engine.profile?.revision
                fake.onEvent?(fake.record.pid,kAXApplicationActivatedNotification,fake.record.element);pump(2.5)
                check("unchanged fill avoids revisions portrait=\(portraitMode)",engine.profile?.revision == revision)
            } else {
                check("stage save \(mode) preserves baseline portrait=\(portraitMode)",(try? store.load()) == db)
            }
            engine.togglePause()
        } catch {failed+=1;print("FAIL ENGINE stage save \(mode): \(error)")}
    }
      }
    do {
        let external=Display(id:"external",name:"External",frame:Rect(-1600,0,1600,1000),primary:false)
        let portrait=Display(id:"portrait",name:"Portrait",frame:Rect(-800,0,800,1200),primary:false)
        let pair=Topology([display,external]),verticalPair=Topology([display,portrait])
        let cases:[(String,Topology,Topology,Display,Bool,Bool,Rect)] = [
            ("reconnect restores saved external display before filling",pair,pair,external,true,false,Rect(-1500,0,1500,1000)),
            ("saved portrait restores original frame instead of filling internal",verticalPair,verticalPair,portrait,true,false,Rect(-700,40,500,600)),
            ("disabled auto restore fills current screen without crossing",pair,pair,external,false,false,Rect(100,0,1100,900)),
            ("unknown combination never borrows saved display",Topology([display]),pair,external,true,false,Rect(100,0,1100,900)),
            ("ambiguous saved roles never choose a destination screen",pair,pair,external,true,true,Rect(100,0,1100,900)),
            ("saved portrait with opt in preserves saved vertical geometry",verticalPair,verticalPair,portrait,true,false,Rect(-700,40,700,600))
        ]
        for (index,item) in cases.enumerated() {
            let (name,current,savedTopology,destination,autoRestore,ambiguous,expected)=item
            topology=current;trusted=true;pointer=false
            let fake=FixtureService()
            let saved=SavedWindow(identity:fake.record.identity,displayID:destination.id,
                frame:destination.id == "portrait" ? Rect(-700,40,500,600):Rect(-1500,40,900,600),sourceVisible:destination.visible)
            var db=Database();db.preferences.stageFill=true;db.preferences.autoRestore=autoRestore
            db.preferences.stagePortraitFill=index == 5
            var windows=[saved]
            if ambiguous { windows.append(SavedWindow(identity:saved.identity,displayID:display.id,frame:Rect(30,40,500,300),sourceVisible:display.visible)) }
            db.profiles=[Profile(name:"Saved setup",topology:savedTopology,windows:windows)]
            let store=LayoutStore(directory:root.appendingPathComponent("routing-\(index)"));try store.save(db)
            var routedEnv=env;routedEnv.stageManagerEnabled={ true };routedEnv.stageDisplay={ $0 }
            let engine=Engine(service:fake,store:store,environment:routedEnv)
            awaitCondition { fake.moves > 0 }
            check(name,fake.record.frame == expected && fake.moves == 1)
            awaitCondition { !engine.busy }
            let changedProfile=engine.profile
            if ambiguous || (destination.frame.width <= destination.frame.height && !db.preferences.stagePortraitFill) {
                check("routing \(index) does not save ambiguous or disabled portrait fill",(try? store.load()) == db)
            } else {
                check("routing \(index) records verified filled geometry",changedProfile?.windows.contains(where:{$0.frame == expected}) == true)
                if index == 3 {
                    check("new combination capture preserves previous combination",engine.database.profiles.first(where:{$0.topology.key == savedTopology.key}) == db.profiles.first)
                }
            }
            if index == 0 {
                pump(2.2)
                pointerPoint=CGPoint(x:-1300,y:5);pointer=true;engine.pointerEvent(down:true)
                fake.record.frame=Rect(100,50,900,700)
                pointerPoint=CGPoint(x:400,y:55);pointer=false;engine.pointerEvent(down:false)
                pump(3.3)
                check("manual cross-screen drag fills user chosen display",fake.record.frame == Rect(100,0,1100,900))
                fake.onEvent?(fake.record.pid,kAXApplicationActivatedNotification,fake.record.element)
                awaitCondition { !engine.busy && engine.profile?.windows.first?.displayID == display.id }
                check("next activation retains newly saved display instead of old screen",fake.record.frame == Rect(100,0,1100,900) && engine.profile?.windows.first?.displayID == display.id)
                let restartedService=FixtureService();restartedService.record.frame=expected
                let restarted=Engine(service:restartedService,store:store,environment:routedEnv)
                awaitCondition { restartedService.record.frame == Rect(100,0,1100,900) && !restarted.busy }
                check("restart uses new saved monitor assignment",restartedService.record.frame == Rect(100,0,1100,900) && restarted.profile?.windows.first?.id == saved.id)
                restarted.togglePause()
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
        let option=find(menu,"同时铺满子窗口")
        check("child menu is indented unchecked and enabled under master",option?.state == .off && option?.indentationLevel == 1 && option?.isEnabled == true)
        check("redundant 100 point menu removed",!menu.items.contains { $0.title.contains("留白设为100") })
        let exclusions=delegate.exceptionSections.first { $0.title == "当前窗口" }?.menu
        check("identified window offers persistent and session exclusion",exclusions?.items.contains { $0.title == "永久排除此类窗口…" } == true && exclusions?.items.contains { $0.title == "当前窗口暂不铺满" } == true)
        check("legacy split exception menus removed",find(menu,"应用例外") == nil && find(menu,"管理窗口例外") == nil)
        check("all exception sections have explicit enabled states",delegate.exceptionSections.count == 3 && delegate.exceptionSections.allSatisfy { !$0.menu.autoenablesItems })
        let unified=find(menu,"铺满例外")?.submenu
        check("unified exceptions use native submenu without window action",find(menu,"铺满例外")?.action != NSSelectorFromString("showExceptions") && unified != nil)
        check("unified window action keeps target and payload",find(menu,"当前窗口暂不铺满")?.target === delegate && (find(menu,"当前窗口暂不铺满")?.representedObject as? String) == fake.record.token)
        check("root has twelve entries and four functional groups",menu.items.filter { !$0.isSeparatorItem }.count == 12 && menu.items.filter { $0.submenu != nil }.map(\.title) == ["台前调度铺满","自动记忆与恢复","布局管理","设置与诊断"])
        let routes:[(String,String,String)] = [
            ("台前调度铺满","横屏自动铺满","toggleStageFill"),
            ("台前调度铺满","同时铺满子窗口","toggleStageChildren"),
            ("自动记忆与恢复","自动核对窗口变化","toggleObserve"),
            ("自动记忆与恢复","自动记忆手动调整","toggleRemember"),
            ("自动记忆与恢复","自动恢复保存布局","toggleAuto"),
            ("自动记忆与恢复","关闭自动恢复并暂停","cancelRestores"),
            ("布局管理","锁定当前布局","lock"),
            ("布局管理","重命名当前布局…","rename"),
            ("布局管理","导出布局备份…","exportBackup"),
            ("布局管理","导入布局备份…","importBackup"),
            ("设置与诊断","登录时启动","toggleLogin"),
            ("设置与诊断","权限与运行状态…","showPanel"),
            ("设置与诊断","重新核对窗口","refresh")]
        for (group,title,selector) in routes {
            let entry=find(menu,group)?.submenu?.items.first { $0.title == title }
            check("menu route \(group)/\(title)",entry?.action == NSSelectorFromString(selector) && entry?.target === delegate)
        }
        check("quick actions remain at root with accurate save label",menu.items.contains { $0.title.hasPrefix("保存已核对窗口") && $0.action == NSSelectorFromString("save") } && menu.items.contains { $0.title == "恢复当前窗口" && $0.action == NSSelectorFromString("restore") } && menu.items.contains { $0.title == "暂停自动操作" && $0.action == NSSelectorFromString("pause") })
        check("empty mapping and history menus disabled",find(menu,"从其它显示器组合映射")?.isEnabled == false && find(menu,"恢复历史基准")?.isEnabled == false)
        check("submenus preserve explicit disabled state",!menu.autoenablesItems && items(menu).compactMap(\.submenu).allSatisfy { !$0.autoenablesItems })
        let scansBefore=fake.scans,movesBefore=fake.moves,dbBefore=child.database
        for _ in 0..<3 { delegate.menuWillOpen(menu) }
        check("opening menus does not scan move or persist",fake.scans == scansBefore && fake.moves == movesBefore && child.database == dbBefore)
        trusted=false;delegate.menuWillOpen(menu)
        check("missing permission exposes actionable root entry",menu.items.first?.title == "需要辅助功能权限…" && menu.items.first?.action == NSSelectorFromString("authorize"))
        check("submenu explains missing permission and disallows window actions",delegate.exceptionSections[1].menu.items.contains { $0.title.contains("辅助功能授权") && $0.action == nil })
        trusted=true;delegate.menuWillOpen(menu)
        child.setPreferences { $0.stageFillChildren=true };awaitCondition { fake.moves > 0 }
        check("opt in allows standard child fill",fake.record.frame == Rect(100,0,1100,900))
        awaitCondition { !child.busy && child.profile?.windows.first?.frame == fake.record.frame }
        let filledProfiles=child.database.profiles
        let rule=child.stageRule(for:fake.record)!
        child.setPreferences { $0.stageExcludedKinds=[rule] };pump(2.2)
        let before=fake.moves
        fake.record.frame=original;fake.emit();pump(2.2)
        check("explicit exclusion overrides child opt in without restore fallback",fake.moves == before && fake.record.frame == original)
        let reloaded=try store.load()
        check("persistent exclusions preserve newly saved filled profile",reloaded.preferences.stageExcludedKinds == [rule] && child.database.profiles == filledProfiles)
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
        check("menu offers only session fallback without identifier",delegate.exceptionSections.first { $0.title == "当前窗口" }?.menu.items.contains { $0.title.contains("未提供可靠窗口标识") && !$0.isEnabled } == true)
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
        check("child option disabled while master is off",find(menu,"同时铺满子窗口")?.isEnabled == false)
        enabled=false;fake.record.frame=original
        child.setPreferences { $0.stageFill=true }
        awaitCondition { fake.record.frame == child.profile?.windows.first?.frame }
        check("system stage off restores newly recorded filled baseline",fake.record.frame == child.profile?.windows.first?.frame)
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
        awaitCondition { fake.scans > 0 && !excluded.busy && !excluded.guardState.settling }
        check("saved app exclusion blocks fill after engine restart",fake.moves == 0 && fake.scans > 0)
        check("app exclusion keeps ordinary app observation preferences intact",excluded.database.preferences.excludedBundles.isEmpty && excluded.candidates.isEmpty)
        let delegate=AppDelegate();delegate.engine=excluded
        let menu=NSMenu();menu.autoenablesItems=false;delegate.menuWillOpen(menu)
        let submenu=delegate.exceptionSections.first { $0.title == "应用级" }?.menu
        check("app menu includes persisted stopped app as checked",submenu?.items.contains { $0.toolTip == "test.fixture" && $0.state == .on && $0.title == "Synthetic · 未运行" } == true)
        check("app menu includes file picker entry",submenu?.items.contains { $0.title == "从文件选择应用…" } == true)
        excluded.setStageApplicationExclusion(bundle:"test.fixture",name:"Synthetic",excluded:false)
        awaitCondition { !excluded.busy && excluded.database.preferences.stageExcludedApplications["test.fixture"] == nil && fake.record.frame == Rect(100,0,1100,900) }
        if fake.record.frame != Rect(100,0,1100,900) {
            print("EXCLUSION_DIAGNOSTIC moves=\(fake.moves) scans=\(fake.scans) busy=\(excluded.busy) paused=\(excluded.guardState.paused) status=\(excluded.status) frame=\(fake.record.frame)")
        }
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
        picker.close()
        excluded.setPreferences { $0.autoObserve=false;$0.excludedBundles=["test.stopped"] }
        awaitCondition { !excluded.busy && !excluded.database.preferences.autoObserve }
        delegate.menuWillOpen(menu);menu.update()
        check("auto remember dependency disabled without discarding saved choice",find(menu,"自动记忆手动调整")?.isEnabled == false && find(menu,"自动记忆手动调整")?.state == .on)
        check("global stopped app exclusion remains removable in its own group",find(menu,"完全忽略应用")?.submenu?.items.contains { ($0.representedObject as? String) == "test.stopped" && $0.state == .on && $0.action == NSSelectorFromString("toggleExclude:") } == true)
        check("app exceptions and global exclusions stay independent during menu creation",excluded.database.preferences.stageExcludedApplications == ["test.fixture":"Synthetic"] && excluded.database.preferences.excludedBundles == ["test.stopped"])
        func depth(_ current:NSMenu) -> Int { 1+(current.items.compactMap(\.submenu).map(depth).max() ?? 0) }
        check("menu nesting is limited to two flyouts",depth(menu) <= 3)
        excluded.togglePause();delegate.menuWillOpen(menu)
        check("paused root changes to resume without disabling restore preference",menu.items.first?.title.contains("已暂停") == true && find(menu,"继续自动操作")?.action == NSSelectorFromString("pause"))
    } catch { failed+=1;print("FAIL ENGINE application exclusions: \(error)") }
    print("ENGINE_TESTS passed=\(passed) failed=\(failed); injected adapter, not physical AX or Stage Manager validation")
    return failed == 0 ? 0:1
}
#endif
