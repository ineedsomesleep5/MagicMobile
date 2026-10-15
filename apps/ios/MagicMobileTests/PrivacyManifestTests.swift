import Foundation
import XCTest

/// PrivacyInfo.xcprivacy must declare every required-reason API category the app calls, or App Store
/// Connect refuses the build for App Store review (ITMS-91053). Build 38 called three undeclared
/// categories (docs/audits/APP_AUDIT_2026-10.md). The engine's static JDK libraries also call
/// stat/fstat/lstat, fstatfs/fstatvfs and mach_absolute_time, which the same categories cover.
final class PrivacyManifestTests: XCTestCase {
    private static let ios = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()

    /// Required-reason categories → identifiers in Swift code that count as a use.
    private static let covered: [String: [String]] = [
        "NSPrivacyAccessedAPICategoryUserDefaults": ["UserDefaults", "AppStorage"],
        "NSPrivacyAccessedAPICategoryFileTimestamp": ["creationDate", "modificationDate", "contentModificationDate",
                                                      "contentModificationDateKey", "creationDateKey", "getattrlist"],
        "NSPrivacyAccessedAPICategorySystemBootTime": ["systemUptime", "mach_absolute_time"],
        "NSPrivacyAccessedAPICategoryDiskSpace": ["systemFreeSize", "systemSize", "volumeAvailableCapacityKey",
                                                  "volumeAvailableCapacityForImportantUsageKey", "statfs", "statvfs"],
        "NSPrivacyAccessedAPICategoryActiveKeyboards": ["activeInputModes"],
    ]

    private func declaredReasons() throws -> [String: [String]] {
        let data = try Data(contentsOf: Self.ios.appendingPathComponent("MagicMobile/PrivacyInfo.xcprivacy"))
        let plist = try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        let types = try XCTUnwrap(plist["NSPrivacyAccessedAPITypes"] as? [[String: Any]])
        var declared: [String: [String]] = [:]
        for entry in types {
            let type = try XCTUnwrap(entry["NSPrivacyAccessedAPIType"] as? String)
            declared[type] = try XCTUnwrap(entry["NSPrivacyAccessedAPITypeReasons"] as? [String])
        }
        return declared
    }

    func testDeclaresTheCategoriesBuild38Calls() throws {
        XCTAssertEqual(try declaredReasons(), [
            "NSPrivacyAccessedAPICategoryUserDefaults": ["CA92.1"],
            "NSPrivacyAccessedAPICategoryFileTimestamp": ["C617.1"],
            "NSPrivacyAccessedAPICategorySystemBootTime": ["35F9.1"],
            "NSPrivacyAccessedAPICategoryDiskSpace": ["E174.1"],
        ])
    }

    /// A covered API newly called from the app's Swift code (or the engine's Swift wrapper) needs its
    /// category in the manifest before the build can go to App Store review.
    func testEveryCoveredAPIInTheSourcesIsDeclared() throws {
        let declared = try declaredReasons()
        let roots = ["MagicMobile", "../../packages/ondevice-engine/swift/Sources"].map {
            Self.ios.appendingPathComponent($0).standardizedFileURL
        }
        var used: [String: String] = [:]
        for root in roots {
            let files = try XCTUnwrap(FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil))
            for case let file as URL in files where file.pathExtension == "swift" {
                let source = try String(contentsOf: file, encoding: .utf8)
                for (category, tokens) in Self.covered where used[category] == nil {
                    if tokens.contains(where: { source.range(of: "\\b\($0)\\b", options: .regularExpression) != nil }) {
                        used[category] = file.lastPathComponent
                    }
                }
            }
        }
        XCTAssertNotNil(used["NSPrivacyAccessedAPICategorySystemBootTime"], "the scan should see systemUptime")
        for (category, file) in used {
            XCTAssertNotNil(declared[category], "\(file) uses \(category); declare it with its reason in PrivacyInfo.xcprivacy")
        }
    }
}
