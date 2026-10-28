import AppKit

func captureFixturePreview(_ view:NSView,name:String) {
    guard Runtime.isTest,ProcessInfo.processInfo.environment["PLANMETER_CAPTURE_FIXTURES"]=="1" else{return}
    view.layoutSubtreeIfNeeded();view.displayIfNeeded()
    guard let bitmap=view.bitmapImageRepForCachingDisplay(in:view.bounds) else{fatalError("Fixture bitmap unavailable")}
    view.cacheDisplay(in:view.bounds,to:bitmap)
    guard let data=bitmap.representation(using:.png,properties:[:]) else{fatalError("Fixture PNG unavailable")}
    let directory=URL(fileURLWithPath:"/private/tmp/planmeter-fixtures")
    try! FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
    try! data.write(to:directory.appendingPathComponent(name+".png"),options:.atomic)
}
