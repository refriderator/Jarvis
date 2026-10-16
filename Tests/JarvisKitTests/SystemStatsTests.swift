import Foundation
import JarvisKit
import Testing

struct SystemStatsTests {
    @Test func secondReadingIsPlausible() throws {
        let sampler = SystemStatsSampler()
        #expect(sampler.sample() == nil, "the first call only sets the baseline")
        // Keep a core busy so there's something to see.
        // The counters move in coarse steps, so spin until a reading has seen some.
        var sample = try #require(sampler.sample() ?? sampler.sample())
        let end = Date().addingTimeInterval(2)
        var spin = 0.0
        while sample.cpu == 0 && Date() < end {
            let until = Date().addingTimeInterval(0.1)
            while Date() < until { spin += sin(spin) }
            sample = try #require(sampler.sample())
        }
        #expect(sample.cpu > 0 && sample.cpu <= 1)
        #expect(sample.memoryUsed > 0 && sample.memoryUsed < sample.memoryTotal)
        #expect(sample.netIn >= 0 && sample.netOut >= 0)
        print("cpu \(sample.cpu) mem \(sample.memory) in \(sample.netIn) out \(sample.netOut)")
    }

    @Test func historyKeepsTheLastMinute() {
        var history = StatsHistory()
        for i in 0..<100 {
            history.add(StatsSample(cpu: Double(i) / 100, memoryUsed: 1, memoryTotal: 2, netIn: Double(i), netOut: 0))
        }
        #expect(history.cpu.count == StatsHistory.length)
        #expect(history.cpu.last == 0.99)
        #expect(history.memory.last == 0.5)
        #expect(history.netIn.count == StatsHistory.length && history.netIn.last == 99)
    }
}

struct SystemStatsCostTests {
    @Test func oneReadingIsCheap() {
        let sampler = SystemStatsSampler()
        _ = sampler.sample()
        let clock = ContinuousClock()
        let took = clock.measure { for _ in 0..<10 { _ = sampler.sample() } }
        print("one reading takes \(took / 10)")
        #expect(took / 10 < .milliseconds(50))
    }
}
