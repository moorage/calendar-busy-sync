#if os(macOS)
import Foundation
import ServiceManagement

protocol MacLaunchAtLoginControlling {
    var status: SMAppService.Status { get }
    func setEnabled(_ enabled: Bool) throws
}

struct MacLaunchAtLoginService: MacLaunchAtLoginControlling {
    var status: SMAppService.Status {
        SMAppService.mainApp.status
    }

    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
#endif
