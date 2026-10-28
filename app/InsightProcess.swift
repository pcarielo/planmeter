import Foundation
import Darwin

// A dedicated process group lets cancellation also terminate a harness's subprocesses.
final class InsightProcess {
    var executableURL:URL?
    var arguments:[String]?
    var currentDirectoryURL:URL?
    var environment:[String:String]?
    var standardInput:Pipe?
    var standardOutput:Pipe?
    var standardError:FileHandle?
    var terminal:FileHandle?
    private(set) var processIdentifier:Int32=0
    private var reaped=false
    private var status:Int32=0
    var isRunning:Bool {
        guard processIdentifier>0,!reaped else{return false}
        let result=waitpid(processIdentifier,&status,WNOHANG)
        if result==processIdentifier || (result<0 && errno==ECHILD) {reaped=true}
        return !reaped
    }
    var terminationStatus:Int32 {(status & 0x7f)==0 ? (status>>8)&0xff : -1}
    func run()throws {
        guard let executable=executableURL?.path,let cwd=currentDirectoryURL?.path,
              let inputFD=terminal?.fileDescriptor ?? standardInput?.fileHandleForReading.fileDescriptor,
              let outputFD=terminal?.fileDescriptor ?? standardOutput?.fileHandleForWriting.fileDescriptor,
              let errorFD=terminal?.fileDescriptor ?? standardError?.fileDescriptor else{throw InsightFailure.invalidConfiguration}
        var actions:posix_spawn_file_actions_t?
        var attrs:posix_spawnattr_t?
        guard posix_spawn_file_actions_init(&actions)==0 else{throw InsightFailure.unavailable}
        defer{posix_spawn_file_actions_destroy(&actions)}
        guard posix_spawnattr_init(&attrs)==0 else{throw InsightFailure.unavailable}
        defer{posix_spawnattr_destroy(&attrs)}
        guard posix_spawn_file_actions_addchdir_np(&actions,cwd)==0,
              posix_spawn_file_actions_adddup2(&actions,inputFD,STDIN_FILENO)==0,
              posix_spawn_file_actions_adddup2(&actions,outputFD,STDOUT_FILENO)==0,
              posix_spawn_file_actions_adddup2(&actions,errorFD,STDERR_FILENO)==0,
              posix_spawnattr_setflags(&attrs,Int16(POSIX_SPAWN_SETPGROUP|POSIX_SPAWN_CLOEXEC_DEFAULT))==0,
              posix_spawnattr_setpgroup(&attrs,0)==0 else{throw InsightFailure.unavailable}
        var argv=([executable]+(arguments ?? [])).map{strdup($0)}+[nil]
        var envp=(environment ?? [:]).map{strdup($0.key+"="+$0.value)}+[nil]
        defer {for ptr in argv {free(ptr)};for ptr in envp {free(ptr)}}
        let result=argv.withUnsafeMutableBufferPointer {a in envp.withUnsafeMutableBufferPointer {e in
            posix_spawn(&processIdentifier,executable,&actions,&attrs,a.baseAddress!,e.baseAddress!)
        }}
        guard result==0 else{processIdentifier=0;throw InsightFailure.unavailable}
        if let terminal=terminal {try? terminal.close()} else {try? standardInput?.fileHandleForReading.close();try? standardOutput?.fileHandleForWriting.close()}
    }
    func terminate(){if processIdentifier>0 {Darwin.kill(-processIdentifier,SIGTERM)}}
    func killGroup(){if processIdentifier>0 {Darwin.kill(-processIdentifier,SIGKILL)}}
    func waitUntilExit(){guard processIdentifier>0,!reaped else{return};while waitpid(processIdentifier,&status,0)<0 && errno==EINTR {};reaped=true}
}
