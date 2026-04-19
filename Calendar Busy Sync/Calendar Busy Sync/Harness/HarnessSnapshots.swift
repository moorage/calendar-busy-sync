import Foundation

struct MirrorPreviewSnapshot: Codable, Equatable {
    let sourceCalendar: String
    let targetCalendar: String
    let availability: String
}

struct HarnessStateSnapshot: Codable, Equatable {
    let platform: String
    let deviceClass: String
    let selectedScenario: String
    let connectedAccountCount: Int
    let selectedCalendarCount: Int
    let mirrorRuleCount: Int
    let pendingWriteCount: Int
    let failedWriteCount: Int
    let lastSyncStatus: String
    let mirrorPreview: [MirrorPreviewSnapshot]
}

struct HarnessPerformanceSnapshot: Codable, Equatable {
    let platform: String
    let deviceClass: String
    let launchTime: Double
    let readyTime: Double
    let scenarioLoadTime: Double
    let syncPlanningTime: Double
    let mirrorPreviewCount: Int
}
