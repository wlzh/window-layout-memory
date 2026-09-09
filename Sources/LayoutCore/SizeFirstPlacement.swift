import Foundation

/// A bounded, event-driven resize/readback/position transaction. No idle polling.
public enum SizeFirstPlacement {
    public static func run(target: Rect, allowed: @escaping () -> Bool,
                           resize: @escaping () -> Bool, read: @escaping () -> Rect?,
                           position: @escaping () -> Bool,
                           schedule: @escaping (@escaping () -> Void) -> Void,
                           completion: @escaping (Rect?, String?) -> Void) {
        guard target.valid, allowed() else { completion(nil, "铺满已取消"); return }
        guard resize() else { completion(read(), "尺寸设置失败，未移动窗口"); return }
        // Native zoom can strand a window at full width when subsequent resizing fails.
        // Only resize/readback/position is allowed, including on failure and cancellation.
        func verify(_ remaining: Int) {
            guard allowed() else { completion(read(), "铺满已取消，未执行位置对齐"); return }
            let actual=read()
            if let actual, actual.valid,
               abs(actual.width-target.width) <= 2, abs(actual.height-target.height) <= 2 {
                guard allowed(), position() else { completion(read(), "位置设置失败或已取消"); return }
                schedule {
                    let final=read()
                    completion(final, final?.close(to:target,tolerance:2) == true ? nil : "铺满未完全到位")
                }
            } else if remaining > 0 {
                schedule { verify(remaining-1) }
            } else {
                completion(actual, "尺寸未达到目标，未执行位置对齐；未使用原生最大化回退")
            }
        }
        schedule { verify(3) }
    }
}
