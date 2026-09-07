import AppKit
import ApplicationServices
import LayoutCore

func displaysNow() -> Topology {
    let screens = NSScreen.screens
    let height = screens.first?.frame.height ?? 0
    func rect(_ r: CGRect) -> Rect { Rect(r.minX,height-r.maxY,r.width,r.height) }
    return Topology(screens.compactMap { s in
        guard let number=s.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
        let id=number.uint32Value
        guard let raw=CGDisplayCreateUUIDFromDisplayID(id) else { return nil }
        let uuid=CFUUIDCreateString(nil,raw.takeRetainedValue()) as String
        return Display(id:uuid,name:s.localizedName,frame:rect(s.frame),visible:rect(s.visibleFrame),
                       scale:s.backingScaleFactor,rotation:CGDisplayRotation(id),primary:CGDisplayIsMain(id) != 0,
                       mirrored:CGDisplayMirrorsDisplay(id) != kCGNullDirectDisplay)
    })
}

struct AXRecord {
    var token: String, app: String, pid: pid_t, element: AXUIElement
    var identity: WindowIdentity, frame: Rect
    var focused: Bool, usable: Bool
    var live: LiveWindow { LiveWindow(token:token,identity:identity,frame:frame,eligible:usable && focused) }
}
struct ScanResult { var pid: pid_t, records: [AXRecord], error: String? }

final class AXService {
    private let queue=DispatchQueue(label:"uk.869hr.WindowLayoutMemory.ax",qos:.utility)
    private var observers: [pid_t:AXObserver] = [:]
    private var watched: [pid_t:[AXUIElement]] = [:]
    private var cache: [pid_t:[AXRecord]] = [:]
    private var serial: UInt64 = 0
    var onEvent: ((pid_t,String)->Void)?
    private let windowEvents = [kAXWindowMovedNotification,kAXWindowResizedNotification,kAXUIElementDestroyedNotification,
                                kAXTitleChangedNotification,kAXWindowMiniaturizedNotification,kAXWindowDeminiaturizedNotification]
    private let appEvents = [kAXWindowCreatedNotification,kAXFocusedWindowChangedNotification,kAXApplicationActivatedNotification,
                             kAXApplicationDeactivatedNotification]
    private func value(_ e: AXUIElement,_ name: String) -> CFTypeRef? {
        var result: CFTypeRef?
        return AXUIElementCopyAttributeValue(e,name as CFString,&result) == .success ? result : nil
    }
    private func geometry(_ e: AXUIElement) -> Rect? {
        guard let p=value(e,kAXPositionAttribute), let s=value(e,kAXSizeAttribute),
              CFGetTypeID(p)==AXValueGetTypeID(),CFGetTypeID(s)==AXValueGetTypeID() else { return nil }
        var point=CGPoint.zero; var size=CGSize.zero
        guard AXValueGetValue(p as! AXValue,.cgPoint,&point),AXValueGetValue(s as! AXValue,.cgSize,&size) else { return nil }
        let r=Rect(point.x,point.y,size.width,size.height); return r.valid ? r : nil
    }
    private func attach(_ pid: pid_t, application: AXUIElement) {
        guard observers[pid] == nil else { return }
        var observer: AXObserver?
        let callback: AXObserverCallback = { _, element, name, context in
            guard let context else { return }
            let service=Unmanaged<AXService>.fromOpaque(context).takeUnretainedValue()
            var pid: pid_t=0
            AXUIElementGetPid(element,&pid)
            service.onEvent?(pid,name as String)
        }
        guard AXObserverCreate(pid,callback,&observer) == .success,let observer else { return }
        observers[pid]=observer
        let context=Unmanaged.passUnretained(self).toOpaque()
        for event in appEvents { _=AXObserverAddNotification(observer,application,event as CFString,context) }
        CFRunLoopAddSource(CFRunLoopGetMain(),AXObserverGetRunLoopSource(observer),.commonModes)
    }
    func detach(_ pid: pid_t) {
        queue.async { [self] in
            if let observer=observers.removeValue(forKey:pid) {
                CFRunLoopRemoveSource(CFRunLoopGetMain(),AXObserverGetRunLoopSource(observer),.commonModes)
            }
            watched[pid]=nil; cache[pid]=nil
        }
    }
    func scan(pid: pid_t, bundle: String, name: String, front: Bool, hidden: Bool, completion: @escaping (ScanResult)->Void) {
        queue.async { [self] in
            guard AXIsProcessTrusted() else {
                DispatchQueue.main.async { completion(ScanResult(pid:pid,records:[],error:"辅助功能未授权")) }; return
            }
            let app=AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(app,0.15)
            attach(pid,application:app)
            var raw: CFTypeRef?
            let status=AXUIElementCopyAttributeValue(app,kAXWindowsAttribute as CFString,&raw)
            guard status == .success, let windows=raw as? [AXUIElement] else {
                DispatchQueue.main.async { completion(ScanResult(pid:pid,records:[],error:"窗口读取失败 AX=\(status.rawValue)")) }; return
            }
            let start=ProcessInfo.processInfo.systemUptime
            let focus=value(app,kAXFocusedWindowAttribute)
            var records: [AXRecord]=[]
            var issues: [String]=[]
            if observers[pid] == nil { issues.append("应用不支持观察者；只能激活或手动刷新") }
            let old=cache[pid] ?? []
            if let observer=observers[pid] {
                for e in watched[pid] ?? [] { for event in windowEvents { AXObserverRemoveNotification(observer,e,event as CFString) } }
            }
            watched[pid]=[]
            for e in windows.prefix(100) {
                if ProcessInfo.processInfo.systemUptime-start > 1 { issues.append("应用读取超过批次预算，结果不完整"); break }
                AXUIElementSetMessagingTimeout(e,0.15)
                guard value(e,kAXSubroleAttribute) as? String == kAXStandardWindowSubrole else { continue }
                guard let frame=geometry(e) else { issues.append("窗口几何不可读"); continue }
                let minimized=value(e,kAXMinimizedAttribute) as? Bool ?? true
                let fullscreen=value(e,"AXFullScreen") as? Bool ?? false
                let identity=WindowIdentity(bundle:bundle,title:value(e,kAXTitleAttribute) as? String ?? "",
                                            document:value(e,kAXDocumentAttribute) as? String ?? "",
                                            identifier:value(e,kAXIdentifierAttribute) as? String ?? "")
                serial &+= 1
                let token=old.first(where:{ CFEqual($0.element,e) })?.token ?? "\(pid):\(serial)"
                let focused=front && focus.map { CFEqual($0,e) } == true
                records.append(AXRecord(token:token,app:name,pid:pid,element:e,identity:identity,frame:frame,
                                        focused:focused,usable:!hidden && !minimized && !fullscreen))
                if let observer=observers[pid] {
                    for event in windowEvents {
                        let result=AXObserverAddNotification(observer,e,event as CFString,Unmanaged.passUnretained(self).toOpaque())
                        if result != .success && result != .notificationAlreadyRegistered { issues.append("部分窗口通知不可用 AX=\(result.rawValue)") }
                    }
                    watched[pid,default:[]].append(e)
                }
            }
            if windows.count > 100 { issues.append("超过100窗口上限") }
            cache[pid]=records
            let error=Set(issues).sorted().joined(separator:"；")
            DispatchQueue.main.async { completion(ScanResult(pid:pid,records:records,error:error.isEmpty ? nil:error)) }
        }
    }
    func move(_ record: AXRecord, to target: Rect, allowed: @escaping ()->Bool, completion: @escaping (Rect?,String?)->Void) {
        queue.async { [self] in
            func permitted() -> Bool { DispatchQueue.main.sync { allowed() } }
            guard AXIsProcessTrusted(),permitted() else { DispatchQueue.main.async { completion(nil,"操作已取消或权限缺失") }; return }
            let e=record.element
            AXUIElementSetMessagingTimeout(e,0.15)
            let application=AXUIElementCreateApplication(record.pid)
            AXUIElementSetMessagingTimeout(application,0.15)
            guard let focused=value(application,kAXFocusedWindowAttribute),CFEqual(focused,e),
                  geometry(e)?.close(to:record.frame,tolerance:4) == true else {
                DispatchQueue.main.async { completion(nil,"窗口焦点或几何已变化，已取消") }; return
            }
            var positionSettable=DarwinBoolean(false), sizeSettable=DarwinBoolean(false)
            guard AXUIElementIsAttributeSettable(e,kAXPositionAttribute as CFString,&positionSettable) == .success,
                  AXUIElementIsAttributeSettable(e,kAXSizeAttribute as CFString,&sizeSettable) == .success,
                  positionSettable.boolValue,sizeSettable.boolValue else { DispatchQueue.main.async { completion(nil,"窗口不允许修改位置或尺寸") }; return }
            guard value(e,kAXMinimizedAttribute) as? Bool == false,
                  value(e,"AXFullScreen") as? Bool != true else { DispatchQueue.main.async { completion(nil,"窗口已最小化或全屏") }; return }
            var point=CGPoint(x:target.x,y:target.y),size=CGSize(width:target.width,height:target.height)
            var errors: [Int32]=[]
            // Re-check cancellation between mutations, not just once per batch.
            for key in [kAXPositionAttribute,kAXSizeAttribute,kAXPositionAttribute] {
                guard permitted(),let focused=value(application,kAXFocusedWindowAttribute),CFEqual(focused,e) else { errors.append(-1); break }
                let v=key == kAXSizeAttribute ? AXValueCreate(.cgSize,&size)! : AXValueCreate(.cgPoint,&point)!
                let status=AXUIElementSetAttributeValue(e,key as CFString,v)
                if status != .success { errors.append(status.rawValue) }
            }
            let actual=geometry(e)
            let error = errors.isEmpty && actual?.close(to:target) == true ? nil : "恢复未完全到位；AX=\(errors)"
            DispatchQueue.main.async { completion(actual,error) }
        }
    }
}
