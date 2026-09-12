/// Process-wide native installation is separate from per-match runtime ownership.
/// The production C registry rejects replacement; a closed isolate does not reset it.
@MainActor
final class OnDeviceBackendRegistration {
    private var installed = false

    /// Synchronous on the main actor: no suspension can race another installer.
    /// A failed installation remains retryable; success is retained for this process.
    func ensureInstalled(_ install: () throws -> Void) rethrows {
        guard !installed else { return }
        try install()
        installed = true
    }
}
