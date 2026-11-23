import Foundation
import IOKit

/// 指针层：通过 IOHIDSystem 私有通道读写 HIDMouseAcceleration。
/// 0.0 = 无加速（ExactMouse 式硬关，旁路加速查表）
/// 65535.0 = 系统默认（带加速曲线）
final class PointerController {
    private typealias NXOpenFn = @convention(c) () -> io_connect_t
    private typealias SetFn = @convention(c) (io_connect_t, CFString, Double) -> kern_return_t
    private typealias GetFn = @convention(c) (io_connect_t, CFString, UnsafeMutablePointer<Double>) -> kern_return_t

    static let systemDefaultAccel: Double = 65535.0

    private let connection: io_connect_t
    private let setAcceleration: SetFn
    private let getAcceleration: GetFn
    private let key = "HIDMouseAcceleration" as CFString

    init?() {
        let asPath = "/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices"
        let ioPath = "/System/Library/Frameworks/IOKit.framework/IOKit"
        guard let asHandle = dlopen(asPath, RTLD_NOW),
              let ioHandle = dlopen(ioPath, RTLD_NOW),
              let nxSym = dlsym(asHandle, "NXOpenEventStatus"),
              let setSym = dlsym(ioHandle, "IOHIDSetAccelerationWithKey"),
              let getSym = dlsym(ioHandle, "IOHIDGetAccelerationWithKey")
        else {
            NSLog("OneMouse: 指针层符号解析失败")
            return nil
        }
        connection = unsafeBitCast(nxSym, to: NXOpenFn.self)()
        setAcceleration = unsafeBitCast(setSym, to: SetFn.self)
        getAcceleration = unsafeBitCast(getSym, to: GetFn.self)
    }

    var currentValue: Double {
        var value: Double = 0
        _ = getAcceleration(connection, key, &value)
        return value
    }

    var isLinear: Bool { currentValue <= 0 }

    private var restoreValue: Double {
        let saved = UserDefaults.standard.double(forKey: Prefs.savedAccel)
        return saved > 0 ? saved : PointerController.systemDefaultAccel
    }

    @discardableResult
    func setLinear(_ linear: Bool) -> Bool {
        if linear {
            let live = currentValue
            if live > 0 {
                UserDefaults.standard.set(live, forKey: Prefs.savedAccel)
            }
            setAcceleration(connection, key, 0.0)
        } else {
            setAcceleration(connection, key, restoreValue)
        }
        let applied = isLinear == linear
        if !applied {
            NSLog("OneMouse: 指针设置未生效，当前值 %.0f", currentValue)
        }
        return applied
    }
}
