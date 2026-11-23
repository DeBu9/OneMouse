import Cocoa
import ServiceManagement

// 命令行入口：--diagnose 打印诊断；--login-on / --login-off 管理开机自启
if CommandLine.arguments.contains("--diagnose") {
    Diagnostics.run()
    exit(0)
}

if CommandLine.arguments.contains("--login-on") || CommandLine.arguments.contains("--login-off") {
    let turnOn = CommandLine.arguments.contains("--login-on")
    do {
        if turnOn {
            try SMAppService.mainApp.register()
            print("开机自启: 已开启")
        } else {
            try SMAppService.mainApp.unregister()
            print("开机自启: 已关闭")
        }
    } catch {
        print("开机自启设置失败: \(error.localizedDescription)")
        exit(1)
    }
    print("状态码: \(SMAppService.mainApp.status.rawValue)（1 = 已启用，2 = 待用户确认，0 = 未注册）")
    exit(0)
}

let application = NSApplication.shared
let appDelegate = AppDelegate()
application.delegate = appDelegate
application.setActivationPolicy(.accessory)
application.run()
