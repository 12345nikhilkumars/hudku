import Foundation

/// What the Mac will let Hudku see through the camera.
enum CameraAccess: Sendable {
    case notDetermined
    case granted
    /// Denied or restricted: only System Settings can undo it, so both read the same to us.
    case denied
}
