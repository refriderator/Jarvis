import Foundation
import JarvisKit
import Testing

struct BrowserTabsTests {
    @Test func opensAfterTheTabShowingAndClosesToItsNeighbour() {
        var tabs = BrowserTabs()
        let first = tabs.selected
        let second = tabs.open(URL(string: "https://a.com"))
        tabs.select(first)
        let between = tabs.open()
        #expect(tabs.tabs.map(\.id) == [first, between, second])
        tabs.close(between)
        #expect(tabs.selected == second, "the one after it shows")
        tabs.close(second)
        #expect(tabs.selected == first, "the last one closed: the one before shows")
        tabs.close(first)
        #expect(tabs.tabs.count == 1 && tabs.current.url == nil, "closing the last leaves a start page")
    }

    @Test func dragReorders() {
        var tabs = BrowserTabs()
        let a = tabs.selected, b = tabs.open(), c = tabs.open()
        tabs.move(c, to: a)
        #expect(tabs.tabs.map(\.id) == [c, a, b])
        tabs.move(c, to: b)
        #expect(tabs.tabs.map(\.id) == [a, b, c])
    }

    @Test func addressesAndSearches() {
        #expect(BrowserTabs.address("apple.com")?.absoluteString == "https://apple.com")
        #expect(BrowserTabs.address("https://q.utoronto.ca/courses")?.absoluteString == "https://q.utoronto.ca/courses")
        #expect(BrowserTabs.address("localhost:8080")?.absoluteString == "http://localhost:8080")
        #expect(BrowserTabs.address("phy224 midterm")?.host() == "www.google.com")
        #expect(BrowserTabs.address("   ") == nil)
    }

    @Test func labels() {
        #expect(BrowserTab().label == "New Tab")
        #expect(BrowserTab(url: URL(string: "https://www.github.com/x")).label == "github.com")
    }
}

struct PasswordStoreTests {
    @Test func savesReplacesAndDeletes() {
        let host = "jarvis-test-\(UUID().uuidString.prefix(8)).example"
        defer { PasswordStore.logins(for: host).forEach(PasswordStore.delete) }
        #expect(PasswordStore.logins(for: host).isEmpty)
        #expect(PasswordStore.save(SavedLogin(host: host, username: "me", password: "one")))
        #expect(PasswordStore.save(SavedLogin(host: host, username: "me", password: "two")))
        #expect(PasswordStore.logins(for: host) == [SavedLogin(host: host, username: "me", password: "two")],
                "one per username: saving again replaces it")
        #expect(PasswordStore.logins(for: "other-\(host)").isEmpty, "only that exact host")
        PasswordStore.delete(SavedLogin(host: host, username: "me", password: ""))
        #expect(PasswordStore.logins(for: host).isEmpty)
    }
}

struct PasswordSafetyTests {
    @Test func onlyPublicSitesOnTheStandardPort() {
        #expect(PasswordSafety.allows(host: "accounts.google.com", port: 0))
        #expect(PasswordSafety.allows(host: "q.utoronto.ca", port: 443))
        #expect(!PasswordSafety.allows(host: "example.com", port: 8443))
        #expect(!PasswordSafety.allows(host: "localhost", port: 0))
        #expect(!PasswordSafety.allows(host: "192.168.1.1", port: 0))
        #expect(!PasswordSafety.allows(host: "::1", port: 0))
        #expect(!PasswordSafety.allows(host: "printer.local", port: 0))
        #expect(!PasswordSafety.allows(host: "router", port: 0))
    }
}
