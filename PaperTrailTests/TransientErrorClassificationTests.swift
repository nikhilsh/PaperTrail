import Testing
import Foundation
import CloudKit
@testable import PaperTrail

/// `Error.isTransientNetworkError` gates whether a CloudKit/network failure is
/// logged as a benign warning (queryable, no Sentry issue) or a real error.
/// Getting it wrong either buries a genuine fault or spams issues per user, so
/// the classification is pinned here.
struct TransientErrorClassificationTests {

    @Test func networkAndAvailabilityCKErrorsAreTransient() {
        for code: CKError.Code in [.networkUnavailable, .networkFailure,
                                   .serviceUnavailable, .requestRateLimited,
                                   .zoneBusy, .notAuthenticated] {
            #expect(CKError(code).isTransientNetworkError, "\(code) should be transient")
        }
    }

    @Test func urlErrorsAreTransient() {
        let offline = NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet)
        #expect(offline.isTransientNetworkError)
    }

    @Test func realCKFaultsAreNotTransient() {
        // The team-ID mismatch and genuine data faults must still raise errors.
        for code: CKError.Code in [.badContainer, .partialFailure,
                                   .permissionFailure, .serverRejectedRequest,
                                   .managedAccountRestricted] {
            #expect(!CKError(code).isTransientNetworkError, "\(code) should NOT be transient")
        }
    }

    @Test func genericErrorsAreNotTransient() {
        struct SomeError: Error {}
        #expect(!SomeError().isTransientNetworkError)
    }
}
