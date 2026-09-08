#if DEBUG
import AppKit
import LayoutCore

func runPreviewChecks() -> Int32 {
    _=NSApplication.shared
    var passed=0,failed=0
    func check(_ name: String,_ result: @autoclosure ()->Bool) {
        if result() { passed+=1;print("PASS PREVIEW \(name)") }
        else { failed+=1;print("FAIL PREVIEW \(name)") }
    }
    let a=Display(id:"synthetic-internal",name:"Mac 内屏",frame:Rect(0,0,1512,982),primary:true)
    let b=Display(id:"synthetic-landscape",name:"外接横屏",frame:Rect(-1920,-224,1920,1080))
    let c=Display(id:"synthetic-portrait",name:"外接竖屏",frame:Rect(-3360,-224,1440,2560),rotation:90)
    let topology=Topology([a,b,c])
    let identities=[WindowIdentity(bundle:"fixture.browser",title:"synthetic"),WindowIdentity(bundle:"fixture.editor",title:"synthetic"),WindowIdentity(bundle:"fixture.chat",title:"synthetic")]
    let frames=[Rect(-3260,10,1200,1850),Rect(-1800,30,1500,750),Rect(120,90,1000,700)]
    let saved=zip(identities,frames).map { SavedWindow(identity:$0.0,displayID:topology.owner(of:$0.1)!.id,frame:$0.1,sourceVisible:topology.owner(of:$0.1)!.visible) }
    let current=zip(identities,frames).enumerated().map { index,pair in
        PreviewObservation(token:"fixture:\(index)",name:["浏览器","编辑器","聊天应用"][index],identity:pair.0,
            frame:Rect(pair.1.x+40,pair.1.y+20,pair.1.width-60,pair.1.height),observedAt:Date(timeIntervalSince1970:1000),usable:true)
    }
    let profile=Profile(name:"合成三屏布局",topology:topology,windows:saved)
    let other=Profile(name:"其它组合",topology:Topology([a]),windows:[])
    weak var releasedController: LayoutPreviewController?
    weak var releasedWindow: NSWindow?
    weak var releasedCanvas: LayoutCanvas?
    autoreleasepool {
        var controller: LayoutPreviewController?=LayoutPreviewController(provider:{ id,mode in
            PreviewScene.make(currentTopology:topology,observations:current,profile:id == other.id ? other:profile,mode:mode)
        },profiles:{ [profile,other] },status:{ "合成数据测试，无真实窗口" })
        releasedController=controller;releasedWindow=controller?.window;releasedCanvas=controller?.canvas
        check("opens with current mode and topology",controller?.canvas.scene?.rows.count == 3 && controller?.modes.selectedSegment == 0)
        let before=controller!.renderCount
        for _ in 0..<1000 { controller?.requestRefresh() }
        RunLoop.main.run(until:Date(timeIntervalSinceNow:0.2))
        check("1000 refresh requests coalesce to one render",controller!.renderCount == before+1)
        let idle=controller!.renderCount;RunLoop.main.run(until:Date(timeIntervalSinceNow:0.2))
        check("idle preview does not refresh itself",controller!.renderCount == idle)
        controller?.modes.selectedSegment=2;controller?.controlsChanged()
        check("comparison shows matched pairs",controller!.canvas.scene!.rows.allSatisfy { $0.delta != nil })
        controller?.window?.contentView?.layoutSubtreeIfNeeded()
        if CommandLine.arguments.contains("--render-preview") {
            controller?.window?.appearance=NSAppearance(named:.aqua)
            controller?.window?.orderFront(nil)
            controller?.window?.displayIfNeeded()
            RunLoop.main.run(until:Date(timeIntervalSinceNow:0.15))
        }
        if let index=CommandLine.arguments.firstIndex(of:"--render-preview"),CommandLine.arguments.indices.contains(index+1),let view=controller?.window?.contentView,
           let bitmap=view.bitmapImageRepForCachingDisplay(in:view.bounds) {
            view.effectiveAppearance.performAsCurrentDrawingAppearance { view.cacheDisplay(in:view.bounds,to:bitmap) }
            do { try bitmap.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:CommandLine.arguments[index+1]));print("SYNTHETIC_PREVIEW_RENDERED") }
            catch { failed+=1;print("FAIL PREVIEW render \(error)") }
        }
        controller?.combinations.selectItem(at:2);controller?.combinationChanged()
        check("other combination forces saved mode",controller?.modes.selectedSegment == 1 && controller?.canvas.scene?.sameCombination == false)
        check("other combination disables current and comparison",controller?.modes.isEnabled(forSegment:0) == false && controller?.modes.isEnabled(forSegment:2) == false)
        controller?.combinations.selectItem(at:0);controller?.combinationChanged()
        check("returning to current combination enables comparison",controller?.modes.isEnabled(forSegment:2) == true)
        controller?.requestRefresh();let count=controller!.renderCount
        controller?.window?.close();RunLoop.main.run(until:Date(timeIntervalSinceNow:0.2))
        check("closing cancels scheduled rendering",controller!.closed && controller!.renderCount == count && controller!.canvas.scene == nil)
        controller?.requestRefresh();controller?.refreshNow()
        check("disposed controller ignores further events",controller!.renderCount == count)
        controller=nil
    }
    RunLoop.main.run(until:Date(timeIntervalSinceNow:0.1))
    check("controller is deallocated",releasedController == nil)
    check("window is deallocated",releasedWindow == nil)
    check("drawing surface is deallocated",releasedCanvas == nil)
    print("PREVIEW_TESTS passed=\(passed) failed=\(failed); synthetic AppKit checks, not real display or AX verification")
    return failed == 0 ? 0:1
}
#endif
