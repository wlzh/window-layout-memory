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
            guard !needsSecond || (allowed() && second(next)) else {
                completion(read(),"边缘调整中止，可能已部分调整；不回滚用户操作");return
            }
            func verify(_ remaining:Int) {
                guard allowed() else { completion(read(),"边缘调整已取消，未继续扩展");return }
                let actual=read()
                if actual?.close(to:next,tolerance:2) == true {
                    previous=next;index+=1
                    if index == steps.count { completion(actual,nil) }
                    else { schedule(advance) }
                } else if remaining > 0 { schedule { verify(remaining-1) } }
                else { completion(actual,"边缘调整未达到目标，已停止；未使用原生最大化") }
            }
            verify(3)
        }
        advance()
    }
}
