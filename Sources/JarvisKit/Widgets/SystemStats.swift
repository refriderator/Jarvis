import Darwin
import Foundation

/// One reading of how busy the Mac is, roughly what Activity Monitor shows.
public struct StatsSample: Sendable, Equatable {
    /// All cores together, 0...1.
    public var cpu: Double
    public var memoryUsed: UInt64
    public var memoryTotal: UInt64
    /// Bytes per second over every network interface.
    public var netIn: Double
    public var netOut: Double
    /// Memory macOS has squeezed in place to make room ("Compressed" in Activity Monitor).
    public var compressed: UInt64 = 0
    /// Memory written out to disk ("Swap Used").
    public var swapUsed: UInt64 = 0

    public init(cpu: Double, memoryUsed: UInt64, memoryTotal: UInt64, netIn: Double, netOut: Double,
                compressed: UInt64 = 0, swapUsed: UInt64 = 0) {
        self.compressed = compressed
        self.swapUsed = swapUsed
        self.cpu = cpu
        self.memoryUsed = memoryUsed
        self.memoryTotal = memoryTotal
        self.netIn = netIn
        self.netOut = netOut
    }

    public var memory: Double { memoryTotal == 0 ? 0 : Double(memoryUsed) / Double(memoryTotal) }
}

/// The last minute of readings, for the graphs.
public struct StatsHistory: Sendable, Equatable {
    public static let length = 60
    public private(set) var cpu: [Double] = []
    public private(set) var memory: [Double] = []
    /// Bytes per second.
    public private(set) var netIn: [Double] = []
    public private(set) var netOut: [Double] = []
    public private(set) var latest: StatsSample?

    public init() {}

    public mutating func add(_ sample: StatsSample) {
        latest = sample
        cpu = Array((cpu + [sample.cpu]).suffix(Self.length))
        memory = Array((memory + [sample.memory]).suffix(Self.length))
        netIn = Array((netIn + [sample.netIn]).suffix(Self.length))
        netOut = Array((netOut + [sample.netOut]).suffix(Self.length))
    }
}

/// Reads the counters macOS keeps (the same ones Activity Monitor reads). Each reading is the change since
/// the last one, so the first call only sets the baseline and returns nil.
public final class SystemStatsSampler {
    private var lastTicks: (busy: UInt64, total: UInt64)?
    private var lastNet: (inBytes: UInt64, outBytes: UInt64)?
    /// The CPU counters only move in coarse steps; with no new ticks since the last reading, this one stands.
    private var lastCPU = 0.0
    private var lastTime: UInt64 = 0

    public init() {}

    public func sample() -> StatsSample? {
        let now = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
        let seconds = Double(now - lastTime) / 1e9
        let first = lastTime == 0
        lastTime = now

        let ticks = cpuTicks()
        let net = networkBytes()
        // No new ticks yet: keep the old baseline so the next reading spans the whole gap.
        let ticksMoved = ticks.map { $0.total != lastTicks?.total } ?? false
        defer {
            if ticksMoved || lastTicks == nil { lastTicks = ticks }
            lastNet = net
        }
        guard !first, seconds > 0, let ticks, let last = lastTicks, let net, let lastNet else { return nil }

        let total = ticks.total - last.total
        let cpu = total == 0 ? lastCPU : Double(ticks.busy - last.busy) / Double(total)
        lastCPU = cpu
        let memory = memoryCounters()
        return StatsSample(cpu: cpu, memoryUsed: memory.used, memoryTotal: ProcessInfo.processInfo.physicalMemory,
                           netIn: Double(net.inBytes &- lastNet.inBytes) / seconds,
                           netOut: Double(net.outBytes &- lastNet.outBytes) / seconds,
                           compressed: memory.compressed, swapUsed: Self.swapUsed())
    }

    // MARK: Counters

    private func cpuTicks() -> (busy: UInt64, total: UInt64)? {
        var load = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &load) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let t = load.cpu_ticks
        let busy = UInt64(t.0) + UInt64(t.1) + UInt64(t.3)  // user, system, nice
        return (busy, busy + UInt64(t.2))                   // + idle
    }

    /// What Activity Monitor calls "Memory Used" (app memory, wired and compressed), and the compressed part.
    private func memoryCounters() -> (used: UInt64, compressed: UInt64) {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return (0, 0) }
        let page = UInt64(getpagesize())
        let pages = UInt64(stats.internal_page_count) - UInt64(stats.purgeable_count)
            + UInt64(stats.wire_count) + UInt64(stats.compressor_page_count)
        return (pages * page, UInt64(stats.compressor_page_count) * page)
    }

    /// Swap in use on disk (`sysctl vm.swapusage`).
    static func swapUsed() -> UInt64 {
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        guard sysctlbyname("vm.swapusage", &usage, &size, nil, 0) == 0 else { return 0 }
        return usage.xsu_used
    }

    /// Bytes in and out so far over every interface but loopback. The counters are 32-bit and wrap around
    /// every 4 GB, so they're summed as 32-bit and differenced with wrapping subtraction.
    private func networkBytes() -> (inBytes: UInt64, outBytes: UInt64)? {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return nil }
        defer { freeifaddrs(list) }
        var inBytes: UInt32 = 0, outBytes: UInt32 = 0
        for entry in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let interface = entry.pointee
            guard interface.ifa_addr?.pointee.sa_family == UInt8(AF_LINK),
                  String(cString: interface.ifa_name) != "lo0",
                  let data = interface.ifa_data?.assumingMemoryBound(to: if_data.self).pointee else { continue }
            inBytes &+= data.ifi_ibytes
            outBytes &+= data.ifi_obytes
        }
        return (UInt64(inBytes), UInt64(outBytes))
    }
}
