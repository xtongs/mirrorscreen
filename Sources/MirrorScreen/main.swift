import Foundation
import CoreGraphics
import CGVirtualDisplayBridge
import Darwin
import MachO

// ─── 日志文件系统 ─────────────────────────────────────
private var logFileHandle: FileHandle?
private let logFileName = "MirrorScreen.log"
private let launchAgentLabel = "com.mirrorscreen.agent"

func setupLogging() {
    let executableURL = URL(fileURLWithPath: resolvedExecutablePath())
    let logDir = executableURL.deletingLastPathComponent()
    let logFilePath = logDir.appendingPathComponent(logFileName).path

    guard FileManager.default.createFile(atPath: logFilePath, contents: nil, attributes: nil) else {
        fputs("无法创建日志文件: \(logFilePath)\n", stderr)
        return
    }

    do {
        logFileHandle = try FileHandle(forWritingTo: URL(fileURLWithPath: logFilePath))
        logFileHandle?.seekToEndOfFile()
    } catch {
        logFileHandle = try? FileHandle(forWritingTo: URL(fileURLWithPath: logFilePath))
    }
}

func writeToLog(_ message: String) {
    let timestamp = ISO8601DateFormatter().string(from: Date())
    let logMessage = "[\(timestamp)] \(message)\n"
    print(message)
    if let handle = logFileHandle {
        handle.write(logMessage.data(using: .utf8) ?? Data())
    }
}

func closeLogging() {
    logFileHandle?.closeFile()
    logFileHandle = nil
}

// ─── 运行参数 ─────────────────────────────────────
var NO_EXIT_MODE = true        // 默认忽略退出信号
var isBackground = true        // 默认后台运行
var isStopping = false
var lastStopReason = ""
var lastStopTime = Date()
var shouldRunAsAgent = false

func parseArguments() {
    let args = CommandLine.arguments
    var index = 1
    while index < args.count {
        let arg = args[index]
        if arg == "--run-agent" {
            shouldRunAsAgent = true
            isBackground = true
            NO_EXIT_MODE = true
        } else if arg == "--no-exit" {
            NO_EXIT_MODE = true
            logDebug("已启用忽略退出模式")
        } else if arg == "--background" {
            isBackground = true
        } else if arg == "--exit-on-signal" {
            NO_EXIT_MODE = false
            logDebug("已禁用忽略退出模式")
        } else if arg == "--foreground" {
            isBackground = false
        }
        index += 1
    }
}

// ─── 日志系统 ─────────────────────────────────────
func logDebug(_ message: String) {
    writeToLog("[MirrorScreen] [DEBUG] \(message)")
}

func logInfo(_ message: String) {
    writeToLog("[MirrorScreen] \(message)")
}

func logWarn(_ message: String) {
    writeToLog("[MirrorScreen] ⚠️  \(message)")
}

func logError(_ message: String) {
    let errorLog = "[MirrorScreen] ❌ \(message)"
    writeToLog(errorLog)
    fputs(errorLog + "\n", stderr)
}

// ─── 子进程执行 ─────────────────────────────────────
@discardableResult
func runCommand(_ launchPath: String, _ arguments: [String]) -> (code: Int32, stdout: String, stderr: String) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: launchPath)
    process.arguments = arguments

    let outPipe = Pipe()
    let errPipe = Pipe()
    process.standardOutput = outPipe
    process.standardError = errPipe

    do {
        try process.run()
        process.waitUntilExit()
    } catch {
        return (127, "", error.localizedDescription)
    }

    let out = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    let err = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    return (process.terminationStatus, out, err)
}

func resolvedExecutablePath() -> String {
    // Ask dyld for the currently loaded executable path instead of trusting argv[0],
    // which can be relative (e.g. "MirrorScreen") and tied to the caller's CWD.
    var size: UInt32 = 0
    _ = _NSGetExecutablePath(nil, &size)
    if size > 0 {
        var buffer = [CChar](repeating: 0, count: Int(size))
        if _NSGetExecutablePath(&buffer, &size) == 0 {
            let path = String(cString: buffer)
            return URL(fileURLWithPath: path).resolvingSymlinksInPath().path
        }
    }

    if let bundlePath = Bundle.main.executablePath, !bundlePath.isEmpty {
        return URL(fileURLWithPath: bundlePath).resolvingSymlinksInPath().path
    }

    let arg0 = CommandLine.arguments[0]
    if arg0.contains("/") {
        return URL(fileURLWithPath: arg0).standardizedFileURL.resolvingSymlinksInPath().path
    }

    if let pathEnv = ProcessInfo.processInfo.environment["PATH"] {
        for dir in pathEnv.split(separator: ":") {
            let candidate = String(dir) + "/" + arg0
            if access(candidate, X_OK) == 0 {
                return URL(fileURLWithPath: candidate).resolvingSymlinksInPath().path
            }
        }
    }

    return URL(fileURLWithPath: arg0).standardizedFileURL.path
}

func guiUID() -> Int {
    if let attrs = try? FileManager.default.attributesOfItem(atPath: "/dev/console"),
       let uid = attrs[.ownerAccountID] as? NSNumber {
        return uid.intValue
    }
    return Int(getuid())
}

func launchAgentPlistPath() -> String {
    "\(NSHomeDirectory())/Library/LaunchAgents/\(launchAgentLabel).plist"
}

func buildLaunchAgentPlist(executablePath: String) -> String {
    let escapedExec = executablePath
        .replacingOccurrences(of: "&", with: "&amp;")
        .replacingOccurrences(of: "<", with: "&lt;")
        .replacingOccurrences(of: ">", with: "&gt;")
    let stdoutPath = "\(NSHomeDirectory())/Library/Logs/MirrorScreen.launchd.out.log"
    let stderrPath = "\(NSHomeDirectory())/Library/Logs/MirrorScreen.launchd.err.log"

    return """
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
      <key>Label</key>
      <string>\(launchAgentLabel)</string>
      <key>ProgramArguments</key>
      <array>
        <string>\(escapedExec)</string>
        <string>--run-agent</string>
      </array>
      <key>RunAtLoad</key>
      <true/>
      <key>KeepAlive</key>
      <true/>
      <key>StandardOutPath</key>
      <string>\(stdoutPath)</string>
      <key>StandardErrorPath</key>
      <string>\(stderrPath)</string>
    </dict>
    </plist>
    """
}

func startManagedAgent() {
    let executablePath = resolvedExecutablePath()
    let plistPath = launchAgentPlistPath()
    let uid = guiUID()

    do {
        let logsDir = "\(NSHomeDirectory())/Library/Logs"
        try FileManager.default.createDirectory(atPath: logsDir, withIntermediateDirectories: true)
        let plist = buildLaunchAgentPlist(executablePath: executablePath)
        try plist.write(toFile: plistPath, atomically: true, encoding: .utf8)
    } catch {
        fputs("写入 LaunchAgent 失败: \(error.localizedDescription)\n", stderr)
        exit(1)
    }

    _ = runCommand("/bin/launchctl", ["bootout", "gui/\(uid)/\(launchAgentLabel)"])
    let bootstrap = runCommand("/bin/launchctl", ["bootstrap", "gui/\(uid)", plistPath])
    if bootstrap.code != 0 {
        fputs("启动失败(bootstrap): \(bootstrap.stderr)\n", stderr)
        exit(1)
    }

    let kickstart = runCommand("/bin/launchctl", ["kickstart", "-k", "gui/\(uid)/\(launchAgentLabel)"])
    if kickstart.code != 0 {
        fputs("启动失败(kickstart): \(kickstart.stderr)\n", stderr)
        exit(1)
    }

    print("MirrorScreen 已启动并托管到 launchd")
    print("  Label: \(launchAgentLabel)")
    print("  Plist: \(plistPath)")
}

func stopManagedAgent() {
    let uid = guiUID()
    let result = runCommand("/bin/launchctl", ["bootout", "gui/\(uid)/\(launchAgentLabel)"])
    if result.code == 0 {
        print("MirrorScreen 已停止")
    } else {
        print("MirrorScreen 停止命令返回: \(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))")
    }

    _ = runCommand("/usr/bin/pkill", ["-9", "-f", resolvedExecutablePath()])
}

func statusManagedAgent() {
    let uid = guiUID()
    let printResult = runCommand("/bin/launchctl", ["print", "gui/\(uid)/\(launchAgentLabel)"])
    let psResult = runCommand("/usr/bin/pgrep", ["-fl", resolvedExecutablePath()])

    if printResult.code == 0 {
        print("launchd: running")
    } else {
        print("launchd: not loaded")
    }

    let pgrepOut = psResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    if pgrepOut.isEmpty {
        print("process: not running")
    } else {
        print("process:")
        print(pgrepOut)
    }
}

func restartManagedAgent() {
    stopManagedAgent()
    startManagedAgent()
}

// ─── 虚拟显示器主逻辑 ─────────────────────────────────────
let manager = VirtualDisplayManager()

var signalSources: [DispatchSourceSignal] = []

func setupSignalHandlers() {
    for sig: Int32 in [SIGINT, SIGTERM, SIGHUP] {
        // 先忽略系统默认处理
        signal(sig, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
        source.setEventHandler {
            if NO_EXIT_MODE && !isStopping {
                let sigName = sig == SIGINT ? "SIGINT" : (sig == SIGTERM ? "SIGTERM" : "SIGHUP")
                logDebug("忽略退出信号 \(sigName)：保持虚拟显示器运行")
                return
            }

            isStopping = true

            let stopReason: String
            if sig == SIGINT {
                stopReason = "用户中断 (Ctrl+C)"
            } else if sig == SIGTERM {
                stopReason = "系统终止 (SIGTERM)"
            } else {
                stopReason = "终端断开/会话结束 (SIGHUP)"
            }
            lastStopReason = stopReason
            lastStopTime = Date()

            logWarn("开始停止虚拟显示器... 原因: \(stopReason)")

            manager.stop()
            closeLogging()
            exit(0)
        }
        source.resume()
        signalSources.append(source)
    }
}

let helpText = """
MirrorScreen — 轻量级 macOS 虚拟屏幕

用法:
  MirrorScreen run                 直接运行（前台阻塞）
  MirrorScreen start               安装并启动 launchd 常驻服务（推荐）
  MirrorScreen stop                停止 launchd 服务
  MirrorScreen status              查看服务和进程状态
  MirrorScreen restart             重启 launchd 服务
  MirrorScreen                     等同于 run
  MirrorScreen --exit-on-signal    允许信号终止程序（Ctrl+C 可退出）
  MirrorScreen --foreground        前台运行模式
  MirrorScreen --run-agent         由 launchd 内部调用
  MirrorScreen --help              显示本帮助

功能特性:
  • 支持 start/stop/status 一键管理
  • 日志输出到程序同目录下的 MirrorScreen.log
  • 默认忽略退出信号，保持虚拟显示器运行
  • 内置显示器关闭时自动切换到扩展模式
  • 内置显示器重新开启时自动恢复镜像模式
  • 用户切换/注销时程序不会中断

运行后 kill 进程即可停止，虚拟屏幕自动清理。
"""

let args = CommandLine.arguments
if args.contains("--help") || args.contains("-h") {
    print(helpText)
    exit(0)
}

let command = args.dropFirst().first
if command == "start" {
    startManagedAgent()
    exit(0)
}
if command == "stop" {
    stopManagedAgent()
    exit(0)
}
if command == "status" {
    statusManagedAgent()
    exit(0)
}
if command == "restart" {
    restartManagedAgent()
    exit(0)
}

setupLogging()
parseArguments()
setupSignalHandlers()

logDebug("main.swift 启动")
logDebug("NO_EXIT_MODE: \(NO_EXIT_MODE)")
logDebug("isBackground: \(isBackground)")
logDebug("PID: \(ProcessInfo.processInfo.processIdentifier), PPID: \(getppid())")
if shouldRunAsAgent {
    logDebug("启动模式: launchd agent")
}

guard manager.start() else {
    logError("manager.start() 失败")
    exit(1)
}

print("")
print("[MirrorScreen] 🟢 运行中 \(NO_EXIT_MODE ? "(忽略退出模式)" : "") — 日志: \(logFileName)")
print("")

dispatchMain()
