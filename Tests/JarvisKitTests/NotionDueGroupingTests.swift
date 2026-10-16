import Foundation
import JarvisKit
import Testing

struct NotionDueGroupingTests {
    @Test func examsAreToldApartByTheirTitle() {
        for exam in ["MIDTERM!!!!! PHY224", "MAT244 Quiz DUE", "Test 1 – Psych", "Final Exam", "Calc test 2", "CHM136 midterms"] {
            #expect(NotionAPI.isExam(exam), "\(exam)")
        }
        for work in ["STA237 Lec (PB B250)", "PHY254 Practice and PS2 work", "Lab Report – Chem", "Contest entry",
                     "Testing notes draft", "Online PS"] {
            #expect(!NotionAPI.isExam(work), "\(work)")
        }
    }

    @Test func groupedListsExamsThenCourseworkEachSoonestFirst() {
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        func item(_ title: String, days: Double) -> DueItem {
            DueItem(id: title, title: title, due: now.addingTimeInterval(days * 86_400), hasTime: false, source: "School")
        }
        let text = NotionAPI.grouped([item("Lab Report", days: 1), item("PHY224 Midterm", days: 2),
                                      item("Essay draft", days: 3), item("MAT244 Quiz", days: 4)], days: 14, now: now)
        let lines = text.split(separator: "\n").map(String.init)
        #expect(lines.first == "Exams:")
        #expect(lines[1].hasPrefix("- PHY224 Midterm"))
        #expect(lines[2].hasPrefix("- MAT244 Quiz"))
        #expect(lines[3] == "Coursework:")
        #expect(lines[4].hasPrefix("- Lab Report"))
        #expect(!text.contains("Exams:\nCoursework:"))
        #expect(NotionAPI.grouped([], days: 7, now: now) == "Nothing due in the next 7 days.")
        #expect(!NotionAPI.grouped([item("Lab Report", days: 1)], days: 7, now: now).contains("Exams:"),
                "no empty group heading")
    }
}
