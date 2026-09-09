import Foundation

/// A bounded, event-driven resize/readback/position transaction. No idle polling.
public enum SizeFirstPlacement {
    public static func nativeZoomAction(in actions: [String]) -> String? {
        actions.first { $0 == "AXZoomWindow" }
    }
    public static func fitsAtCurrentOrigin(_ actual: Rect?, target: Rect, bounds: Rect) -> Bool {
        guard let actual,actual.valid,target.valid,bounds.valid else { return false }
        return actual.x >= bounds.x-2 && actual.y >= target.y-2 &&
            actual.x+target.width <= bounds.x+bounds.width+2 &&
            actual.y+target.height <= bounds.y+bounds.height+2
    }
    public static func run(target: Rect, allowed: @escaping () -> Bool,
                           resize: @escaping () -> Bool, read: @escaping () -> Rect?,
                           position: @escaping () -> Bool,
                           prepare: (() -> Bool)? = nil, prepared: @escaping (Rect?) -> Bool = { _ in false },
                           schedule: @escaping (@escaping () -> Void) -> Void,
                           completion: @escaping (Rect?, String?) -> Void) {
        guard target.valid, allowed() else { completion(nil, "铺满已取消"); return }
        guard resize() else { completion(read(), "尺寸设置失败，未移动窗口"); return }
        func prepareReadback(_ remaining: Int) {
            guard allowed() else { completion(read(), "原生缩放后已取消");return }
            let actual=read()
            if prepared(actual) {
                guard allowed(),resize() else { completion(read(), "原生缩放后尺寸设置失败");return }
                schedule { verify(3,canPrepare:false) }
            } else if remaining > 0 { schedule { prepareReadback(remaining-1) } }
            else { completion(actual,"原生缩放未提供足够空间，未继续对齐") }
        }
        func verify(_ remaining: Int, canPrepare: Bool) {
            guard allowed() else { completion(read(), "铺满已取消，未移动窗口"); return }
            let actual=read()
            if let actual, actual.valid,
               abs(actual.width-target.width) <= 2, abs(actual.height-target.height) <= 2 {
                guard allowed(), position() else { completion(read(), "位置设置失败或已取消"); return }
                schedule {
                    let final=read()
                    completion(final, final?.close(to:target,tolerance:2) == true ? nil : "铺满未完全到位")
                }
            } else if remaining > 0 {
                schedule { verify(remaining-1,canPrepare:canPrepare) }
            } else if canPrepare,let prepare,allowed(),prepare() {
                schedule { prepareReadback(3) }
            } else {
                completion(read(), "尺寸未达到目标，未执行位置对齐")
            }
        }
        schedule { verify(3,canPrepare:true) }
    }
}
