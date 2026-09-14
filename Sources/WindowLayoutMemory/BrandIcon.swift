import AppKit

enum BrandIcon {
    static let image: NSImage = {
        if let url=Bundle.main.url(forResource:"AppIcon",withExtension:"icns"),let image=NSImage(contentsOf:url) { return image }
        let image=NSImage(size:NSSize(width:256,height:256))
        image.addRepresentation(bitmap(pixels:256))
        return image
    }()

    static func bitmap(pixels: Int) -> NSBitmapImageRep {
        precondition(pixels > 0 && pixels <= 1024)
        let rep=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:pixels,pixelsHigh:pixels,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
        let context=NSGraphicsContext(bitmapImageRep:rep)!.cgContext
        context.clear(CGRect(x:0,y:0,width:pixels,height:pixels))
        context.scaleBy(x:CGFloat(pixels)/1024,y:CGFloat(pixels)/1024)
        func color(_ r:CGFloat,_ g:CGFloat,_ b:CGFloat)->CGColor { CGColor(red:r,green:g,blue:b,alpha:1) }
        func rounded(_ rect:CGRect,_ radius:CGFloat,_ fill:CGColor) {
            context.setFillColor(fill)
            context.addPath(CGPath(roundedRect:rect,cornerWidth:radius,cornerHeight:radius,transform:nil));context.fillPath()
        }
        let background=CGPath(roundedRect:CGRect(x:64,y:64,width:896,height:896),cornerWidth:196,cornerHeight:196,transform:nil)
        context.saveGState();context.addPath(background);context.clip()
        let gradient=CGGradient(colorsSpace:CGColorSpaceCreateDeviceRGB(),colors:[color(0.04,0.16,0.23),color(0.04,0.43,0.47)] as CFArray,locations:[0,1])!
        context.drawLinearGradient(gradient,start:CGPoint(x:180,y:900),end:CGPoint(x:850,y:100),options:[.drawsBeforeStartLocation,.drawsAfterEndLocation])
        context.restoreGState()
        context.saveGState()
        context.setShadow(offset:CGSize(width:0,height:-16),blur:30,color:CGColor(gray:0,alpha:0.22))
        rounded(CGRect(x:174,y:256,width:676,height:526),60,color(0.94,0.97,0.95))
        context.restoreGState()
        for x in [226,260,294] {
            context.setFillColor(color(0.27,0.47,0.49));context.fillEllipse(in:CGRect(x:x,y:724,width:14,height:14))
        }
        rounded(CGRect(x:214,y:296,width:232,height:380),24,color(0.05,0.42,0.46))
        rounded(CGRect(x:476,y:501,width:334,height:175),24,color(0.96,0.68,0.29))
        rounded(CGRect(x:476,y:296,width:334,height:175),24,color(0.45,0.65,0.67))
        // A small return mark anchors the memory/restore meaning without lettering.
        context.setStrokeColor(color(0.87,0.96,0.94));context.setLineWidth(27);context.setLineCap(.round);context.setLineJoin(.round)
        context.move(to:CGPoint(x:596,y:184));context.addLine(to:CGPoint(x:436,y:184));context.addLine(to:CGPoint(x:436,y:211));context.strokePath()
        context.move(to:CGPoint(x:406,y:184));context.addLine(to:CGPoint(x:436,y:214));context.addLine(to:CGPoint(x:466,y:184));context.strokePath()
        return rep
    }
}
