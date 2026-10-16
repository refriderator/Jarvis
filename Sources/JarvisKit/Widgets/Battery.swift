import Foundation
import IOKit.ps

/// The internal battery's charge, for the notch's ticker.
public struct Battery: Equatable, Sendable {
    public var percent: Int
    public var charging: Bool

    public init(percent: Int, charging: Bool) {
        self.percent = percent
        self.charging = charging
    }

    /// nil on a Mac without a battery (an iMac, a Mac mini).
    public static func current() -> Battery? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  let now = description[kIOPSCurrentCapacityKey] as? Int,
                  let max = description[kIOPSMaxCapacityKey] as? Int, max > 0 else { continue }
            return Battery(percent: now * 100 / max, charging: description[kIOPSIsChargingKey] as? Bool ?? false)
        }
        return nil
    }
}
