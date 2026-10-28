import Foundation

struct OperationsSettings: Codable, Equatable {
    var refreshSeconds:Double=0
    var queries=true
    var configuration=true
    var access=true
    var retentionDays=90
    var rotationMB=10
    var rotateBySize=true
    // Zero disables that rotation trigger; size and period can be combined.
    var rotationDays=1
    enum CodingKeys:String,CodingKey {case refreshSeconds,queries,configuration,access,retentionDays,rotationMB,rotationDays,rotateBySize}
    init() {}
    init(from decoder:Decoder) throws {
        let c=try decoder.container(keyedBy:CodingKeys.self)
        refreshSeconds=try c.decodeIfPresent(Double.self,forKey:.refreshSeconds) ?? 0
        queries=try c.decodeIfPresent(Bool.self,forKey:.queries) ?? true
        configuration=try c.decodeIfPresent(Bool.self,forKey:.configuration) ?? true
        access=try c.decodeIfPresent(Bool.self,forKey:.access) ?? true
        retentionDays=try c.decodeIfPresent(Int.self,forKey:.retentionDays) ?? 90
        rotateBySize=try c.decodeIfPresent(Bool.self,forKey:.rotateBySize) ?? true
        rotationMB=try c.decodeIfPresent(Int.self,forKey:.rotationMB) ?? 10
        rotationDays=try c.decodeIfPresent(Int.self,forKey:.rotationDays) ?? 1
        self=self.normalized()
    }
    func interval(for provider:String)->TimeInterval {
        if refreshSeconds>0 {return refreshSeconds}
        return ["codex","claude-passive"].contains(provider) ? 60 : 900
    }
    func normalized()->Self {
        var v=self
        v.refreshSeconds=refreshSeconds==0 ? 0 : refreshSeconds.isFinite ? min(3600,max(60,refreshSeconds)) : 0
        v.retentionDays=min(3650,max(90,retentionDays))
        v.rotationMB=min(100,max(1,rotationMB))
        v.rotationDays=min(30,max(0,rotationDays))
        return v
    }
}
