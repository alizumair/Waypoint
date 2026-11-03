import Foundation

public enum NetworkUtilities {
    /// Discovers the active local Wi-Fi / Ethernet IPv4 address of this Mac.
    public static func getLocalIPAddress() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else {
            return nil
        }
        defer { freeifaddrs(ifaddr) }
        
        for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let interface = ptr.pointee
            let addrFamily = interface.ifa_addr.pointee.sa_family
            
            // Look for IPv4 interfaces (AF_INET)
            if addrFamily == UInt8(AF_INET) {
                let name = String(cString: interface.ifa_name)
                // Filter out loopback (lo0) and bridge/virtual interfaces if primary en0/en1 exists
                if name.hasPrefix("en") || name.hasPrefix("eth") || name.hasPrefix("wlan") {
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    if getnameinfo(interface.ifa_addr,
                                   socklen_t(interface.ifa_addr.pointee.sa_len),
                                   &hostname,
                                   socklen_t(hostname.count),
                                   nil,
                                   0,
                                   NI_NUMERICHOST) == 0 {
                    let ip = hostname.withUnsafeBufferPointer { ptr -> String in
                        guard let base = ptr.baseAddress else { return "" }
                        return String(cString: base)
                    }
                    if !ip.isEmpty && !ip.hasPrefix("127.") {
                        address = ip
                        if name == "en0" {
                            break
                        }
                    }
                    }
                }
            }
        }
        
        // Fallback: If no enX match, return first non-loopback AF_INET
        if address == nil {
            for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
                let interface = ptr.pointee
                if interface.ifa_addr.pointee.sa_family == UInt8(AF_INET) {
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    if getnameinfo(interface.ifa_addr,
                                   socklen_t(interface.ifa_addr.pointee.sa_len),
                                   &hostname,
                                   socklen_t(hostname.count),
                                   nil,
                                   0,
                                   NI_NUMERICHOST) == 0 {
                        let ip = hostname.withUnsafeBufferPointer { ptr -> String in
                            guard let base = ptr.baseAddress else { return "" }
                            return String(cString: base)
                        }
                        if !ip.isEmpty && !ip.hasPrefix("127.") {
                            address = ip
                            break
                        }
                    }
                }
            }
        }
        
        return address
    }
}
