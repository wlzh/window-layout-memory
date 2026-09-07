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
print("CORE_TESTS passed=\(passed) failed=\(failed) assertions=\(assertions)")
print("Coverage percentage: NOT MEASURED. AX, UI, Stage Manager, hardware and performance tests: NOT RUN.")
exit(failed==0 ? 0:1)
