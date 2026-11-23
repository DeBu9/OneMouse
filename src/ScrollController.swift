import Cocoa
import CoreGraphics

private let ownEventTag: Int64 = 0x4F4D_5553 // "OMUS"

private let scrollTapCallback: CGEventTapCallBack = { _, type, event, refcon in
    guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
    let controller = Unmanaged<ScrollController>.fromOpaque(refcon).takeUnretainedValue()
    return controller.handle(type: type, event: event)
}

/// 滚动层：拦截非连续滚轮事件，吞掉后按 120Hz 投递插值后的像素事件。
/// 触控板（continuous 事件）与自带标记的事件一律放行。
final class ScrollController {
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var timer: DispatchSourceTimer?
    private let engineQueue = DispatchQueue(label: "io.local.onemouse.scroll")
    private let eventSource = CGEventSource(stateID: .hidSystemState)

    private var remaining: Double = 0
    private var debugLogCount = 0

    var enabled: Bool = false {
        didSet {
            if enabled { start() } else { flush() }
        }
    }

    var speedLevel: Int = 1 {
        didSet { flush() }
    }

    /// 每「行」滚动对应的像素数。系统默认一格滚轮约等于 1 行。
    /// 三级分别对应 慢 / 标准 / 快，数值越低滚得越近。
    private var pixelsPerLine: Double {
        let base: Double
        switch speedLevel {
        case 0: base = 9
        case 2: base = 22
        default: base = 14
        }
        return base * distanceScale
    }

    /// 运行时可通过 defaults 微调整体距离，不必重新编译
    private var distanceScale: Double {
        let value = UserDefaults.standard.double(forKey: "scrollDistanceScale")
        guard value > 0 else { return 1.0 }
        return min(max(value, 0.3), 2.5)
    }

    /// 每帧吃掉剩余量的比例，越大收尾越快
    private var smoothing: Double {
        switch speedLevel {
        case 0: return 0.26
        case 2: return 0.40
        default: return 0.32
        }
    }

    var hasPermission: Bool { AXIsProcessTrusted() }
    var isTapping: Bool { tap != nil }

    func requestPermissionIfNeeded() {
        if AXIsProcessTrusted() {
            if enabled { start() }
            return
        }
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    func retryStart() {
        if tap == nil, enabled { start() }
    }

    func start() {
        guard tap == nil else { return }
        guard AXIsProcessTrusted() else {
            NSLog("OneMouse: 缺辅助功能权限，滚动层未启动")
            return
        }
        let mask = CGEventMask(1 << CGEventType.scrollWheel.rawValue)
        let port = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: scrollTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )
        guard let port = port else { return }
        tap = port
        if let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0) {
            runLoopSource = source
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        }
        CGEvent.tapEnable(tap: port, enable: true)
    }

    func stop() {
        flush()
        if let port = tap {
            CGEvent.tapEnable(tap: port, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        runLoopSource = nil
        tap = nil
    }

    func flush() {
        engineQueue.async { [weak self] in
            self?.remaining = 0
            self?.stopTimer()
        }
    }

    fileprivate func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let passthrough = Unmanaged.passUnretained(event)

        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let port = tap { CGEvent.tapEnable(tap: port, enable: true) }
            return passthrough
        }
        guard type == .scrollWheel, enabled else { return passthrough }
        guard event.getIntegerValueField(.eventSourceUserData) != ownEventTag else { return passthrough }
        // 触控板 / 妙控鼠标的连续滚动保持系统原样
        guard event.getIntegerValueField(.scrollWheelEventIsContinuous) == 0 else { return passthrough }

        let dy = event.getIntegerValueField(.scrollWheelEventDeltaAxis1)
        let dx = event.getIntegerValueField(.scrollWheelEventDeltaAxis2)
        guard dy != 0, dx == 0 else { return passthrough }

        if UserDefaults.standard.bool(forKey: "debugScroll"), debugLogCount < 60 {
            debugLogCount += 1
            let fixed = event.getIntegerValueField(.scrollWheelEventFixedPtDeltaAxis1)
            let line = event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1)
            appendDebug("dy=\(dy) fixedPt=\(fixed) point=\(line) px=\(dy) * \(pixelsPerLine) = \(Double(dy) * pixelsPerLine)")
        }

        enqueue(lines: Double(dy))
        return nil
    }

    private func appendDebug(_ text: String) {
        let path = "/tmp/onemouse-scroll.log"
        let line = text + "\n"
        if let handle = FileHandle(forWritingAtPath: path) {
            handle.seekToEndOfFile()
            handle.write(line.data(using: .utf8) ?? Data())
            handle.closeFile()
        } else {
            try? line.write(toFile: path, atomically: true, encoding: .utf8)
        }
    }

    private func enqueue(lines: Double) {
        let pixels = lines * pixelsPerLine
        engineQueue.async { [weak self] in
            guard let self = self else { return }
            if (self.remaining > 0) != (pixels > 0) { self.remaining = 0 }
            self.remaining += pixels
            if abs(self.remaining) > 4000 { self.remaining = self.remaining > 0 ? 4000 : -4000 }
            self.startTimerIfNeeded()
        }
    }

    private func startTimerIfNeeded() {
        guard timer == nil else { return }
        let source = DispatchSource.makeTimerSource(queue: engineQueue)
        source.schedule(deadline: .now(), repeating: .milliseconds(8), leeway: .milliseconds(1))
        source.setEventHandler { [weak self] in self?.tick() }
        source.resume()
        timer = source
    }

    private func stopTimer() {
        timer?.cancel()
        timer = nil
    }

    private func tick() {
        if abs(remaining) < 0.5 {
            let tail = remaining
            remaining = 0
            stopTimer()
            if abs(tail) >= 0.5 { emit(pixels: tail) }
            return
        }
        var step = remaining * smoothing
        if abs(step) < 1 { step = step < 0 ? -1 : 1 }
        remaining -= step
        emit(pixels: step)
    }

    private func emit(pixels: Double) {
        guard pixels != 0,
              let event = CGEvent(scrollWheelEvent2Source: eventSource,
                                  units: .pixel,
                                  wheelCount: 1,
                                  wheel1: 0,
                                  wheel2: 0,
                                  wheel3: 0) else { return }
        event.setIntegerValueField(.scrollWheelEventFixedPtDeltaAxis1, value: Int64((pixels * 65536).rounded()))
        event.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: Int64(pixels.rounded()))
        event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 0)
        event.setIntegerValueField(.eventSourceUserData, value: ownEventTag)
        event.post(tap: .cgSessionEventTap)
    }
}
