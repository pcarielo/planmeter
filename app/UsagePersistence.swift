import Foundation

final class UsagePersistence {
    private let queue=DispatchQueue(label:"PlanMeter.usage-persistence",qos:.utility)
    private var pending:DispatchWorkItem?
    private var latest:UsageTimeline?
    private var completion:((Bool)->Void)?
    private var version=0
    private let write:(Data)throws->Void
    init(file:URL,write:((Data)throws->Void)?=nil) {
        self.write=write ?? {data in
            try FileManager.default.createDirectory(at:file.deletingLastPathComponent(),withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
            try data.write(to:file,options:.atomic)
            try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:file.path)
        }
    }
    func submit(_ value:UsageTimeline,completion:@escaping(Bool)->Void) {
        queue.async {
            self.latest=value;self.completion=completion;self.version += 1
            let token=self.version
            self.pending?.cancel()
            let task=DispatchWorkItem{[weak self] in
                guard let self=self,self.version==token else{return};self.persist()
            }
            self.pending=task;self.queue.asyncAfter(deadline:.now()+2,execute:task)
        }
    }
    private func persist() {
        pending=nil
        guard let value=latest else{return}
        let callback=completion
        do {try write(JSONEncoder().encode(value));latest=nil;completion=nil;callback?(true)}
        catch {callback?(false)}
    }
    func flush(){queue.sync{pending?.cancel();pending=nil;version += 1;persist()}}
}
func runUsagePersistenceTests() {
    var writes=0,results:[Bool]=[]
    let path=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let store=UsagePersistence(file:path,write:{_ in writes += 1})
    for _ in 0..<100 {store.submit(UsageTimeline()){results.append($0)}}
    store.flush()
    guard writes==1,results==[true] else{fatalError("FAIL timeline persistence: updates did not coalesce")}
    struct Failure:Error{}
    var attempts=0
    let retry=UsagePersistence(file:path,write:{_ in attempts += 1;if attempts==1 {throw Failure()}})
    retry.submit(UsageTimeline()){results.append($0)};retry.flush();retry.flush()
    guard attempts==2,results.suffix(2)==[false,true] else{fatalError("FAIL timeline persistence: latest snapshot lost after failure")}
    print("PASS Usage persistence: coalescing, flush and retry; no real files")
}
