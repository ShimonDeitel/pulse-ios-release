import Foundation

// MARK: - DailyAIBudget
//
// Splits the tier's monthly AI budget evenly across the days of the current
// month, then debits real DeepSeek spend against today's slice. When today's
// slice is gone the app shows "Usage limit hit — resets tomorrow" and AI is
// paused until midnight, at which point a fresh day-key gives a clean allowance.
//
// Economics (single $9.99 Pro plan): $9.99 − ~$3 Apple ≈ $7. AI budget $2.50/mo,
// leaving ~$4.50 gross margin per paying user. $2.50 ÷ ~30 days ≈ $0.083/day.

@Observable
final class DailyAIBudget: @unchecked Sendable {
    static let shared = DailyAIBudget()

    private let defaults = UserDefaults.standard
    private let lock = NSLock()

    private init() {}

    // MARK: - Day key (yyyy-MM-dd, POSIX + gregorian for stability)

    private var dayKey: String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }

    private var spendKeyToday: String { "ai_daily_spend_usd_\(dayKey)" }

    private func daysInCurrentMonth() -> Int {
        let cal = Calendar(identifier: .gregorian)
        return cal.range(of: .day, in: .month, for: Date())?.count ?? 30
    }

    // MARK: - Allowance / spend

    /// Today's USD allowance = this tier's monthly budget ÷ days in the month.
    /// Free tier (budget 0) gets 0 — AI is gated off entirely for free users.
    var dailyAllowanceUSD: Double {
        let monthly = SubscriptionManager.shared.currentTier.monthlyAIBudgetUSD
        guard monthly > 0 else { return 0 }
        return monthly / Double(daysInCurrentMonth())
    }

    var spentTodayUSD: Double { defaults.double(forKey: spendKeyToday) }

    var remainingTodayUSD: Double { max(0, dailyAllowanceUSD - spentTodayUSD) }

    /// 0–100% of today's allowance consumed.
    var percentUsedToday: Int {
        let a = dailyAllowanceUSD
        guard a > 0 else { return 100 }
        return min(100, Int((spentTodayUSD / a) * 100))
    }

    // MARK: - Gates

    /// True once today's allowance is fully spent (or the tier has no budget).
    func hasExceededToday() -> Bool {
        let a = dailyAllowanceUSD
        guard a > 0 else { return true }
        return spentTodayUSD >= a
    }

    /// True when ≥ `threshold` of today's allowance is spent. AIRouter uses this
    /// to downshift DeepSeek Pro → Flash so the user can keep working cheaply
    /// through the rest of the day instead of hitting a hard wall.
    func nearlyExhausted(threshold: Double = 0.85) -> Bool {
        let a = dailyAllowanceUSD
        guard a > 0 else { return true }
        return spentTodayUSD >= a * threshold
    }

    // MARK: - Recording

    /// Debit a completed call's real USD cost from today's allowance.
    func record(costUSD: Double) {
        guard costUSD > 0 else { return }
        lock.lock(); defer { lock.unlock() }
        let k = spendKeyToday
        defaults.set(defaults.double(forKey: k) + costUSD, forKey: k)
    }

    /// Convenience: debit a DeepSeek call directly from its usage + model.
    func record(usage: DeepSeekUsage, model: DeepSeekModel) {
        record(costUSD: usage.costUSD(for: model))
    }

    // MARK: - Reset / maintenance

    func resetToday() {
        defaults.removeObject(forKey: spendKeyToday)
    }

    /// Sweep stale day-keys so UserDefaults doesn't accumulate one entry per day
    /// forever. Keeps only today's key. Cheap; safe to call on launch.
    func pruneOldKeys() {
        let prefix = "ai_daily_spend_usd_"
        let keep = spendKeyToday
        for key in defaults.dictionaryRepresentation().keys
        where key.hasPrefix(prefix) && key != keep {
            defaults.removeObject(forKey: key)
        }
    }
}
