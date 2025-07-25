extension EmbeddedTemplates {
    public static let previewTests = #"""
// swiftlint:disable all
// swiftformat:disable all

import XCTest
import SwiftUI
import Prefire
{% for import in argument.imports %}
import {{ import }}
{% endfor %}
{% if argument.mainTarget %}
@testable import {{ argument.mainTarget }}
{% endif %}
{% for import in argument.testableImports %}
@testable import {{ import }}
{% endfor %}
import SnapshotTesting
#if canImport(AccessibilitySnapshot)
    import AccessibilitySnapshot
#endif

@MainActor class PreviewTests: XCTestCase, Sendable {
    private var simulatorDevice: String?{% if argument.simulatorDevice %} = "{{ argument.simulatorDevice|default:nil }}"{% endif %}
    private var requiredOSVersion: Int?{% if argument.simulatorOSVersion %} = {{ argument.simulatorOSVersion }}{% endif %}
    private let snapshotDevices: [String]{% if argument.snapshotDevices %} = {{ argument.snapshotDevices|split:"|" }}{% else %} = []{% endif %}
#if os(iOS)
    private let deviceConfig: DeviceConfig = ViewImageConfig.iPhoneX.deviceConfig
#elseif os(tvOS)
    private let deviceConfig: DeviceConfig = ViewImageConfig.tv.deviceConfig
#endif


    {% if argument.file %}

    private var file: StaticString { .init(stringLiteral: "{{ argument.file }}") }
    {% endif %}

    @MainActor override func setUp() async throws {
        try await super.setUp()

        checkEnvironments()
        UIView.setAnimationsEnabled(false)
    }

    // MARK: - PreviewProvider

    {% for type in types.types where type.implements.PrefireProvider or type.based.PrefireProvider or type|annotated:"PrefireProvider" %}
    func test_{{ type.name|lowerFirstLetter|replace:"_Previews", "" }}() {
        for preview in {{ type.name }}._allPreviews {
            if let failure = assertSnapshots(for: PrefireSnapshot(preview, device: preview.device?.snapshotDevice() ?? deviceConfig)) {
                XCTFail(failure)
            }
        }
    }
    {%- if not forloop.last %}

    {% endif %}
    {% endfor %}
    {% if argument.previewsMacrosDict %}
    // MARK: - Macros

    {% for macroModel in argument.previewsMacrosDict %}
    func test_{{ macroModel.componentTestName }}_Preview() {
        {% if macroModel.properties %}
        struct PreviewWrapper{{ macroModel.componentTestName }}: SwiftUI.View {
        {{ macroModel.properties }}
            var body: some View {
            {{ macroModel.body|indent:12 }}
            }
        }
        let preview = PreviewWrapper{{ macroModel.componentTestName }}.init
        {% else %}
        let preview = {
        {{ macroModel.body|indent:8 }}
        }
        {% endif %}
        {% if macroModel.isScreen == 1 %}
        let isScreen = true
        {% else %}
        let isScreen = false
        {% endif %}
        if let failure = assertSnapshots(for: PrefireSnapshot(preview(), name: "{{ macroModel.displayName }}", isScreen: isScreen, device: deviceConfig)) {
            XCTFail(failure)
        }
    }
    {%- if not forloop.last %}

    {% endif %}
    {% endfor %}
    {% endif %}
    // MARK: Private

    private func assertSnapshots<Content: SwiftUI.View>(for prefireSnapshot: PrefireSnapshot<Content>) -> String? {
        guard !snapshotDevices.isEmpty else {
            return assertSnapshot(for: prefireSnapshot)
        }

        for deviceName in snapshotDevices {
            var snapshot = prefireSnapshot
            guard let device: DeviceConfig = PreviewDevice(rawValue: deviceName).snapshotDevice() else {
                fatalError("Unknown device name from configuration file: \(deviceName)")
            }

            snapshot.name = "\(prefireSnapshot.name)-\(deviceName)"
            snapshot.device = device

            // Ignore specific device safe area
            snapshot.device.safeArea = .zero

            // Ignore specific device display scale
            snapshot.traits = UITraitCollection(displayScale: 2.0)

            if let failure = assertSnapshot(for: snapshot) {
                XCTFail(failure)
            }
        }

        return nil
    }

    private func assertSnapshot<Content: SwiftUI.View>(for prefireSnapshot: PrefireSnapshot<Content>) -> String? {
        let (previewView, preferences) = prefireSnapshot.loadViewWithPreferences()

        let failure = verifySnapshot(
            of: previewView,
            as: .wait(
                for: preferences.delay,
                on: .image(
                    precision: preferences.precision,
                    perceptualPrecision: preferences.perceptualPrecision,
                    layout: prefireSnapshot.isScreen ? .device(config: prefireSnapshot.device.imageConfig) : .sizeThatFits,
                    traits: prefireSnapshot.traits
                )
            ),
            record: preferences.record{% if argument.file %},
            file: file{% endif %},
            testName: prefireSnapshot.name
        )

        #if canImport(AccessibilitySnapshot)
            let vc = UIHostingController(rootView: previewView)
            vc.view.frame = UIScreen.main.bounds

            SnapshotTesting.assertSnapshot(
                matching: vc,
                as: .wait(for: preferences.delay, on: .accessibilityImage(showActivationPoints: .always)){% if argument.file %},
                record: preferences.record,
                file: file{% endif %},
                testName: prefireSnapshot.name + ".accessibility"
            )
        #endif
        return failure
    }

    /// Check environments to avoid problems with snapshots on different devices or OS.
    private func checkEnvironments() {
        if let simulatorDevice, let deviceModel = ProcessInfo().environment["SIMULATOR_MODEL_IDENTIFIER"] {
            guard deviceModel.contains(simulatorDevice) else {
                fatalError("Switch to using \(simulatorDevice) for these tests. (You are using \(deviceModel))")
            }
        }

        if let requiredOSVersion {
            let osVersion = ProcessInfo().operatingSystemVersion
            guard osVersion.majorVersion == requiredOSVersion else {
                fatalError("Switch to iOS \(requiredOSVersion) for these tests. (You are using \(osVersion))")
            }
        }
    }
}

// MARK: - SnapshotTesting + Extensions

extension DeviceConfig {
    var imageConfig: ViewImageConfig { ViewImageConfig(safeArea: safeArea, size: size, traits: traits) }
}

extension ViewImageConfig {
    var deviceConfig: DeviceConfig { DeviceConfig(safeArea: safeArea, size: size, traits: traits) }
}

private extension PreviewDevice {
    func snapshotDevice() -> ViewImageConfig? {
        switch rawValue {
        #if os(iOS)
        case "iPhone 16 Pro Max", "iPhone 15 Pro Max", "iPhone 14 Pro Max", "iPhone 13 Pro Max", "iPhone 12 Pro Max":
            return .iPhone13ProMax
        case "iPhone 16 Pro", "iPhone 15 Pro", "iPhone 14 Pro", "iPhone 13 Pro", "iPhone 12 Pro":
            return .iPhone13Pro
        case "iPhone 16", "iPhone 15", "iPhone 14", "iPhone 13", "iPhone 12", "iPhone 11", "iPhone 10", "iPhone X":
            return .iPhoneX
        case "iPhone 6", "iPhone 6s", "iPhone 7", "iPhone 8", "iPhone SE (2nd generation)", "iPhone SE (3rd generation)":
            return .iPhone8
        case "iPhone 6 Plus", "iPhone 6s Plus", "iPhone 8 Plus":
            return .iPhone8Plus
        case "iPhone SE (1st generation)":
            return .iPhoneSe
        case "iPad":
            return .iPad10_2
        case "iPad Mini":
            return .iPadMini
        case "iPad Pro 11":
            return .iPadPro11
        case "iPad Pro 12.9":
            return .iPadPro12_9
        #elseif os(tvOS)
        case "Apple TV":
            return .tv
        #endif
        default: return nil
        }
    }

    func snapshotDevice() -> DeviceConfig? {
        (self.snapshotDevice())?.deviceConfig
    }
}
"""#
}
