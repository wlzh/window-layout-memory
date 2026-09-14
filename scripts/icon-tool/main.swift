import AppKit

let sizes:[(String,Int)] = [("icon_16x16.png",16),("icon_16x16@2x.png",32),("icon_32x32.png",32),("icon_32x32@2x.png",64),("icon_128x128.png",128),("icon_128x128@2x.png",256),("icon_256x256.png",256),("icon_256x256@2x.png",512),("icon_512x512.png",512),("icon_512x512@2x.png",1024)]
guard CommandLine.arguments.count == 3,["generate","check"].contains(CommandLine.arguments[1]) else { fatalError("usage: icon-tool generate|check ICONSET") }
let directory=URL(fileURLWithPath:CommandLine.arguments[2],isDirectory:true)
do {
    if CommandLine.arguments[1] == "generate" {
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        for (name,size) in sizes {
            guard let data=BrandIcon.bitmap(pixels:size).representation(using:.png,properties:[:]) else { fatalError("PNG encoding failed") }
            try data.write(to:directory.appendingPathComponent(name),options:.atomic)
        }
    }
    for (name,size) in sizes {
        guard let rep=NSBitmapImageRep(data:try Data(contentsOf:directory.appendingPathComponent(name))),
              rep.pixelsWide == size,rep.pixelsHigh == size,rep.hasAlpha,
              let corner=rep.colorAt(x:0,y:0),corner.alphaComponent < 0.01,
              let center=rep.colorAt(x:size/2,y:size/2),center.alphaComponent > 0.99 else { fatalError("invalid icon representation: \(name)") }
        if size >= 128 {
            guard rep.colorAt(x:size/6,y:size/8)!.alphaComponent > 0.99,
                  rep.colorAt(x:size*5/6,y:size*7/8)!.alphaComponent > 0.99 else { fatalError("background gradient does not cover icon: \(name)") }
        }
    }
    print("ICON_REPRESENTATIONS passed=\(sizes.count) failed=0")
} catch { fputs("Icon tool failed: \(error)\n",stderr);exit(1) }
