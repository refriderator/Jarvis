import Foundation
import JarvisKit
import Testing

/// Today's Notion items are decided in local time: evening items in Toronto (UTC−4) are past midnight UTC, and
/// Notion's own date filter used to drop them.
struct NotionDueWindowTests {
    let toronto = TimeZone(identifier: "America/Toronto")!
    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = toronto
        return calendar
    }
    /// Oct 16 2026, 3 PM in Toronto.
    var now: Date { NotionAPI.date("2026-10-16T15:00:00-04:00")!.date }

    func isToday(_ raw: String) -> Bool {
        NotionAPI.isWithin(NotionAPI.date(raw, timeZone: toronto)!, days: 1, now: now, calendar: calendar)
    }

    @Test func eveningItemsStayOnToday() {
        #expect(isToday("2026-10-16T16:00:00.000-04:00"), "4 PM, 20:00Z")
        #expect(isToday("2026-10-16T20:00:00.000-04:00"), "8 PM, 00:00Z the next day")
        #expect(isToday("2026-10-16T22:00:00.000-04:00"), "10 PM, 02:00Z the next day")
        #expect(isToday("2026-10-16T23:59:00.000-04:00"))
        #expect(isToday("2026-10-17T01:00:00.000Z"), "written in UTC: 9 PM here")
    }

    @Test func otherDaysAreLeftOut() {
        #expect(!isToday("2026-10-15T22:00:00.000-04:00"), "last night")
        #expect(!isToday("2026-10-17T00:00:00.000-04:00"), "midnight tonight is tomorrow")
    }

    @Test func dateOnlyItemsGoByTheirDate() {
        #expect(isToday("2026-10-16"))
        #expect(!isToday("2026-10-15"))
        #expect(!isToday("2026-10-17"))
    }

    @Test func overdueItemsComeBackWhenAskedFor() {
        let late = NotionAPI.date("2026-10-10", timeZone: toronto)!
        #expect(!NotionAPI.isWithin(late, days: 1, now: now, calendar: calendar))
        #expect(NotionAPI.isWithin(late, days: 1, overdueDays: 30, now: now, calendar: calendar))
        let ancient = NotionAPI.date("2026-08-01", timeZone: toronto)!
        #expect(!NotionAPI.isWithin(ancient, days: 1, overdueDays: 30, now: now, calendar: calendar), "past the cap")
    }
}
