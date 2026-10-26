import Testing
import Foundation
import SwiftData
@testable import RyadomFeature

@Suite struct MonetizationTests {
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Moscow")!
        return c
    }

    private let start = Date(timeIntervalSince1970: 1_790_000_000)
    private func state(after seconds: TimeInterval, hasPlan: Bool = false, start: Date? = nil) -> AccessState {
        Monetization.state(hasPlan: hasPlan, trialStart: start ?? self.start, now: (start ?? self.start).addingTimeInterval(seconds), calendar: calendar)
    }

    private func daysLeft(_ state: AccessState) -> Int? {
        if case .trial(let days, _) = state { days } else { nil }
    }

    @Test func trialLastsFourteenDaysThenExpires() {
        #expect(Monetization.trialDays == 14)
        #expect(daysLeft(state(after: 0)) == 14)
        #expect(daysLeft(state(after: 60)) == 14)
        #expect(daysLeft(state(after: 13 * 86_400)) == 1)
        #expect(daysLeft(state(after: 14 * 86_400 - 1)) == 1)
        #expect(state(after: 14 * 86_400) == .expired)
        #expect(state(after: 30 * 86_400) == .expired)
    }

    @Test func daysLeftCountsDownEachDay() {
        let counts = (0..<14).map { daysLeft(state(after: Double($0) * 86_400 + 3_600)) }
        #expect(counts == (0..<14).map { 14 - $0 })
    }

    @Test func subscriptionAlwaysWins() {
        #expect(state(after: 100 * 86_400, hasPlan: true) == .subscribed)
        #expect(state(after: 0, hasPlan: true) == .subscribed)
    }

    @Test func unknownStartMeansTrialJustBegan() {
        let now = Date.now
        let result = Monetization.state(hasPlan: false, trialStart: nil, now: now, calendar: calendar)
        #expect(daysLeft(result) == 14)
    }

    @Test func accessibility() {
        #expect(AccessState.subscribed.hasAccess)
        #expect(AccessState.trial(daysLeft: 3, endsAt: .now).hasAccess)
        #expect(!AccessState.expired.hasAccess)
    }
}

@MainActor
struct TrialStoreTests {
    @Test func firstBeginWinsAndIsRemembered() {
        let store = InMemoryTrialStore()
        #expect(store.start() == nil)
        let first = Date(timeIntervalSince1970: 1_000)
        #expect(store.begin(at: first) == first)
        #expect(store.begin(at: first.addingTimeInterval(999_999)) == first, "повторный вызов не сдвигает начало")
        #expect(store.start() == first)
    }

    @Test func keychainKeepsStartBetweenCalls() {
        let service = "app.ryadom.trial.tests.\(UUID().uuidString)"
        let store = KeychainTrialStore(service: service)
        defer { store.reset() }
        #expect(store.start() == nil)
        let first = Date(timeIntervalSince1970: 2_000)
        #expect(store.begin(at: first) == first)
        // «Новая» установка того же приложения видит прежнюю дату.
        let again = KeychainTrialStore(service: service)
        #expect(again.begin(at: first.addingTimeInterval(86_400 * 30)) == first)
    }

    @Test func sessionStartsTrialOnceFromStore() throws {
        let context = ModelContext(RyadomSchema.makeContainer(inMemory: true))
        let family = FamilyRecord(id: UUID(), name: "Смирновы")
        context.insert(family)
        let earlier = Date.now.addingTimeInterval(-20 * 86_400)
        // В хранилище уже есть дата (например, после переустановки) — берётся она, а не «сейчас».
        let session = AppSession(userId: UUID(), familyId: family.id, trialStore: InMemoryTrialStore(start: earlier))
        session.ensureTrialStarted(context: context)
        #expect(family.trialStartedAt == earlier)
        #expect(family.accessState() == .expired)
        // Повторный вызов ничего не меняет.
        session.ensureTrialStarted(context: context)
        #expect(family.trialStartedAt == earlier)
    }

    @Test func subscribedFamilyIgnoresOldTrial() {
        let family = FamilyRecord(id: UUID(), name: "Смирновы", plan: "plus")
        family.trialStartedAt = Date.now.addingTimeInterval(-90 * 86_400)
        #expect(family.accessState() == .subscribed)
    }
}
