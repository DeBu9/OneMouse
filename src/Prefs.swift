import Foundation

enum Prefs {
    static let pointerLinear = "pointerLinearEnabled"
    static let scrollSmooth = "scrollSmoothEnabled"
    static let scrollSpeed = "scrollSpeedLevel"
    static let savedAccel = "savedMouseAcceleration"

    static func register() {
        UserDefaults.standard.register(defaults: [
            scrollSmooth: true,
            scrollSpeed: 1
        ])
    }

    /// 从旧 bundle id（io.local.onemouse）迁移一次配置，换 id 不至于把设置清空
    static func migrateIfNeeded() {
        guard let legacy = UserDefaults(suiteName: "io.local.onemouse") else { return }
        let current = UserDefaults.standard
        for key in [pointerLinear, scrollSmooth, scrollSpeed, savedAccel] {
            if current.object(forKey: key) == nil, let value = legacy.object(forKey: key) {
                current.set(value, forKey: key)
            }
        }
    }
}
