import Foundation
import Darwin

final class ClaudeCLIProbe {
    let binary:String,directory:URL
    let timeout:TimeInterval
    private let lock=NSLock()
    private var process:InsightProcess?
    private var cancelled=false
    init(binary:String,directory:URL,timeout:TimeInterval=35){self.binary=binary;self.directory=directory;self.timeout=timeout}
    func cancel(){lock.lock();cancelled=true;let process=process;lock.unlock();process?.terminate()}
    private var stopped:Bool {lock.lock();defer{lock.unlock()};return cancelled}
    static func arguments()->[String] {
        ["/usage","--tools","","--strict-mcp-config","--mcp-config","{\"mcpServers\":{}}","--setting-sources","","--settings","{\"disableAllHooks\":true,\"remoteControlAtStartup\":false,\"disableDeepLinkRegistration\":\"disable\"}","--permission-mode","dontAsk","--no-chrome"]
    }
    static func trustKey(screen:String,directory:URL)->String? {
        let normalized=ClaudeCLIUsageParser.normalized(screen)
        let full=ClaudeCLIUsageParser.normalized(directory.path)
        let home=FileManager.default.homeDirectoryForCurrentUser.path
        let abbreviated=ClaudeCLIUsageParser.normalized(directory.path.replacingOccurrences(of:home,with:"~"))
        guard normalized.contains(full) || normalized.contains(abbreviated) else{return nil}
        let lines=screen.components(separatedBy:.newlines)
        guard let yes=lines.firstIndex(where:{ClaudeCLIUsageParser.normalized($0).contains("yes,itrustthisfolder")}),
              let selected=lines.indices.first(where:{$0>=max(0,yes-3) && $0<=min(lines.count-1,yes+3) && lines[$0].contains("❯")}) else{return nil}
        if yes==selected {return "\r"}
        return selected<yes ? "\u{1b}[B" : "\u{1b}[A"
    }
    func read(allowTrust:Bool=false)throws->ClaudeQuotaReading {
        guard binary.hasPrefix("/"),!stopped else{throw QuotaError.message("Consulta Claude cancelada")}
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
        var attributes=stat()
        guard lstat(directory.path,&attributes)==0,(attributes.st_mode&S_IFMT)==S_IFDIR,attributes.st_uid==getuid(),(attributes.st_mode&0o022)==0 else{throw QuotaError.message("Pasta de consulta Claude indisponível")}
        if allowTrust {
            guard (try FileManager.default.contentsOfDirectory(atPath:directory.path)).isEmpty else{throw QuotaError.message("A confirmação de confiança requer a pasta exclusiva vazia")}
        }
        var master:Int32 = -1,slave:Int32 = -1,window=winsize(ws_row:80,ws_col:160,ws_xpixel:0,ws_ypixel:0)
        guard openpty(&master,&slave,nil,nil,&window)==0 else{throw QuotaError.message("Terminal Claude indisponível")}
        let terminal=FileHandle(fileDescriptor:slave,closeOnDealloc:true)
        var masterOpen=true
        defer{if masterOpen {close(master)};try? terminal.close()}
        guard fcntl(master,F_SETFL,O_NONBLOCK)==0 else{throw QuotaError.message("Terminal Claude indisponível")}
        let child=InsightProcess();child.executableURL=URL(fileURLWithPath:binary);child.arguments=Self.arguments();child.currentDirectoryURL=directory;child.terminal=terminal
        var env=InsightRunner.environment(ProcessInfo.processInfo.environment,binary:binary)
        env["PWD"]=directory.path;env["TERM"]="xterm-256color";env["LANG"]="en_US.UTF-8";env["LC_ALL"]="en_US.UTF-8"
        env["DISABLE_AUTOUPDATER"]="1";env["DISABLE_TELEMETRY"]="1";env["DISABLE_ERROR_REPORTING"]="1"
        child.environment=env
        lock.lock();if cancelled {lock.unlock();throw QuotaError.message("Consulta Claude cancelada")}
        do {try child.run();process=child;lock.unlock()}catch{lock.unlock();throw QuotaError.message("Não foi possível iniciar Claude Code")}
        defer {
            // Close the PTY before waiting; an exiting terminal process can otherwise wait for its reader.
            close(master);masterOpen=false;child.terminate()
            let deadline=Date().addingTimeInterval(1)
            while child.isRunning && Date()<deadline {Thread.sleep(forTimeInterval:0.01)}
            child.killGroup()
            let reapDeadline=Date().addingTimeInterval(1)
            while child.isRunning && Date()<reapDeadline {Thread.sleep(forTimeInterval:0.01)}
            lock.lock();process=nil;lock.unlock()
        }
        func status(_ value:String,retryAt:Date?=nil)->ClaudeQuotaReading {
            var snapshot=QuotaSnapshot(queriedAt:Date(),windows:[]);snapshot.provider="claude";snapshot.sourceHost="claude-code-cli"
            return ClaudeQuotaReading(snapshot:snapshot,status:value,nextAttemptAt:retryAt ?? Date().addingTimeInterval(60))
        }
        var data=Data(),stable:String?,stableSince=Date(),trustActions=0,lastTrust=Date.distantPast
        let deadline=Date().addingTimeInterval(timeout)
        while Date()<deadline {
            if stopped {throw QuotaError.message("Consulta Claude cancelada")}
            var descriptor=pollfd(fd:master,events:Int16(POLLIN),revents:0)
            if poll(&descriptor,1,100)>0 {
                var bytes=[UInt8](repeating:0,count:16384)
                let size=Darwin.read(master,&bytes,bytes.count)
                if size>0 {
                    let chunk=Data(bytes.prefix(size));data.append(chunk)
                    guard data.count<=1_048_576 else{throw QuotaError.message("Tela Claude excedeu o limite")}
                    if chunk.range(of:Data("\u{1b}[6n".utf8)) != nil {let answer=Array("\u{1b}[1;1R".utf8);_ = answer.withUnsafeBytes{Darwin.write(master,$0.baseAddress,$0.count)}}
                } else if size==0 {break}
            }
            var terminal=ClaudeTerminalScreen();terminal.render(data);let screen=terminal.text
            if ClaudeCLIUsageParser.requiresTrust(screen) {
                guard allowTrust else{return status("setup_required")}
                guard trustActions<4 else{return status("setup_required")}
                if Date().timeIntervalSince(lastTrust)>0.5,let key=Self.trustKey(screen:screen,directory:directory) {
                    let bytes=Array(key.utf8);_=bytes.withUnsafeBytes{Darwin.write(master,$0.baseAddress,$0.count)};trustActions += 1;lastTrust=Date()
                }
                continue
            }
            let lower=screen.lowercased()
            if lower.contains("sign in") || lower.contains("please log in") {return status("unauthorized")}
            if let state=ClaudeCLIUsageParser.screenStatus(screen) {
                stable=nil
                if state=="refreshing" {continue}
                return status(state,retryAt:state=="rate_limited" ? ClaudeCLIUsageParser.retryDate(screen,now:Date()) : nil)
            }
            if let reading=try? ClaudeCLIUsageParser.parse(screen) {
                let signature=reading.snapshot.windows.map{"\($0.name):\($0.remaining ?? -1):\($0.reset ?? -1)"}.joined(separator:"|")
                if stable != signature {stable=signature;stableSince=Date()}
                if Date().timeIntervalSince(stableSince)>=0.7 {return reading}
            }
            if !child.isRunning {break}
        }
        return status("unavailable")
    }
}
