//
//  CodDecoder.swift
//  FieldwatchCore
//
//  نقل 1:1 لـ CodDecoder.kt — Bluetooth Class of Device (Assigned Numbers)، 24-bit.
//

import Foundation

public enum CodDecoder {

    public struct Decoded: Sendable, Equatable {
        public var major: String
        public var minor: String
        public var services: [String]
        public var raw: Int

        public init(major: String, minor: String, services: [String], raw: Int) {
            self.major = major; self.minor = minor; self.services = services; self.raw = raw
        }

        /// Kotlin: summary()
        public func summary() -> String {
            var out = major
            if !minor.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && minor != "Uncategorized" {
                out += " / "
                out += minor
            }
            if !services.isEmpty {
                out += " · "
                out += services.joined(separator: ", ")
            }
            return out
        }
    }

    public static func decode(_ cod: Int) -> Decoded {
        let format = cod & 0x3
        let minorBits = (cod >> 2) & 0x3F
        let majorBits = (cod >> 8) & 0x1F
        let serviceBits = (cod >> 13) & 0x7FF
        let major = majorName(majorBits)
        let minor = format != 0 ? "format \(format)" : minorName(majorBits, minorBits)
        return Decoded(major: major, minor: minor,
                       services: serviceNames(serviceBits), raw: cod & 0xFFFFFF)
    }

    public static func decodeOrNull(_ cod: Int?) -> Decoded? {
        guard let cod, cod != 0 else { return nil }
        return decode(cod)
    }

    // MARK: - Private (نفس جداول Kotlin)

    private static func majorName(_ major: Int) -> String {
        switch major {
        case 0x00: return "Miscellaneous"
        case 0x01: return "Computer"
        case 0x02: return "Phone"
        case 0x03: return "LAN / Network AP"
        case 0x04: return "Audio / Video"
        case 0x05: return "Peripheral"
        case 0x06: return "Imaging"
        case 0x07: return "Wearable"
        case 0x08: return "Toy"
        case 0x09: return "Health"
        case 0x1F: return "Uncategorized"
        default: return String(format: "Major 0x%02X", major)
        }
    }

    private static func minorName(_ major: Int, _ minor: Int) -> String {
        switch major {
        case 0x01:
            switch minor {
            case 0x00: return "Uncategorized"
            case 0x01: return "Desktop"
            case 0x02: return "Server"
            case 0x03: return "Laptop"
            case 0x04: return "Handheld PC/PDA"
            case 0x05: return "Palm-size PDA"
            case 0x06: return "Wearable computer"
            case 0x07: return "Tablet"
            default: return String(format: "Computer 0x%02X", minor)
            }

        case 0x02:
            switch minor {
            case 0x00: return "Uncategorized"
            case 0x01: return "Cellular"
            case 0x02: return "Cordless"
            case 0x03: return "Smartphone"
            case 0x04: return "Wired modem / voice gateway"
            case 0x05: return "Common ISDN access"
            default: return String(format: "Phone 0x%02X", minor)
            }

        case 0x03:
            switch (minor >> 3) & 0x7 {
            case 0: return "Fully available"
            case 1: return "1–17% utilized"
            case 2: return "17–33% utilized"
            case 3: return "33–50% utilized"
            case 4: return "50–67% utilized"
            case 5: return "67–83% utilized"
            case 6: return "83–99% utilized"
            default: return "No service available"
            }

        case 0x04:
            switch minor {
            case 0x00: return "Uncategorized"
            case 0x01: return "Wearable headset"
            case 0x02: return "Hands-free"
            case 0x04: return "Microphone"
            case 0x05: return "Loudspeaker"
            case 0x06: return "Headphones"
            case 0x07: return "Portable audio"
            case 0x08: return "Car audio"
            case 0x09: return "Set-top box"
            case 0x0A: return "HiFi audio"
            case 0x0B: return "VCR"
            case 0x0C: return "Video camera"
            case 0x0D: return "Camcorder"
            case 0x0E: return "Video monitor"
            case 0x0F: return "Video display and loudspeaker"
            case 0x10: return "Video conferencing"
            case 0x12: return "Gaming / toy"
            default: return String(format: "A/V 0x%02X", minor)
            }

        case 0x05:
            let sense = minor & 0x0F
            let hid = (minor >> 4) & 0x3
            let kind: String
            switch sense {
            case 0x00: kind = "Uncategorized"
            case 0x01: kind = "Joystick"
            case 0x02: kind = "Gamepad"
            case 0x03: kind = "Remote control"
            case 0x04: kind = "Sensing device"
            case 0x05: kind = "Digitizer tablet"
            case 0x06: kind = "Card reader"
            case 0x07: kind = "Digital pen"
            case 0x08: kind = "Handheld scanner"
            case 0x09: kind = "Handheld gestural input"
            default: kind = String(format: "Peripheral 0x%X", sense)
            }
            let extra: String?
            switch hid {
            case 1: extra = "keyboard"
            case 2: extra = "pointing"
            case 3: extra = "keyboard/pointing"
            default: extra = nil
            }
            if extra == nil { return kind }
            if sense == 0 { return capitalizeFirst(extra!) }
            return "\(kind) + \(extra!)"

        case 0x06:
            var parts = [String]()
            if minor & 0x08 != 0 { parts.append("Display") }
            if minor & 0x04 != 0 { parts.append("Camera") }
            if minor & 0x02 != 0 { parts.append("Scanner") }
            if minor & 0x01 != 0 { parts.append("Printer") }
            let joined = parts.joined(separator: " + ")
            return joined.isEmpty ? "Uncategorized" : joined

        case 0x07:
            switch minor {
            case 0x01: return "Wristwatch"
            case 0x02: return "Pager"
            case 0x03: return "Jacket"
            case 0x04: return "Helmet"
            case 0x05: return "Glasses"
            default: return String(format: "Wearable 0x%02X", minor)
            }

        case 0x08:
            switch minor {
            case 0x01: return "Robot"
            case 0x02: return "Vehicle"
            case 0x03: return "Doll / action figure"
            case 0x04: return "Controller"
            case 0x05: return "Game"
            default: return String(format: "Toy 0x%02X", minor)
            }

        case 0x09:
            switch minor {
            case 0x01: return "Blood pressure monitor"
            case 0x02: return "Thermometer"
            case 0x03: return "Weighing scale"
            case 0x04: return "Glucose meter"
            case 0x05: return "Pulse oximeter"
            case 0x06: return "Heart / pulse rate monitor"
            case 0x07: return "Health data display"
            case 0x08: return "Step counter"
            case 0x09: return "Body composition analyzer"
            case 0x0A: return "Peak flow monitor"
            case 0x0B: return "Medication monitor"
            case 0x0C: return "Knee prosthesis"
            case 0x0D: return "Ankle prosthesis"
            case 0x0E: return "Generic health manager"
            case 0x0F: return "Personal mobility device"
            default: return String(format: "Health 0x%02X", minor)
            }

        default:
            return minor == 0 ? "" : String(format: "0x%02X", minor)
        }
    }

    private static func serviceNames(_ bits: Int) -> [String] {
        var out = [String]()
        if bits & 0x001 != 0 { out.append("Limited Discoverable") }
        if bits & 0x008 != 0 { out.append("Positioning") }
        if bits & 0x010 != 0 { out.append("Networking") }
        if bits & 0x020 != 0 { out.append("Rendering") }
        if bits & 0x040 != 0 { out.append("Capturing") }
        if bits & 0x080 != 0 { out.append("Object Transfer") }
        if bits & 0x100 != 0 { out.append("Audio") }
        if bits & 0x200 != 0 { out.append("Telephony") }
        if bits & 0x400 != 0 { out.append("Information") }
        return out
    }

    private static func capitalizeFirst(_ s: String) -> String {
        guard let f = s.first else { return s }
        return String(f).uppercased() + s.dropFirst()
    }
}
