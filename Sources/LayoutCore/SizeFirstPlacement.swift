import Foundation

/// A bounded placement transaction. Both policies stop on failure without native zoom.
public enum SizeFirstPlacement {
    public static func run(target: Rect, positionFirst: Bool = false, allowed: @escaping () -> Bool,
                           resize: @escaping () -> Bool, read: @escaping () -> Rect?,
                           position: @escaping () -> Bool,
                           schedule: @escaping (@escaping () -> Void) -> Void,
                           completion: @escaping (Rect?, String?) -> Void) {
        guard target.valid, allowed() else { completion(nil, "铺满已取消"); return }
        if positionFirst {
            guard position() else { completion(read(), "位置设置失败，未继续调整尺寸"); return }
            guard allowed() else { completion(read(), "铺满已取消，未继续调整尺寸"); return }
        }
        guard resize() else { completion(read(), positionFirst ? "尺寸设置失败，已停止调整" : "尺寸设置失败，未移动窗口"); return }
        // Native zoom can strand a window at full width when subsequent resizing fails.
        // No zoom or rollback is used; either can overwrite a concurrent user adjustment.
        func verify(_ remaining: Int) {
            guard allowed() else { completion(read(), positionFirst ? "铺满已取消，已停止调整" : "铺满已取消，未执行位置对齐"); return }
            let actual=read()
            if let actual, actual.valid,
               abs(actual.width-target.width) <= 2, abs(actual.height-target.height) <= 2 {
                guard allowed(), positionFirst || position() else { completion(read(), "位置设置失败或已取消"); return }
                schedule {
                    guard allowed() else { completion(read(), "铺满已取消，已停止调整"); return }
                    let final=read()
                    completion(final, final?.close(to:target,tolerance:2) == true ? nil : "铺满未完全到位")
                }
            } else if remaining > 0 {
                schedule { verify(remaining-1) }
            } else {
                completion(actual, positionFirst ? "尺寸未达到目标，已停止调整；未使用原生最大化回退" : "尺寸未达到目标，未执行位置对齐；未使用原生最大化回退")
            }
        }
        schedule { verify(3) }
    }
}
