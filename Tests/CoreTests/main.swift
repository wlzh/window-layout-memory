import Foundation
import LayoutCore

var passed=0, failed=0, assertions=0
func expect(_ condition: @autoclosure () throws ->Bool,_ message: String="assertion") throws {
    assertions += 1
    if try !condition() { throw CoreError.invalid(message) }
}
func rejects(_ block: () throws -> Void) throws {
    var rejected=false
    do { try block() } catch { rejected=true }
    try expect(rejected,"expected error")
}
func test(_ name:String,_ block:() throws ->Void) {
    do { try block(); passed+=1; print("PASS \(name)") }
    catch { failed+=1; print("FAIL \(name): \(error)") }
}
let a=Display(id:"a",name:"Main",frame:Rect(0,0,1000,800),primary:true)
let b=Display(id:"b",name:"Left",frame:Rect(-1200,-200,1200,1000))
let c=Display(id:"c",name:"Portrait",frame:Rect(-2000,-200,800,1400),rotation:90)
let one=Topology([a]),two=Topology([a,b]),three=Topology([a,b,c])
let identity=WindowIdentity(bundle:"test.app",title:"Document")
func window(_ identity:WindowIdentity=identity,frame:Rect=Rect(20,40,400,300)) -> SavedWindow {
    SavedWindow(identity:identity,displayID:"a",frame:frame,sourceVisible:a.visible)
}
func profile(_ t:Topology=one) -> Profile { Profile(name:"Fixture",topology:t,windows:[window()]) }

test("geometry rejects nonfinite, zero, negative") {
    for r in [Rect(.nan,0,1,1),Rect(0,.infinity,1,1),Rect(0,0,0,1),Rect(0,0,-1,1),Rect(0,0,1,-1)] { try expect(!r.valid) }
}
test("small ordinary windows remain valid in Stage Manager OFF") { try expect(Rect(1,2,40,30).valid) }
test("negative desktop coordinates valid") { try expect(Rect(-3200,-200,1000,1600).valid) }
test("geometry tolerance boundary") {
    try expect(Rect(1,2,3,4).close(to:Rect(5,6,7,8)))
    try expect(!Rect(1,2,3,4).close(to:Rect(5.01,6,7,8)))
}
test("nonoverlapping area is zero") { try expect(a.frame.intersection(b.frame)==0) }
test("display owner based on intersection") { try expect(two.owner(of:Rect(-1100,0,300,200))?.id=="b") }
test("ambiguous equal-overlap owner rejected") { try expect(two.owner(of:Rect(-100,0,200,100))==nil) }
test("offscreen owner unknown") { try expect(one.owner(of:Rect(2000,2000,100,100))==nil) }
test("topology order independent") { try expect(Topology([a,b,c]).key==Topology([c,b,a]).key) }
test("different same-count display identities isolated") {
    var d=b; d.id="d"; try expect(Topology([a,b]).key != Topology([a,d]).key)
}
test("screen count isolated") { try expect(one.key != two.key && two.key != three.key) }
test("rotation key changes") { var d=b; d.rotation=90; try expect(two.key != Topology([a,d]).key) }
test("scale key changes") { var d=a; d.scale=2; try expect(one.key != Topology([d]).key) }
test("primary changes key") { var d=a; var e=b; d.primary=false;e.primary=true;try expect(two.key != Topology([d,e]).key) }
test("display arrangement changes key") { var d=b;d.frame.x -= 1;try expect(two.key != Topology([a,d]).key) }
test("display enumeration canonical JSON avoids separator collisions") {
    var d=a;d.id="a|b,[]";try expect(Topology([d]).key != one.key)
}
test("display visible area does not fork profile") { var d=a;d.visible.y=40;try expect(Topology([d]).key==one.key) }
test("topology rejects duplicate IDs") { try expect(!Topology([a,a]).valid) }
test("topology rejects no primary or multiple primaries") { try expect(!Topology([b]).valid);var d=b;d.primary=true;try expect(!Topology([a,d]).valid) }
test("mirror rejected safely") { var d=b;d.mirrored=true;try expect(!Topology([a,d]).valid) }
test("empty topology rejected") { try expect(!Topology([]).valid) }
test("invalid screen geometry rejected") { var d=a;d.visible.width=0;try expect(!Topology([d]).valid) }
test("unchanged geometry restored exactly") { let w=window();try expect(w.target(in:one)==w.frame) }
test("unknown display target rejected") { var w=window();w.displayID="missing";try expect(w.target(in:one)==nil) }
test("relative geometry adapts to usable region") {
    var d=a;d.visible=Rect(0,40,500,400)
    try expect(window().target(in:Topology([d]))==Rect(10,60,200,150))
}
test("unreachable titlebar clamped") { let r=Rect(3000,-3000,400,300).reachable(in:a.visible);try expect(r.x==920 && r.y==0) }
test("cross-screen negative offsets not forcibly clamped") { let r=Rect(-200,0,500,300);try expect(r.reachable(in:a.visible)==r) }
test("geometry roundtrip properties 500 fixtures") {
    for i in 1...500 {
        let frame=Rect(Double(-i),Double(i),Double(i+50),Double(i+30))
        try expect(frame.normalized(in:b.visible).expanded(in:b.visible).close(to:frame,tolerance:0.000001))
    }
}
test("exact title identity match") { let w=window();try expect(Matcher.assign([w],[LiveWindow(token:"1",identity:identity,frame:w.frame)]).resolved[w.id]=="1") }
test("changed title not guessed") {
    let w=window();let live=LiveWindow(token:"1",identity:WindowIdentity(bundle:identity.bundle,title:"Other"),frame:w.frame)
    try expect(Matcher.assign([w],[live]).missing.contains(w.id))
}
test("same app title ambiguity blocks both saved roles") {
    let w=window(),v=window();let live=LiveWindow(token:"1",identity:identity,frame:w.frame)
    try expect(Matcher.assign([w,v],[live]).ambiguous.count==2)
}
test("multiple live same-title windows ambiguous") {
    let w=window();let live=["1","2"].map { LiveWindow(token:$0,identity:identity,frame:w.frame) }
    try expect(Matcher.assign([w],live).ambiguous.contains(w.id))
}
test("same name different app isolated") {
    let w=window();let live=LiveWindow(token:"1",identity:WindowIdentity(bundle:"other",title:identity.title),frame:w.frame)
    try expect(Matcher.assign([w],[live]).resolved.isEmpty)
}
test("document identity survives title change") {
    let w=window(WindowIdentity(bundle:"a",title:"Old",document:"file:///synthetic"))
    let live=LiveWindow(token:"1",identity:WindowIdentity(bundle:"a",title:"New",document:"file:///synthetic"),frame:w.frame)
    try expect(Matcher.assign([w],[live]).resolved[w.id]=="1")
}
test("titleless window not singleton-guessed after login") {
    let w=window(WindowIdentity(bundle:"a"));let live=LiveWindow(token:"1",identity:w.identity,frame:w.frame)
    try expect(Matcher.assign([w],[live]).missing.contains(w.id))
}
test("explicit session binding survives title mutation") {
    let w=window();let live=LiveWindow(token:"1",identity:WindowIdentity(bundle:identity.bundle,title:"changed"),frame:w.frame)
    try expect(Matcher.assign([w],[live],bindings:[w.id:"1"]).resolved[w.id]=="1")
}
test("binding cannot cross app identity") {
    let w=window();let live=LiveWindow(token:"1",identity:WindowIdentity(bundle:"other"),frame:w.frame)
    try expect(Matcher.assign([w],[live],bindings:[w.id:"1"]).resolved.isEmpty)
}
test("window order invariant") {
    let w=window(),v=window(WindowIdentity(bundle:"other",title:"different"))
    let l=[LiveWindow(token:"1",identity:w.identity,frame:w.frame),LiveWindow(token:"2",identity:v.identity,frame:v.frame)]
    try expect(Matcher.assign([w,v],l).resolved==Matcher.assign([v,w],l.reversed()).resolved)
}
test("guard starts fail closed") { let g=GuardState();try expect(!g.permits(0,key:"")) }
func ready() -> GuardState { var g=GuardState();g.trusted=true;g.settling=false;g.topologyKey=one.key;return g }
test("ready generation permits") { let g=ready();try expect(g.permits(0,key:one.key)) }
test("topology change cancels stale operations") { var g=ready();g.invalidate();try expect(!g.permits(0,key:one.key)) }
test("wrong topology rejected") { let g=ready();try expect(!g.permits(0,key:two.key)) }
test("pause cancels operations") { var g=ready();g.paused=true;try expect(!g.permits(0,key:one.key)) }
test("sleep cancels operations") { var g=ready();g.sleeping=true;try expect(!g.permits(0,key:one.key)) }
test("revoked permission cancels operations") { var g=ready();g.trusted=false;try expect(!g.permits(0,key:one.key)) }
test("transition settling blocks learning/restoration") { var g=ready();g.settling=true;try expect(!g.permits(0,key:one.key)) }
test("1000 invalidations reject old events") {
    var g=ready()
    for _ in 0..<1000 { let old=g.generation;g.invalidate();g.settling=false;try expect(!g.permits(old,key:one.key)) }
}
test("database schema rejected") { var db=Database();db.schemaVersion=2;try rejects { try db.validate() } }
test("profile points to unknown display rejected") { var db=Database();var p=profile();p.windows[0].displayID="none";db.profiles=[p];try rejects { try db.validate() } }
test("duplicate role ID rejected") { var db=Database();var p=profile();p.windows.append(p.windows[0]);db.profiles=[p];try rejects { try db.validate() } }
test("profile replacement optimistic concurrency") {
    var db=Database();var p=profile();try db.replace(p,expectedRevision:nil);p.revision=2
    try rejects { try db.replace(p,expectedRevision:10) };try expect(db.profiles[0].revision==1)
}
test("invalid replacement is transactional") {
    var db=Database();var p=profile();try db.replace(p,expectedRevision:nil);let old=db
    p.revision=2;p.windows[0].frame.width=0
    try rejects { try db.replace(p,expectedRevision:1) };try expect(db==old)
}
test("equal revision rejected") { var db=Database();let p=profile();try db.replace(p,expectedRevision:nil);try rejects { try db.replace(p,expectedRevision:1) } }
test("history bounded and current retained") {
    var db=Database();var p=profile();try db.replace(p,expectedRevision:nil)
    for i in 2...100 { p.revision=i;try db.replace(p,expectedRevision:i-1) }
    try expect(db.history.count==20);try expect(db.profiles[0].revision==100);try expect(db.history.last?.revision==99)
}
test("1-2-3-2-1 distinct profiles 10 cycles") {
    var db=Database()
    for t in [one,two,three] { try db.replace(profile(t),expectedRevision:nil) }
    for _ in 0..<10 { for t in [one,two,three,two,one] { try expect(db.profiles.filter { $0.topology.key==t.key }.count==1) } }
}
let temp=FileManager.default.temporaryDirectory.appendingPathComponent("wlm-tests-\(UUID().uuidString)")
defer { try? FileManager.default.removeItem(at:temp) }
test("missing storage returns empty library") { let store=LayoutStore(directory:temp.appendingPathComponent("empty"));try expect(try store.load().profiles.isEmpty) }
test("atomic store roundtrip and private permissions") {
    let store=LayoutStore(directory:temp.appendingPathComponent("roundtrip"));var db=Database();try db.replace(profile(),expectedRevision:nil)
    try store.save(db);let loaded=try store.load();try expect(loaded==db)
    let attrs=try FileManager.default.attributesOfItem(atPath:store.file.path)
    try expect((attrs[.posixPermissions] as? NSNumber)?.intValue==0o600)
}
test("unchanged save does not rewrite") {
    let store=LayoutStore(directory:temp.appendingPathComponent("no-op"));let db=Database();try store.save(db)
    let before=try FileManager.default.attributesOfItem(atPath:store.file.path)[.modificationDate] as? Date
    try store.save(db)
    let after=try FileManager.default.attributesOfItem(atPath:store.file.path)[.modificationDate] as? Date
    try expect(before==after)
}
test("corrupt data not treated as empty") {
    let store=LayoutStore(directory:temp.appendingPathComponent("corrupt"));try store.save(Database())
    try Data("broken".utf8).write(to:store.file)
    try rejects { _=try store.load() };try expect(try Data(contentsOf:store.file)==Data("broken".utf8))
}
test("invalid save preserves previous bytes") {
    let store=LayoutStore(directory:temp.appendingPathComponent("reject"));try store.save(Database());let old=try Data(contentsOf:store.file)
    var db=Database();db.schemaVersion=99;try rejects { try store.save(db) };try expect(try Data(contentsOf:store.file)==old)
}
test("symlink store rejected") {
    let dir=temp.appendingPathComponent("link");try FileManager.default.createSymbolicLink(at:dir,withDestinationURL:temp)
    try rejects { try LayoutStore(directory:dir).save(Database()) }
}
test("oversized import rejected before decoding") {
    let url=temp.appendingPathComponent("large.json");try Data(count:21*1024*1024).write(to:url)
    try rejects { _=try LayoutStore(directory:temp).decode(url) }
}
test("default auto restore is opt in") { try expect(!Preferences().autoRestore) }
test("changed save atomically replaces existing file") {
    let store=LayoutStore(directory:temp.appendingPathComponent("replace"));var db=Database();try store.save(db)
    try db.replace(profile(),expectedRevision:nil);try store.save(db);try expect(try store.load()==db)
}
test("symlink layout file rejected") {
    let dir=temp.appendingPathComponent("file-link");try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)
    try FileManager.default.createSymbolicLink(at:dir.appendingPathComponent("layouts.json"),withDestinationURL:temp.appendingPathComponent("large.json"))
    try rejects { _=try LayoutStore(directory:dir).load() }
}
test("missing expected profile rejected without mutation") {
    var db=Database();try rejects { try db.replace(profile(),expectedRevision:1) };try expect(db.profiles.isEmpty)
}
test("too many history entries rejected") { var db=Database();db.history=Array(repeating:profile(),count:201);try rejects { try db.validate() } }
test("duplicate topology rejected transactionally") {
    var db=Database();try db.replace(profile(),expectedRevision:nil);let old=db
    try rejects { try db.replace(profile(),expectedRevision:nil) };try expect(db==old)
}
test("scale and geometry must be finite") { var d=a;d.scale = .nan;try expect(!Topology([d]).valid);d.scale=1;d.rotation = .infinity;try expect(!Topology([d]).valid) }
test("invalid source frame produces no target") { var w=window();w.sourceVisible.width=0;try expect(w.target(in:one)==nil) }
test("stable identifier matches changed title") {
    let w=window(WindowIdentity(bundle:"a",title:"old",identifier:"stable"))
    let l=LiveWindow(token:"1",identity:WindowIdentity(bundle:"a",title:"new",identifier:"stable"),frame:w.frame)
    try expect(Matcher.assign([w],[l]).resolved[w.id]=="1")
}
test("legacy preferences migrate without enabling automatic mutations") {
    let p=try JSONDecoder().decode(Preferences.self,from:Data("{\"autoObserve\":true,\"autoRestore\":false,\"excludedBundles\":[]}".utf8))
    try expect(!p.autoRemember && !p.autoRestore && p.autoObserve)
}
test("empty preferences decode conservatively") {
    let p=try JSONDecoder().decode(Preferences.self,from:Data("{}".utf8))
    try expect(!p.autoRemember && !p.autoRestore && p.autoObserve)
}
test("automatic remember preference roundtrip") {
    var p=Preferences();p.autoRemember=true;p.autoRestore=true
    try expect(try JSONDecoder().decode(Preferences.self,from:JSONEncoder().encode(p)) == p)
}
test("malformed automatic remember preference rejected") {
    try rejects { _=try JSONDecoder().decode(Preferences.self,from:Data("{\"autoRemember\":\"yes\"}".utf8)) }
}
test("activation and system geometry changes never grant learning") {
    var gate=LearningGate()
    for i in 0..<1000 {
        gate.note("w",now:Double(i),pointerDown:false,eligible:true)
        try expect(!gate.permits("w",now:Double(i),pointerDown:false,stable:true,eligible:true))
    }
    try expect(gate.count == 0)
}
test("learning requires release stability and eligibility") {
    for down in [false,true] { for stable in [false,true] { for eligible in [false,true] {
        var gate=LearningGate(); gate.note("w",now:10,pointerDown:true,eligible:true)
        try expect(gate.permits("w",now:11,pointerDown:down,stable:stable,eligible:eligible) == (!down && stable && eligible))
    } } }
}
test("background or transition gestures do not grant learning") {
    var gate=LearningGate();gate.note("w",now:10,pointerDown:true,eligible:false)
    try expect(!gate.permits("w",now:11,pointerDown:false,stable:true,eligible:true))
}
test("gesture lifetime bounded and monotonic") {
    var gate=LearningGate();gate.note("w",now:10,pointerDown:true,eligible:true)
    for now in [9.0,40.001,Double.infinity,Double.nan] {
        try expect(!gate.permits("w",now:now,pointerDown:false,stable:true,eligible:true))
    }
    try expect(gate.permits("w",now:40,pointerDown:false,stable:true,eligible:true))
}
test("invalid gesture time ignored") {
    var gate=LearningGate();gate.note("w",now:.nan,pointerDown:true,eligible:true)
    try expect(gate.count == 0)
}
test("new geometry refreshes an active drag deadline") {
    var gate=LearningGate();gate.note("w",now:0,pointerDown:true,eligible:true)
    gate.note("w",now:29,pointerDown:true,eligible:true)
    try expect(gate.permits("w",now:31,pointerDown:false,stable:true,eligible:true))
}
test("generation reset prevents learning across monitor changes") {
    var gate=LearningGate();gate.note("w",now:0,pointerDown:true,eligible:true);gate.reset()
    try expect(gate.count == 0)
    try expect(!gate.permits("w",now:1,pointerDown:false,stable:true,eligible:true))
}
test("restoring window discards only its gesture") {
    var gate=LearningGate()
    for token in ["a","b"] { gate.note(token,now:1,pointerDown:true,eligible:true) }
    gate.discard("a");try expect(gate.count == 1)
    try expect(gate.permits("b",now:2,pointerDown:false,stable:true,eligible:true))
}
test("gesture flood remains bounded and expires") {
    var gate=LearningGate()
    for i in 0..<2000 { gate.note("\(i)",now:1,pointerDown:true,eligible:true) }
    try expect(gate.count == 500)
    gate.note("new",now:32,pointerDown:true,eligible:true);try expect(gate.count == 1)
}
test("empty capture does not create profile") { try expect(try CaptureMerge.updated(nil,topology:one,windows:[]) == nil) }
test("first capture establishes profile") {
    let w=window(),p=try CaptureMerge.updated(nil,topology:one,windows:[w])!
    try expect(p.windows == [w] && p.revision == 1 && p.topology == one)
}
test("unchanged capture makes no revision history or disk work") {
    let p=profile();try expect(try CaptureMerge.updated(p,topology:one,windows:p.windows) == nil)
    var w=p.windows[0];w.frame.x+=0.4
    try expect(try CaptureMerge.updated(p,topology:one,windows:[w]) == nil)
}
test("changed capture updates same role preserving unseen windows") {
    var p=profile();p.windows.append(window(WindowIdentity(bundle:"other")))
    var w=p.windows[0];w.frame.x+=30
    let next=try CaptureMerge.updated(p,topology:one,windows:[w])!
    try expect(next.id == p.id && next.revision == p.revision+1)
    try expect(next.windows == [w,p.windows[1]])
}
test("capture updates identity and visible region without adding role") {
    let p=profile();var w=p.windows[0];w.identity.title="Changed";w.sourceVisible.y+=20
    let next=try CaptureMerge.updated(p,topology:one,windows:[w])!
    try expect(next.windows == [w])
}
test("locked profiles reject even automatic no-op capture") {
    var p=profile();p.locked=true
    try rejects { _=try CaptureMerge.updated(p,topology:one,windows:p.windows) }
}
test("capture rejects stale topology and invalid geometry") {
    try rejects { _=try CaptureMerge.updated(profile(),topology:two,windows:[window()]) }
    try rejects { _=try CaptureMerge.updated(nil,topology:Topology([]),windows:[]) }
    var w=window();w.frame.width=0
    try rejects { _=try CaptureMerge.updated(nil,topology:one,windows:[w]) }
}
test("one two three monitor capture cycle preserves independent baselines") {
    var db=Database()
    for cycle in 0..<10 { for topology in [one,two,three,two,one] {
        let existing=db.profiles.first { $0.topology.key == topology.key }
        var w=existing?.windows.first ?? window();w.frame.x=Double(cycle*10+topology.displays.count)
        if let p=try CaptureMerge.updated(existing,topology:topology,windows:[w]) {
            try db.replace(p,expectedRevision:existing?.revision)
        }
        try db.validate()
        for p in db.profiles where p.topology.key != topology.key {
            try expect(Int(p.windows[0].frame.x) % 10 == p.topology.displays.count)
        }
    } }
    try expect(db.profiles.count == 3)
}
test("new installations enable deliberate-drag memory without automatic moves") {
    try expect(Preferences().autoRemember && !Preferences().autoRestore)
}
test("explicit display mapping adapts geometry and preserves source") {
    let p=profile();let original=p
    let mapped=try ProfileMapping.copy(p,to:two,mapping:["a":"b"])
    try expect(mapped.windows[0].displayID == "b")
    try expect(mapped.windows[0].frame == p.windows[0].frame.normalized(in:a.visible).expanded(in:b.visible))
    try expect(mapped.id != p.id && p == original && !mapped.locked)
}
test("mapping rejects missing duplicate and unknown display assignments") {
    for mapping in [[String:String](),["a":"unknown"],["a":"b","unknown":"a"]] {
        try rejects { _=try ProfileMapping.copy(profile(),to:two,mapping:mapping) }
    }
    try rejects { _=try ProfileMapping.copy(profile(two),to:two,mapping:["a":"a","b":"a"]) }
}
test("mapping rejects invalid geometry") {
    var p=profile();p.windows[0].sourceVisible.width=0
    try rejects { _=try ProfileMapping.copy(p,to:one,mapping:["a":"a"]) }
}
test("mapping never silently assigns a missing source window display") {
    var p=profile();p.windows[0].displayID="missing"
    try rejects { _=try ProfileMapping.copy(p,to:one,mapping:["a":"a"]) }
}
test("retry requires budget transient error unchanged geometry and no pointer") {
    let frame=Rect(10,10,200,100)
    for remaining in [0,1] { for transient in [false,true] { for pointer in [false,true] {
        try expect(RestoreRetry.permits(remaining:remaining,transient:transient,original:frame,actual:frame,pointerDown:pointer)
            == (remaining > 0 && transient && !pointer))
    } } }
    try expect(!RestoreRetry.permits(remaining:1,transient:true,original:frame,actual:nil,pointerDown:false))
    try expect(!RestoreRetry.permits(remaining:1,transient:true,original:frame,actual:Rect(20,10,200,100),pointerDown:false))
}
test("pointer evidence requires titlebar or resize edge not sidebar or content") {
    let r=Rect(100,100,500,400)
    for point in [(120.0,110.0),(100,300),(600,300),(350,500)] { try expect(r.isDragHandle(x:point.0,y:point.1)) }
    for point in [(10.0,300.0),(350,300),(800,800),(Double.nan,100)] { try expect(!r.isDragHandle(x:point.0,y:point.1)) }
}
test("same built-in screen has independent windows in different dual-screen combinations") {
    var other=b;other.id="external-other";other.name=b.name
    let setups=[Topology([a,b]),Topology([a,other])]
    var db=Database()
    for (index,setup) in setups.enumerated() {
        let w=window(frame:Rect(Double(100+index*300),50,Double(400+index*100),300))
        let p=Profile(name:"Same count",topology:setup,windows:[w])
        try db.replace(p,expectedRevision:nil)
    }
    try expect(db.profiles.count == 2)
    for (index,setup) in setups.enumerated() {
        let p=db.profiles.first { $0.topology.key == setup.key }!
        try expect(p.windows[0].displayID == "a")
        try expect(p.windows[0].target(in:setup) == Rect(Double(100+index*300),50,Double(400+index*100),300))
    }
}
test("three-screen configurations with one changed external screen never share profiles") {
    var other=c;other.id="different-portrait";other.name=c.name
    let setups=[Topology([a,b,c]),Topology([a,b,other])]
    var db=Database()
    for (index,setup) in setups.enumerated() {
        let windows=index == 0 ? [window(WindowIdentity(bundle:"work.editor"))] : [window(WindowIdentity(bundle:"personal.browser"))]
        try db.replace(Profile(name:"Three screens",topology:setup,windows:windows),expectedRevision:nil)
    }
    try expect(db.profiles[0].windows[0].identity.bundle == "work.editor")
    try expect(db.profiles[1].windows[0].identity.bundle == "personal.browser")
    try expect(db.profiles.allSatisfy { $0.windows[0].displayID == "a" })
}
test("updating shared built-in screen in one combination never mutates another") {
    var other=b;other.id="b2"
    let work=two,home=Topology([a,other])
    var db=Database()
    for setup in [work,home] { try db.replace(profile(setup),expectedRevision:nil) }
    let homeBefore=db.profiles[1],original=db.profiles[0]
    var moved=original.windows[0];moved.frame=Rect(400,200,300,500)
    let updated=try CaptureMerge.updated(original,topology:work,windows:[moved])!
    try db.replace(updated,expectedRevision:original.revision)
    try expect(db.profiles[1] == homeBefore)
    try expect(db.history.count == 1 && db.history[0].id == original.id)
}
test("combination-specific internal-screen layouts survive disk restart") {
    let dir=FileManager.default.temporaryDirectory.appendingPathComponent("wlm-combinations-\(UUID())")
    defer { try? FileManager.default.removeItem(at:dir) }
    var external=b;external.id="other-external"
    let setups=[one,two,three,Topology([a,external]),Topology([a,external,c])]
    var db=Database()
    for (index,setup) in setups.enumerated() {
        try db.replace(Profile(name:"Configuration",topology:setup,windows:[window(frame:Rect(Double(index*100),40,400,300))]),expectedRevision:nil)
    }
    try LayoutStore(directory:dir).save(db)
    let loaded=try LayoutStore(directory:dir).load()
    for (index,setup) in setups.enumerated() {
        let p=loaded.profiles.first { $0.topology.key == setup.key }!
        try expect(p.windows[0].target(in:setup)?.x == Double(index*100))
    }
    try expect(loaded.profiles.count == 5)
}
print("CORE_TESTS passed=\(passed) failed=\(failed) assertions=\(assertions)")
print("Coverage percentage: NOT MEASURED. AX, UI, Stage Manager, hardware and performance tests: NOT RUN.")
exit(failed==0 ? 0:1)
