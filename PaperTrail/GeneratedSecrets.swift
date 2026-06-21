import Foundation

enum BuildSecrets {
    static let sentryDSN = ""
    // Community-learning backend (Supabase). Empty in source control — CI
    // injects real values from repo secrets; the pipeline stays dormant
    // without them.
    static let supabaseURL = ""
    static let supabaseAnonKey = ""
}
