import Foundation

struct HWKComplexScriptSuggestionPolicy {
    private let scriptEngine = HWKScriptEngine()
    private let navigator = HWKGraphemeNavigator()

    func shouldOfferSuggestions(for context: String, complexScriptsEnabled: Bool) -> Bool {
        guard !context.isEmpty, !complexScriptsEnabled else { return true }
        return !containsComplexScriptText(in: context)
    }

    func containsComplexScriptText(in context: String) -> Bool {
        navigator.clusters(in: context).contains { token in
            switch scriptEngine.script(for: token) {
            case .arabic, .hebrew, .thai, .devanagari:
                return true
            case .latin, .unknown:
                return false
            }
        }
    }
}

