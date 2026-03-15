import SwiftUI

extension CodeScreen {

    // MARK: - Symbol Navigation

    func handleDefinitionRequest(_ query: EditorSymbolQuery) {
        Task {
            let definitions = await model.findEditorDefinitions(for: query)
            await MainActor.run {
                guard !definitions.isEmpty else {
                    model.statusMessage = L10n("editor.navigation.definition.notFound", query.symbol)
                    return
                }

                if definitions.count == 1, let target = definitions.first {
                    model.openEditorLocation(target)
                    model.statusMessage = L10n("editor.navigation.definition.opened", query.symbol)
                    return
                }

                symbolResultsMode = .definitions
                symbolResultsQuery = query.symbol
                symbolResults = definitions
                isSymbolResultsVisible = true
            }
        }
    }

    func handleReferencesRequest(_ query: EditorSymbolQuery) {
        Task {
            let references = await model.findEditorReferences(for: query)
            await MainActor.run {
                guard !references.isEmpty else {
                    model.statusMessage = L10n("editor.navigation.references.notFound", query.symbol)
                    return
                }

                symbolResultsMode = .references
                symbolResultsQuery = query.symbol
                symbolResults = references
                isSymbolResultsVisible = true
                model.statusMessage = L10n("editor.navigation.references.found", "\(references.count)", query.symbol)
            }
        }
    }
}
