import Foundation
import CoreGraphics
import CGVirtualDisplayBridge

final class VirtualDisplayManager {

    private var virtualDisplay: CGVirtualDisplay?
    private var virtualDisplayID: CGDirectDisplayID = 0
    private var sourceDisplayID: CGDirectDisplayID = 0

    // 显示状态监听
    private var displayMonitorTimer: DispatchSourceTimer?
    private var isMirroring = false
    private var wasMirroring = false  // 内置屏关闭前是否是镜像模式
    private var checkInterval: DispatchTimeInterval = .seconds(2)
    private var isRecoveringDisplay = false
    private var healthLogTicker = 0

    // caffeinate 进程（防止显示器休眠）
    private var caffeinateProcess: Process?

    // MARK: - Public

    /// 创建虚拟屏幕并启用镜像，返回是否成功
    func start() -> Bool {
        guard virtualDisplay == nil else {
            printErr("虚拟屏幕已在运行中")
            return true
        }

        // 1. 找到源显示器（优先内置屏，否则主屏）
        sourceDisplayID = Self.findSourceDisplay()
        guard sourceDisplayID != kCGNullDirectDisplay else {
            printErr("❌ 未找到任何活跃的显示器")
            return false
        }

        let isBuiltIn = CGDisplayIsBuiltin(sourceDisplayID) != 0
        printInfo("📺 源显示器: \(isBuiltIn ? "内置屏幕" : "主屏幕") (ID: \(sourceDisplayID))")

        // 2. 获取源屏幕的原生像素分辨率
        guard let mode = CGDisplayCopyDisplayMode(sourceDisplayID) else {
            printErr("❌ 无法获取显示器模式")
            return false
        }
        let pixelW = mode.pixelWidth
        let pixelH = mode.pixelHeight
        let pointW = mode.width
        let pointH = mode.height
        let refreshRate = mode.refreshRate > 0 ? mode.refreshRate : 60.0

        printInfo("   原生像素: \(pixelW)×\(pixelH)")
        printInfo("   逻辑分辨率: \(pointW)×\(pointH) @\(pixelW > pointW ? 2 : 1)x")
        printInfo("   刷新率: \(Int(refreshRate))Hz")

        // 3. 创建虚拟显示器
        guard createVirtualDisplay(
            pixelW: pixelW, pixelH: pixelH,
            pointW: pointW, pointH: pointH,
            refreshRate: refreshRate
        ) else {
            return false
        }

        let mirrorOK = enableMirroring()
        if mirrorOK {
            printInfo("✅ 镜像模式已启用")
            isMirroring = true
            wasMirroring = true
        } else {
            printErr("镜像模式设置失败（虚拟屏幕仍作为扩展显示器存在）")
            isMirroring = false
            wasMirroring = false
        }

        // 启动显示状态监听（包含内置屏开关和虚拟显示器存活）
        startDisplayMonitoring()

        // 启动 caffeinate -d 防止显示器休眠
        startCaffeinate()

        return true
    }

    /// 关闭镜像并销毁虚拟显示器
    func stop() {
        stopDisplayMonitoring()
        stopCaffeinate()
        if virtualDisplayID != 0 {
            disableMirroring()
            printInfo("🔌 镜像已关闭")
        }
        virtualDisplay = nil
        virtualDisplayID = 0
        sourceDisplayID = 0
        printInfo("🔌 虚拟显示器已移除")
    }

    // MARK: - Built-in Display Monitoring

    /// 启动显示器状态监听，负责保活和镜像状态自动恢复
    private func startDisplayMonitoring() {
        let queue = DispatchQueue(label: "com.mirrorscreen.display-monitor")
        displayMonitorTimer = DispatchSource.makeTimerSource(queue: queue)

        displayMonitorTimer?.setEventHandler { [weak self] in
            self?.checkDisplayState()
        }

        displayMonitorTimer?.schedule(deadline: .now(), repeating: checkInterval)
        displayMonitorTimer?.resume()

        printInfo("🔍 显示器状态监听已启动")
    }

    private func stopDisplayMonitoring() {
        displayMonitorTimer?.cancel()
        displayMonitorTimer = nil
    }

    // MARK: - Caffeinate Process

    /// 启动 caffeinate -d 防止显示器休眠
    private func startCaffeinate() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")
        process.arguments = ["-d"]  // -d: 防止显示器休眠

        do {
            try process.run()
            caffeinateProcess = process
            printInfo("✅ 已启动 caffeinate -d (防止显示器休眠)")
        } catch {
            printErr("启动 caffeinate 失败: \(error.localizedDescription)")
        }
    }

    /// 停止 caffeinate 进程
    private func stopCaffeinate() {
        guard let process = caffeinateProcess else { return }

        process.terminate()
        caffeinateProcess = nil
        printInfo("🔌 caffeinate 已停止")
    }

    private func checkDisplayState() {
        guard virtualDisplayID != 0 else { return }
        healthLogTicker += 1

        // 核心保活：虚拟显示器被系统回收后自动重建
        let alive = isDisplayAlive(virtualDisplayID)
        if !alive {
            printWarn("检测到虚拟显示器离线: virtualDisplayID=\(virtualDisplayID), sourceDisplayID=\(sourceDisplayID)")
            DispatchQueue.main.async { [weak self] in
                self?.recoverVirtualDisplay(reason: "检测到虚拟显示器已离线")
            }
            return
        }

        guard sourceDisplayID != 0, CGDisplayIsBuiltin(sourceDisplayID) != 0 else { return }

        let isPoweredOn = CGDisplayIsOnline(sourceDisplayID) != 0
        let isCurrentlyMirrored = isDisplayMirrored(virtualDisplayID)

        // 每分钟心跳一次，便于复盘消失前状态
        if healthLogTicker >= 30 {
            healthLogTicker = 0
            printInfo(
                "心跳: virtualID=\(virtualDisplayID), sourceID=\(sourceDisplayID), sourceOnline=\(isPoweredOn), mirrored=\(isCurrentlyMirrored), recovering=\(isRecoveringDisplay)"
            )
        }

        if !isPoweredOn && isCurrentlyMirrored {
            // 内置屏关闭，当前是镜像模式 -> 切换到扩展模式
            DispatchQueue.main.async { [weak self] in
                self?.handleBuiltInDisplayOff()
            }
        } else if isPoweredOn && !isCurrentlyMirrored && wasMirroring {
            // 内置屏重新开启，之前是镜像模式 -> 恢复镜像
            DispatchQueue.main.async { [weak self] in
                self?.handleBuiltInDisplayOn()
            }
        }
    }

    private func recoverVirtualDisplay(reason: String) {
        guard !isRecoveringDisplay else { return }
        isRecoveringDisplay = true
        defer { isRecoveringDisplay = false }

        let shouldRestoreMirroring = wasMirroring || isMirroring
        printWarn("⚠️ \(reason)，准备重建虚拟显示器")

        sourceDisplayID = Self.findSourceDisplay()
        guard sourceDisplayID != kCGNullDirectDisplay else {
            printErr("恢复失败：找不到可用源显示器")
            return
        }

        guard let mode = CGDisplayCopyDisplayMode(sourceDisplayID) else {
            printErr("恢复失败：无法读取源显示器模式")
            return
        }

        let rebuilt = createVirtualDisplay(
            pixelW: mode.pixelWidth,
            pixelH: mode.pixelHeight,
            pointW: mode.width,
            pointH: mode.height,
            refreshRate: mode.refreshRate > 0 ? mode.refreshRate : 60.0
        )
        guard rebuilt else { return }

        if shouldRestoreMirroring {
            if enableMirroring() {
                isMirroring = true
                wasMirroring = true
                printInfo("✅ 重建后已恢复镜像模式")
            } else {
                isMirroring = false
                printErr("重建后恢复镜像失败")
            }
        } else {
            isMirroring = false
        }
    }

    private func createVirtualDisplay(
        pixelW: Int,
        pixelH: Int,
        pointW: Int,
        pointH: Int,
        refreshRate: Double
    ) -> Bool {
        let descriptor = CGVirtualDisplayDescriptor()
        descriptor.setDispatchQueue(DispatchQueue.main)
        descriptor.name = "MirrorScreen"
        descriptor.maxPixelsWide = UInt32(pixelW)
        descriptor.maxPixelsHigh = UInt32(pixelH)
        descriptor.sizeInMillimeters = CGSize(width: 600, height: 340)
        descriptor.vendorID = 0xAB02
        descriptor.productID = 0xAB01
        descriptor.serialNum = UInt32(Int.random(in: 1...Int(UInt16.max)))
        descriptor.terminationHandler = { [weak self] _, display in
            DispatchQueue.main.async {
                self?.recoverVirtualDisplay(reason: "系统触发 terminationHandler (ID: \(display.displayID))")
            }
        }

        let display = CGVirtualDisplay(descriptor: descriptor)
        guard display.displayID != 0 else {
            printErr("❌ 创建虚拟显示器失败")
            return false
        }

        self.virtualDisplay = display
        self.virtualDisplayID = display.displayID
        printInfo("✅ 虚拟显示器已创建 (ID: \(virtualDisplayID))")

        let settings = CGVirtualDisplaySettings()
        settings.hiDPI = 1
        settings.modes = Self.buildModes(
            nativeW: pixelW, nativeH: pixelH,
            pointW: pointW, pointH: pointH,
            refreshRate: refreshRate
        )

        let applyOK = display.apply(settings)
        if !applyOK {
            printErr("❌ 虚拟显示器模式应用失败")
            return false
        }

        printInfo("   已应用 \(settings.modes.count) 个分辨率模式")
        printInfo("⏳ 等待系统注册虚拟显示器...")
        Thread.sleep(forTimeInterval: 1.5)
        return true
    }

    private func isDisplayAlive(_ displayID: CGDirectDisplayID) -> Bool {
        var ids = [CGDirectDisplayID](repeating: 0, count: 32)
        var count: UInt32 = 0
        let err = CGGetOnlineDisplayList(UInt32(ids.count), &ids, &count)
        guard err == .success else { return false }
        return ids.prefix(Int(count)).contains(displayID)
    }

    private func handleBuiltInDisplayOff() {
        printInfo("📴 内置显示器已关闭，切换到扩展模式")
        disableMirroring()
        isMirroring = false
        wasMirroring = true
    }

    private func handleBuiltInDisplayOn() {
        printInfo("📺 内置显示器已开启，恢复镜像模式")
        let mirrorOK = enableMirroring()
        if mirrorOK {
            isMirroring = true
            wasMirroring = false
        }
    }

    /// 检查指定显示器是否处于镜像模式
    private func isDisplayMirrored(_ displayID: CGDirectDisplayID) -> Bool {
        // CGDisplayMirrorsDisplay 返回被镜像的显示器ID，如果没有镜像则返回 kCGNullDirectDisplay
        let mirroredDisplay = CGDisplayMirrorsDisplay(displayID)
        return mirroredDisplay != kCGNullDirectDisplay
    }

    // MARK: - Display Detection

    /// 优先返回内置屏幕 ID，否则返回主屏幕
    private static func findSourceDisplay() -> CGDirectDisplayID {
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        CGGetActiveDisplayList(16, &ids, &count)

        for i in 0..<Int(count) {
            if CGDisplayIsBuiltin(ids[i]) != 0 {
                return ids[i]
            }
        }
        // 没有内置屏幕（Mac mini / Mac Pro / 合盖模式），用主屏
        return CGMainDisplayID()
    }

    // MARK: - Mode Building

    private static func buildModes(
        nativeW: Int, nativeH: Int,
        pointW: Int, pointH: Int,
        refreshRate: Double
    ) -> [CGVirtualDisplayMode] {
        var modes: [CGVirtualDisplayMode] = []
        var seen = Set<String>()

        func add(_ w: Int, _ h: Int, _ hz: Double) {
            let key = "\(w)x\(h)"
            guard !seen.contains(key), w > 0, h > 0 else { return }
            seen.insert(key)
            modes.append(CGVirtualDisplayMode(width: UInt(w), height: UInt(h), refreshRate: hz))
        }

        let hz = refreshRate

        // 源屏幕的原生像素分辨率
        add(nativeW, nativeH, hz)
        // 逻辑分辨率（如果不同）
        add(pointW, pointH, hz)

        // 常见分辨率补充
        let common: [(Int, Int)] = [
            (3840, 2400), (3840, 2160), (3456, 2234), (3024, 1964),
            (2880, 1800), (2560, 1600), (2560, 1440),
            (1920, 1200), (1920, 1080), (1680, 1050),
            (1440, 900),  (1280, 800),
        ]
        for (w, h) in common { add(w, h, hz) }

        return modes
    }

    // MARK: - Mirroring

    private func enableMirroring() -> Bool {
        guard virtualDisplayID != 0, sourceDisplayID != 0 else { return false }

        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success else {
            printErr("CGBeginDisplayConfiguration 失败")
            return false
        }

        let err = CGConfigureDisplayMirrorOfDisplay(config, virtualDisplayID, sourceDisplayID)
        guard err == .success else {
            printErr("CGConfigureDisplayMirrorOfDisplay 失败: \(err)")
            CGCancelDisplayConfiguration(config)
            return false
        }

        guard CGCompleteDisplayConfiguration(config, .forSession) == .success else {
            printErr("CGCompleteDisplayConfiguration 失败")
            return false
        }

        return true
    }

    private func disableMirroring() {
        guard virtualDisplayID != 0 else { return }
        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success else { return }
        CGConfigureDisplayMirrorOfDisplay(config, virtualDisplayID, kCGNullDirectDisplay)
        CGCompleteDisplayConfiguration(config, .forSession)
    }

    // MARK: - Logging

    private func printInfo(_ msg: String) {
        logInfo(msg)
    }

    private func printErr(_ msg: String) {
        logError(msg)
    }

    private func printWarn(_ msg: String) {
        logWarn(msg)
    }
}
