import UIKit

/// Parameters of the quick-attach fan animation.
/// The two-axis trick: X and Y run on SEPARATE springs — a fast Y with
/// overshoot plus a slower smooth X bends the straight line into a natural
/// arc while keeping true spring physics on both axes.
final class FanTuning {
    static let shared = FanTuning()

    // Measured off the reference capture; cards are born at the icon center.
    var xStiffness: CGFloat = 320   // horizontal spring stiffness
    var xDamping: CGFloat = 0.88    // horizontal damping ratio (1 = no overshoot)
    var yStiffness: CGFloat = 500   // vertical spring stiffness
    var yDamping: CGFloat = 0.60    // vertical damping ratio (< 1 = overshoot up)
    var birthScale: CGFloat = 0.42  // scale at the icon center
    var staggerMs: CGFloat = 28     // per-card launch delay
    var birthYOffset: CGFloat = 0   // vertical shift of the birth point (- up, + down)
    var yOvershootStep: CGFloat = 0.06 // per-card Y damping reduction: righter = bouncier
}
