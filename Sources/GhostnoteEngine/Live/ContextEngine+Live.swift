// MARK: - The live engine

extension ContextEngine {
    /// Makes an engine that watches the real front app through NSWorkspace and the Accessibility API.
    public init() {
        self.init(source: LiveFrontAppSource())
    }
}
