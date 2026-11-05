import Foundation
import IOKit
import IOKit.ps

struct PowerReading: Sendable {
    let adapterRatingWatts: Double?
    let inputWatts: Double?
    let systemWatts: Double?
    let batteryWatts: Double? // Positive = charging, negative = discharging.
}

enum PowerSampler {
    static func read() -> PowerReading? {
        let rating = (IOPSCopyExternalPowerAdapterDetails()?.takeRetainedValue() as? [String: Any])
            .flatMap { watts($0[kIOPSPowerAdapterWattsKey], divisor: 1) }

        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else {
            return rating.map { PowerReading(adapterRatingWatts: $0, inputWatts: nil,
                                             systemWatts: nil, batteryWatts: nil) }
        }
        defer { IOObjectRelease(service) }

        func property(_ key: String) -> Any? {
            IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
        }
        let telemetry = property("PowerTelemetryData") as? [String: Any]
        // These IORegistry telemetry fields are milliwatts, and not available on every Mac.
        let input = watts(telemetry?["SystemPowerIn"], divisor: 1_000)
        let system = watts(telemetry?["SystemLoad"], divisor: 1_000)

        // Signed battery current in mA times voltage in mV gives net watts.
        // Positive current charges the battery; negative current discharges it,
        // including when an adapter is connected but system demand is too high.
        let current = number(property("InstantAmperage")) ?? number(property("Amperage"))
        let voltage = number(property("Voltage"))
        let battery = (current != nil && voltage != nil && voltage! > 0)
            ? (current! * voltage! / 1_000_000) : nil
        let batteryWatts = battery.flatMap { $0.isFinite && abs($0) < 1_000 ? $0 : nil }

        guard rating != nil || input != nil || system != nil || batteryWatts != nil else { return nil }
        return PowerReading(adapterRatingWatts: rating, inputWatts: input,
                            systemWatts: system, batteryWatts: batteryWatts)
    }

    private static func number(_ value: Any?) -> Double? {
        guard let value = value as? NSNumber else { return nil }
        return value.doubleValue.isFinite ? value.doubleValue : nil
    }

    private static func watts(_ value: Any?, divisor: Double) -> Double? {
        guard let number = number(value), number >= 0, number < 1_000_000 else { return nil }
        return number / divisor
    }
}
