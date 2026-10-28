import Foundation
import Darwin

final class InsightProxy {
    let port:Int
    private let process:InsightProcess
    private let input:Pipe,output:Pipe
    private init(port:Int,process:InsightProcess,input:Pipe,output:Pipe){self.port=port;self.process=process;self.input=input;self.output=output}
    static func hosts(for provider:String)->[String] {
        switch provider {
        case "kimi":return ["api.kimi.com","auth.kimi.com"]
        case "zai":return ["api.z.ai"]
        default:return []
        }
    }
    static func nodeCandidates(environment:[String:String],home:String)->[String] {
        var paths:[String]=[]
        if let explicit=environment["PLANMETER_NODE_PATH"],!explicit.isEmpty {return explicit.hasPrefix("/") && !explicit.contains("\n") && !explicit.contains("\0") ? [explicit] : []}
        paths += (environment["PATH"] ?? "").split(separator:":").filter{$0.hasPrefix("/")}.map{String($0)+"/node"}
        paths += ["/opt/homebrew/bin/node","/usr/local/bin/node",home+"/.volta/bin/node",home+"/.local/share/mise/shims/node"]
        for base in [home+"/.nvm/versions/node",home+"/.local/share/mise/installs/node"] {
            let versions=(try? FileManager.default.contentsOfDirectory(atPath:base)) ?? []
            paths += versions.sorted{$0.compare($1,options:.numeric) == .orderedDescending}.map{base+"/"+$0+"/bin/node"}
        }
        var seen=Set<String>();return paths.filter{!$0.contains("\n") && !$0.contains("\0") && seen.insert($0).inserted}
    }
    static func start(hosts:[String],directory:URL,candidates supplied:[String]?=nil)throws->InsightProxy {
        let candidates=(supplied ?? nodeCandidates(environment:ProcessInfo.processInfo.environment,home:FileManager.default.homeDirectoryForCurrentUser.path)).filter{FileManager.default.isExecutableFile(atPath:$0)}
        for node in candidates {
            do {return try launch(node:node,hosts:hosts,directory:directory)}
            catch InsightFailure.nodeRequired {continue}
            catch InsightFailure.unavailable {continue}
        }
        throw InsightFailure.nodeRequired
    }
    private static func launch(node:String,hosts:[String],directory:URL)throws->InsightProxy {
        guard let script=Bundle.main.url(forResource:"insight-connect-proxy",withExtension:"js"),let hostList=String(data:try JSONEncoder().encode(hosts),encoding:.utf8) else{throw InsightFailure.unavailable}
        let process=InsightProcess(),input=Pipe(),output=Pipe(),null=FileHandle(forWritingAtPath:"/dev/null")!
        defer{try? null.close()}
        process.executableURL=URL(fileURLWithPath:node);process.arguments=[script.path,hostList]
        process.environment=InsightRunner.environment(ProcessInfo.processInfo.environment,binary:node)
        process.currentDirectoryURL=directory;process.standardInput=input;process.standardOutput=output;process.standardError=null
        try process.run()
        var buffer=Data();let deadline=Date().addingTimeInterval(6)
        do {
            while Date()<deadline {
                var fd=pollfd(fd:output.fileHandleForReading.fileDescriptor,events:Int16(POLLIN),revents:0)
                if poll(&fd,1,100)>0 {
                    var bytes=[UInt8](repeating:0,count:1024);let size=Darwin.read(fd.fd,&bytes,bytes.count)
                    guard size>0 else{throw InsightFailure.unavailable};buffer.append(contentsOf:bytes.prefix(size))
                    guard buffer.count<=4096 else{throw InsightFailure.invalidResponse}
                    if let end=buffer.firstIndex(of:10) {
                        guard let value=(try? JSONSerialization.jsonObject(with:Data(buffer[..<end]))) as? [String:Any] else{throw InsightFailure.invalidResponse}
                        if let error=value["error"] as? String {throw error=="node_version" ? InsightFailure.nodeRequired : InsightFailure.proxyUnavailable}
                        guard let port=value["port"] as? Int,(1024...65535).contains(port),let major=value["nodeMajor"] as? Int,major>=18 else{throw InsightFailure.invalidResponse}
                        return InsightProxy(port:port,process:process,input:input,output:output)
                    }
                }
            }
            throw InsightFailure.timeout
        }catch{process.killGroup();process.waitUntilExit();throw error}
    }
    func cancel(){process.terminate()}
    func stop(){
        try? input.fileHandleForWriting.close();process.terminate()
        let deadline=Date().addingTimeInterval(1)
        while process.isRunning && Date()<deadline {Thread.sleep(forTimeInterval:0.01)}
        process.killGroup();process.waitUntilExit();try? output.fileHandleForReading.close()
    }
}
