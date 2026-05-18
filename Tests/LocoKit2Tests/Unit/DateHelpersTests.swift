import Testing
import Foundation
@testable import LocoKit2

// Day-boundary math is a classic bug magnet (DST, month/year rollovers,
// non-current time zones) and feeds visit-time stats via sinceStartOfDay,
// so it is tested with explicit fixed calendars rather than .current.
@Suite struct DateHelpersTests {

    private var utc: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    private var newYork: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        return c
    }

    private func date(_ cal: Calendar, _ y: Int, _ mo: Int, _ d: Int,
                      _ h: Int = 0, _ mi: Int = 0, _ s: Int = 0) -> Date {
        cal.date(from: DateComponents(
            year: y, month: mo, day: d, hour: h, minute: mi, second: s
        ))!
    }

    // MARK: - start / since start of day

    @Test func sinceStartOfDayIsSecondsSinceMidnight() {
        let d = date(utc, 2023, 6, 15, 13, 45, 30)
        #expect(d.startOfDay(in: utc) == date(utc, 2023, 6, 15, 0, 0, 0))
        #expect(d.sinceStartOfDay(in: utc) == 13 * 3600 + 45 * 60 + 30)
        #expect(d.dayOfMonth(in: utc) == 15)
    }

    @Test func endOfDayIsStartOfNextDay() {
        let d = date(utc, 2023, 6, 15, 13, 0, 0)
        #expect(d.endOfDay(in: utc) == d.nextDay(in: utc).startOfDay(in: utc))
    }

    // MARK: - next / previous / add / subtract, across boundaries

    @Test(arguments: [
        (y: 2023, mo: 1, d: 31, ny: 2023, nmo: 2, nd: 1),    // month rollover
        (y: 2023, mo: 12, d: 31, ny: 2024, nmo: 1, nd: 1),   // year rollover
        (y: 2024, mo: 2, d: 28, ny: 2024, nmo: 2, nd: 29),   // leap day
    ])
    func nextDayCrossesBoundaries(_ a: (y: Int, mo: Int, d: Int, ny: Int, nmo: Int, nd: Int)) {
        let start = date(utc, a.y, a.mo, a.d, 9)
        let next = start.nextDay(in: utc)
        #expect(utc.component(.year, from: next) == a.ny)
        #expect(utc.component(.month, from: next) == a.nmo)
        #expect(utc.component(.day, from: next) == a.nd)
        #expect(next.previousDay(in: utc) == start)
    }

    @Test func addAndSubtractDaysAreInverse() {
        let d = date(utc, 2023, 6, 15, 13, 45, 30)
        #expect(d.adding(days: 10, in: utc).subtracting(days: 10, in: utc) == d)
        #expect(d.adding(days: 0, in: utc) == d)
    }

    @Test func sameDayAndSameMonthComparisons() {
        let d = date(utc, 2023, 6, 15, 1, 0, 0)
        #expect(d.isSameDayAs(date(utc, 2023, 6, 15, 23, 59, 59), in: utc))
        #expect(!d.isSameDayAs(d.nextDay(in: utc), in: utc))
        #expect(d.isSameMonthAs(date(utc, 2023, 6, 30), in: utc))
        #expect(!d.isSameMonthAs(date(utc, 2023, 7, 1), in: utc))
    }

    // MARK: - DST correctness (the actual bug-prone part)

    @Test func springForwardDayIs23HoursLong() {
        // 2023-03-12: clocks jump 02:00 -> 03:00 in America/New_York
        let day = date(newYork, 2023, 3, 12, 12)
        let span = day.endOfDay(in: newYork).timeIntervalSince(day.startOfDay(in: newYork))
        #expect(span == 23 * 3600)
    }

    @Test func fallBackDayIs25HoursLong() {
        // 2023-11-05: clocks fall 02:00 -> 01:00 in America/New_York
        let day = date(newYork, 2023, 11, 5, 12)
        let span = day.endOfDay(in: newYork).timeIntervalSince(day.startOfDay(in: newYork))
        #expect(span == 25 * 3600)
    }

    @Test func addingDayPreservesWallClockAcrossDST() {
        // calendar day arithmetic must keep the same local hour, not add 24h
        let day = date(newYork, 2023, 3, 11, 12)   // day before spring forward
        let nextWallNoon = day.adding(days: 1, in: newYork)
        #expect(newYork.component(.hour, from: nextWallNoon) == 12)
        // and it is NOT a naive +86400 (that day is only 23h long)
        #expect(nextWallNoon.timeIntervalSince(day) == 23 * 3600)
    }

    @Test func sinceStartOfDayStaysWithinOneDayEvenOnDST() {
        for (mo, d) in [(3, 12), (11, 5)] {
            let t = date(newYork, 2023, mo, d, 15, 30)
            let since = t.sinceStartOfDay(in: newYork)
            #expect(since >= 0)
            #expect(since < .hours(26))
        }
    }

    // MARK: - DateInterval helpers (hand-rolled containment, not overlap)

    @Test func dateIntervalContainmentIsInclusive() {
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        let outer = DateInterval(start: t0, end: t0 + 10)

        #expect(outer.contains(DateInterval(start: t0 + 2, end: t0 + 8)))
        #expect(outer.contains(outer))                                   // identical -> contained
        #expect(outer.contains(DateInterval(start: t0 + 10, end: t0 + 10))) // touching end
        #expect(!outer.contains(DateInterval(start: t0 - 1, end: t0 + 5))) // starts before
        #expect(!outer.contains(DateInterval(start: t0 + 5, end: t0 + 11)))// ends after
        #expect(outer.range == t0 ... (t0 + 10))
    }
}
