import UIKit

/// Restores the left-edge swipe-back gesture everywhere.
///
/// The Archive design hides the system back button
/// (`.navigationBarBackButtonHidden()` with a custom toolbar Back button in
/// `RecordDetailView`, `SharedRecordDetailView`, …), and UIKit disables the
/// `interactivePopGestureRecognizer` whenever the system back button is
/// hidden. Re-attaching ourselves as the gesture's delegate re-enables it;
/// the `viewControllers.count > 1` guard keeps the gesture from firing on a
/// navigation stack's root (which can freeze the navigation controller).
extension UINavigationController: @retroactive UIGestureRecognizerDelegate {
    override open func viewDidLoad() {
        super.viewDidLoad()
        interactivePopGestureRecognizer?.delegate = self
    }

    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        viewControllers.count > 1
    }
}
