import Foundation

// MARK: - Member number (docs/design-v2/V2_BRIEF.md §1 "Post-purchase state")
//
// Derives a "sequential-looking" 6-digit member number from an opaque
// purchase identifier (StoreKit's `originalTransactionID`, etc). This is
// purely cosmetic — not a real sequence, not an actual count of members —
// just a stable, deterministic badge number so "Member № 000482" reads the
// same every time the same person opens Settings.
//
// Deterministic: the same id always maps to the same number. Distinct ids
// are very likely (not guaranteed — it's a hash into a 6-digit space, ~1M
// buckets) to map to distinct numbers.

/// Free function, not a method: no `self`, no app state — safe to call from
/// any isolation context. Marked `nonisolated` because the project defaults
/// declarations to `@MainActor` (`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`)
/// and this has no business being actor-isolated.
nonisolated func memberNumber(fromTransactionID id: String) -> String {
    // FNV-1a 64-bit: fast, dependency-free, good avalanche for short strings.
    var hash: UInt64 = 0xcbf2_9ce4_8422_2325
    for byte in id.utf8 {
        hash ^= UInt64(byte)
        hash = hash &* 0x0000_0100_0000_01b3
    }
    let bucket = hash % 1_000_000
    return String(format: "%06d", bucket)
}
