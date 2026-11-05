import Foundation
import IOKit.ps

struct BatteryReading: Sendable {
    let level: Double // Fraction from 0 to 1.
    let isCharging: Bool
    let isPluggedIn: Bool
}

enum BatterySampler {
    static func read() -> BatteryReading? {
        let info = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let sources = IOPSCopyPowerSourcesList(info).takeRetainedValue() as NSArray
        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(info, source as CFTypeRef)?
                .takeUnretainedValue() as? [String: Any],
                description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                description[kIOPSIsPresentKey] as? Bool == true,
                let current = description[kIOPSCurrentCapacityKey] as? Int,
                let maximum = description[kIOPSMaxCapacityKey] as? Int,
                maximum > 0 else { continue }

            return BatteryReading(
                level: min(1, max(0, Double(current) / Double(maximum))),
                isCharging: description[kIOPSIsChargingKey] as? Bool ?? false,
                isPluggedIn: description[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue
            )
        }
        return nil
    }
}
