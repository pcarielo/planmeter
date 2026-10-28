import Foundation
import Darwin

enum AuditCategory:String,CaseIterable,Codable {case queries,configuration,access
    var title:String {switch self {case .queries:return "Consultas";case .configuration:return "Configurações";case .access:return "Acessos e chaves"}}
}
enum AuditProvider:String,Codable {case app,codex,claude,zai,kimi,grok}
enum AuditAction:String,Codable {case query,readCache,settingsChanged,saveKey,removeKey,authorize}
enum AuditOutcome:String,Codable {case started,success,failure,cancelled}
// No free-text fields: credentials, raw provider errors, prompts and paths cannot enter an event.
private struct AuditEvent:Codable {
    let timestamp:Double
    let provider:AuditProvider
    let action:AuditAction
    let outcome:AuditOutcome
}
final class AuditLog {
    let directory:URL
    private let lock=NSLock()
    private(set) var lastError:String?
    private(set) var warning:String?
    var statusMessage:String? {lastError ?? warning}
    var availableBytes:(URL)->Int64? = {url in
        (try? FileManager.default.attributesOfFileSystem(forPath:url.path)[.systemFreeSize] as? NSNumber)?.int64Value
    }
    var simulateWriteFailure=false
    init(directory:URL){self.directory=directory}
    func url(_ category:AuditCategory)->URL {directory.appendingPathComponent(category.rawValue+".jsonl")}
    @discardableResult func record(_ category:AuditCategory,provider:AuditProvider,action:AuditAction,outcome:AuditOutcome,settings:OperationsSettings,now:Date=Date())->Bool {
        lock.lock();defer{lock.unlock()}
        let options=settings.normalized()
        guard category != .queries || options.queries,
              category != .configuration || options.configuration,
              category != .access || options.access else{return true}
        warning=availableBytes(directory.deletingLastPathComponent()).map{$0<104_857_600 ? "Pouco espaço em disco. Os registros dentro da retenção serão preservados." : nil} ?? nil
        do {
            if simulateWriteFailure {throw StorageFailure()}
            try append(category,event:AuditEvent(timestamp:now.timeIntervalSince1970,provider:provider,action:action,outcome:outcome),options:options,now:now)
            lastError=nil;return true
        } catch {lastError="Não foi possível gravar os registros locais. Confira espaço e permissões da pasta de logs.";return false}
    }
    private struct StorageFailure:Error {}
    private func append(_ category:AuditCategory,event:AuditEvent,options:OperationsSettings,now:Date)throws {
        let fm=FileManager.default
        // Refuse a redirected log directory, including symlink ancestors.
        guard directory.standardizedFileURL.path == directory.resolvingSymlinksInPath().standardizedFileURL.path else {throw StorageFailure()}
        try fm.createDirectory(at:directory,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
        let dir=open(directory.path,O_RDONLY|O_DIRECTORY|O_NOFOLLOW)
        guard dir>=0 else {throw StorageFailure()};defer{close(dir)}
        var ds=stat();guard fstat(dir,&ds)==0,ds.st_uid==getuid(),fchmod(dir,0o700)==0 else {throw StorageFailure()}
        let name=category.rawValue+".jsonl"
        var fd=openat(dir,name,O_RDWR|O_APPEND|O_CREAT|O_NOFOLLOW,0o600)
        guard fd>=0 else{throw StorageFailure()};defer{if fd>=0 {close(fd)}}
        func validate(_ handle:Int32)throws->stat {
            var s=stat()
            guard fstat(handle,&s)==0,(s.st_mode & S_IFMT)==S_IFREG,s.st_uid==getuid(),s.st_nlink==1,fchmod(handle,0o600)==0 else{throw StorageFailure()}
            return s
        }
        let s=try validate(fd)
        var bytes=try JSONEncoder().encode(event);bytes.append(10)
        var first=[UInt8](repeating:0,count:2048)
        let count=pread(fd,&first,first.count,0)
        let firstLine=Data(first.prefix(max(0,count))).split(separator:10).first
        let started=firstLine.flatMap{try? JSONDecoder().decode(AuditEvent.self,from:Data($0)).timestamp}
        let due=options.rotationDays>0 && started.map{now.timeIntervalSince1970-$0>=Double(options.rotationDays)*86400} == true
        if s.st_size>0 && ((options.rotateBySize && s.st_size+Int64(bytes.count)>Int64(options.rotationMB)*1_048_576) || due) {
            let archive=category.rawValue+"-"+String(Int64(now.timeIntervalSince1970))+"-"+UUID().uuidString+".jsonl"
            guard renameat(dir,name,dir,archive)==0 else{throw StorageFailure()}
            close(fd);fd=openat(dir,name,O_WRONLY|O_APPEND|O_CREAT|O_EXCL|O_NOFOLLOW,0o600)
            guard fd>=0 else{throw StorageFailure()};_ = try validate(fd)
        }
        try bytes.withUnsafeBytes { raw in
            var offset=0
            while offset<raw.count {
                let n=Darwin.write(fd,raw.baseAddress!.advanced(by:offset),raw.count-offset)
                if n<0 && errno==EINTR {continue}
                guard n>0 else{throw StorageFailure()};offset += n
            }
        }
        guard fsync(fd)==0 else{throw StorageFailure()}
        // Rotation creates segments; deletion is based on time since archival, never size pressure.
        let daysCutoff=now.timeIntervalSince1970-Double(options.retentionDays)*86400
        let monthsCutoff=Calendar(identifier:.gregorian).date(byAdding:.month,value:-3,to:now)?.timeIntervalSince1970 ?? daysCutoff
        let cutoff=min(daysCutoff,monthsCutoff)
        for item in try fm.contentsOfDirectory(at:directory,includingPropertiesForKeys:nil) {
            let parts=item.lastPathComponent.split(separator:"-")
            guard parts.count==7,AuditCategory(rawValue:String(parts[0])) != nil,
                  let archived=Double(parts[1]),archived<cutoff,item.pathExtension=="jsonl" else{continue}
            var entry=stat()
            guard fstatat(dir,item.lastPathComponent,&entry,AT_SYMLINK_NOFOLLOW)==0,(entry.st_mode&S_IFMT)==S_IFREG,entry.st_uid==getuid() else{continue}
            guard unlinkat(dir,item.lastPathComponent,0)==0 else{throw StorageFailure()}
        }
    }
}
