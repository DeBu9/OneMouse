import Foundation
import IOKit
import ApplicationServices

enum Diagnostics {
    private static var lines: [String] = []

    private static func emit(_ text: String) {
        print(text)
        lines.append(text)
    }

    static func run() {
        emit("OneMouse 诊断")
        emit("系统: \(ProcessInfo.processInfo.operatingSystemVersionString)")
        emit("bundle id: \(Bundle.main.bundleIdentifier ?? "nil")")
        emit("bundle 路径: \(Bundle.main.bundlePath)")
        emit("偏好 pointerLinear: \(UserDefaults.standard.bool(forKey: Prefs.pointerLinear))")

        if let pointer = PointerController() {
            let before = pointer.currentValue
            emit(String(format: "指针层: 可用，HIDMouseAcceleration = %.0f (%@)", before, before <= 0 ? "线性" : "加速"))
            let target = !pointer.isLinear
            let applied = pointer.setLinear(target)
            let after = pointer.currentValue
            emit(String(format: "试写 %@ → 读回 %.0f，%@", target ? "线性(0)" : "默认(65535)", after, applied ? "生效" : "未生效"))
            _ = pointer.setLinear(!target)
            emit(String(format: "已回滚 → 读回 %.0f", pointer.currentValue))
        } else {
            emit("指针层: 不可用（符号解析失败）")
        }

        // 注意：从终端直接跑二进制时，TCC 会归因给终端，这里会假报「已授权」。
        // 判断真实状态必须用 `open -a ... --args --diagnose` 启动。
        emit("辅助功能权限: \(AXIsProcessTrusted() ? "已授权" : "未授权")")
        emit("可注入事件(CGPreflightPostEventAccess): \(CGPreflightPostEventAccess() ? "是" : "否")")

        let report = lines.joined(separator: "\n") + "\n"
        try? report.write(toFile: "/tmp/onemouse-diag.txt", atomically: true, encoding: .utf8)
    }
}
