import Foundation

/// Which brains suit this Mac, and anything the user should know first.
public struct MacAdvice: Equatable, Sendable {
    public enum Fit: Sendable {
        /// Runs the bigger built-in model comfortably.
        case great
        case good
        /// Too little memory for a built-in model; Apple Intelligence instead.
        case light
        /// Intel: no local brain at all.
        case cloudOnly
    }

    public var fit: Fit
    public var localBrain: LocalBrain
    public var model: LocalModel?
    public var summary: String
    public var warnings: [String]

    /// Room left over after a download, so the Mac doesn't run out of disk.
    public static let spareDiskGB = 5

    public static func `for`(_ mac: MacProfile) -> MacAdvice {
        var warnings: [String] = []
        if !mac.hasNotch {
            warnings.append("No notch on this screen, so Jarvis shows as a small pill at the top instead.")
        }
        guard mac.isAppleSilicon else {
            warnings.append("Intel Macs can't run Apple Intelligence and are too slow for a built-in model, "
                            + "so every question goes to Claude.")
            return MacAdvice(fit: .cloudOnly, localBrain: .off, model: nil,
                             summary: "Claude for everything.", warnings: warnings)
        }

        var fit: Fit = mac.memoryGB >= 24 ? .great : mac.memoryGB >= 16 ? .good : .light
        let model = LocalModels.recommended(memoryGB: mac.memoryGB)
        if fit == .light {
            warnings.append("\(mac.memoryGB) GB of memory is tight for a built-in model; it would slow your other apps. "
                            + "Apple Intelligence + Claude is the better fit.")
        } else if mac.freeDiskGB < Int(model.bytes >> 30) + spareDiskGB {
            fit = .light
            warnings.append("Only \(mac.freeDiskGB) GB of disk is free, not enough for the \(model.sizeText) model. "
                            + "Using Apple Intelligence until there's more room.")
        }

        guard fit != .light else {
            if !mac.appleIntelligence {
                warnings.append("Apple Intelligence is off. Turn it on in System Settings › Apple Intelligence & Siri; "
                                + "until then small questions go to Claude too.")
            }
            return MacAdvice(fit: .light, localBrain: .apple, model: nil,
                             summary: "Apple Intelligence for small questions, Claude for the rest.", warnings: warnings)
        }
        if mac.isLaptop {
            warnings.append("The built-in model uses extra battery while it answers.")
        }
        return MacAdvice(fit: fit, localBrain: .builtIn, model: model,
                         summary: "Built-in \(model.name) for small questions, Claude for the rest.", warnings: warnings)
    }
}
