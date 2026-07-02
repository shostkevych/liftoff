import SwiftUI
import CoreImage.CIFilterBuiltins

/// Discovers the Mac's reachable LAN/VPN addresses and packs them into the
/// QR payload the iOS companion scans to pair (Air → Connect).
enum AirPairing {
    /// All non-loopback IPv4 addresses this machine currently has, most
    /// useful (private LAN ranges) first so the phone tries those first.
    static func localIPv4Addresses() -> [String] {
        var addresses: [String] = []
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return [] }
        defer { freeifaddrs(ifaddr) }

        for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let flags = Int32(ptr.pointee.ifa_flags)
            // Skip down / loopback interfaces.
            guard flags & (IFF_UP | IFF_LOOPBACK) == IFF_UP else { continue }
            guard let addr = ptr.pointee.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET) else { continue }

            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let result = getnameinfo(addr, socklen_t(addr.pointee.sa_len),
                                     &host, socklen_t(host.count),
                                     nil, 0, NI_NUMERICHOST)
            guard result == 0 else { continue }
            let ip = String(cString: host)
            guard !ip.isEmpty, ip != "127.0.0.1" else { continue }
            if !addresses.contains(ip) { addresses.append(ip) }
        }
        return addresses.sorted { lhs, rhs in
            // Private LAN ranges (10/172.16/192.168) ahead of anything else.
            isPrivate(lhs) && !isPrivate(rhs)
        }
    }

    private static func isPrivate(_ ip: String) -> Bool {
        ip.hasPrefix("10.") || ip.hasPrefix("192.168.") || (ip.hasPrefix("172.") && {
            let second = Int(ip.split(separator: ".").dropFirst().first ?? "0") ?? 0
            return (16...31).contains(second)
        }())
    }

    /// JSON payload encoded into the QR code:
    /// `{"v":2,"port":48624,"name":"<host>","ips":[...],"token":"<base64>"}`
    /// v=2 adds the persistent auth token so the iOS companion can authenticate
    /// without a separate pairing step. The token is generated once and persisted
    /// in ~/.liftoff/settings.json.
    static func payload(ips: [String]) -> String {
        let token = SettingsStore.load().companionToken
        let dict: [String: Any] = [
            "v": 2,
            "port": Int(CompanionServer.port),
            "name": Host.current().localizedName ?? "Mac",
            "ips": ips,
            "token": token,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let json = String(data: data, encoding: .utf8) else { return "" }
        return json
    }

    /// Convenience that scans interfaces itself. Prefer `payload(ips:)` with a
    /// cached/scanned-once list to avoid re-running getifaddrs per render.
    static func payload() -> String { payload(ips: localIPv4Addresses()) }

    /// Render `string` as a crisp black-on-clear QR `NSImage` sized to `side` points.
    static func qrImage(from string: String, side: CGFloat) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scale = side / output.extent.width
        let scaled = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let context = CIContext()
        guard let cg = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: side, height: side))
    }
}
