import Foundation

/// Interpolate edges, not a translated full-size rectangle. Aligned edges stay fixed
/// at verified checkpoints; AX's separate position/size writes are not atomic.
public enum EdgeAnchoredPlacement {
    public static func frames(from initial: Rect, to target: Rect) -> [Rect]? {
        guard initial.valid,target.valid else { return nil }
        let a=[initial.x,initial.y,initial.x+initial.width,initial.y+initial.height]
        let b=[target.x,target.y,target.x+target.width,target.y+target.height]
        let distance=zip(a,b).map { abs($0-$1) }.max() ?? 0
        guard distance <= 4096 else { return nil }
        let count=max(1,Int(ceil(distance/32)))
        return (1...count).map { index in
            let p=Double(index)/Double(count)
            let e=zip(a,b).map { $0+($1-$0)*p }
            return Rect(e[0],e[1],e[2]-e[0],e[3]-e[1])
        }
    }
    public static func run(initial: Rect,target: Rect,allowed: @escaping ()->Bool,
                           read: @escaping ()->Rect?,resize: @escaping (Rect)->Bool,
                           position: @escaping (Rect)->Bool,
                           schedule: @escaping (@escaping ()->Void)->Void,
                           completion: @escaping (Rect?,String?)->Void) {
        guard let steps=frames(from:initial,to:target),allowed(),
              read()?.close(to:initial,tolerance:2) == true else {
            completion(read(),"边缘调整未开始：几何变化、权限或目标无效");return
        }
        var index=0,previous=initial
        func advance() {
            guard allowed(),read()?.close(to:previous,tolerance:2) == true else {
                completion(read(),"边缘调整已取消：窗口或操作条件变化");return
            }
            let next=steps[index]
            let move=abs(next.x-previous.x)>0.01 || abs(next.y-previous.y)>0.01
            let size=abs(next.width-previous.width)>0.01 || abs(next.height-previous.height)>0.01
            // Only a small leading-edge expansion precedes its matching size write.
            // Contraction resizes first so the old size does not cross screen bounds.
            let leadingExpansion=(next.x < previous.x && next.width > previous.width) ||
                (next.y < previous.y && next.height > previous.height)
            let first=leadingExpansion ? position:resize
            let second=leadingExpansion ? resize:position
            let needsFirst=leadingExpansion ? move:size
            let needsSecond=leadingExpansion ? size:move
            guard !needsFirst || (allowed() && first(next)) else {
                completion(read(),"边缘调整写入失败，已停止");return
            }
            func verify(_ remaining:Int) {
                guard allowed() else { completion(read(),"边缘调整已取消，未继续扩展");return }
                let actual=read()
                if actual?.close(to:next,tolerance:2) == true {
                    previous=next;index+=1
                    if index == steps.count { completion(actual,nil) }
                    else { schedule(advance) }
                } else if remaining > 0 {
                    // Some clients acknowledge a position before their resize constraint
                    // catches up. Retry only this step's size, never advance its origin.
                    let retrySize=leadingExpansion && actual.map { frame in
                        abs(frame.x-next.x)<=2 && abs(frame.y-next.y)<=2 &&
                        frame.width >= min(previous.width,next.width)-2 && frame.width <= max(previous.width,next.width)+2 &&
                        frame.height >= min(previous.height,next.height)-2 && frame.height <= max(previous.height,next.height)+2
                    } == true
                    schedule {
                        if retrySize {
                            if allowed(),read()?.close(to:next,tolerance:2) == true {verify(remaining-1);return}
                            guard allowed(),let actual,read()?.close(to:actual,tolerance:2) == true,resize(next) else {
                                completion(read(),"边缘尺寸重试已取消或失败");return
                            }
                        }
                        verify(remaining-1)
                    }
                }
                else { completion(actual,"边缘调整未达到目标，已停止；未使用原生最大化") }
            }
            var intermediate=previous
            if leadingExpansion {intermediate.x=next.x;intermediate.y=next.y}
            else {intermediate.width=next.width;intermediate.height=next.height}
            func verifyFirst(_ remaining:Int) {
                guard allowed() else {completion(read(),"边缘调整已取消，未继续扩展");return}
                let actual=read()
                if !needsFirst || actual?.close(to:intermediate,tolerance:2) == true || actual?.close(to:next,tolerance:2) == true {
                    guard !needsSecond || (allowed() && second(next)) else {
                        completion(read(),"边缘调整中止，可能已部分调整；不回滚用户操作");return
                    }
                    verify(3)
                } else if remaining > 0 {schedule {verifyFirst(remaining-1)}}
                else {completion(actual,"边缘首个写入未到位，未继续调整")}
            }
            // Let asynchronous native window geometry settle before the paired write.
            if needsFirst && needsSecond {schedule {verifyFirst(3)}}
            else {verifyFirst(3)}
        }
        advance()
    }
}
