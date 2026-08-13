import ServiceManagement

protocol LaunchAtLoginManaging {
    var isEnabled: Bool { get }

    func setEnabled(_ isEnabled: Bool) throws
}

struct SystemLaunchAtLoginManager: LaunchAtLoginManaging {
    var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    func setEnabled(_ isEnabled: Bool) throws {
        if isEnabled {
            guard SMAppService.mainApp.status != .enabled else {
                return
            }
            try SMAppService.mainApp.register()
        } else {
            guard SMAppService.mainApp.status == .enabled else {
                return
            }
            try SMAppService.mainApp.unregister()
        }
    }
}
