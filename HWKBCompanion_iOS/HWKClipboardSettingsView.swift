import SwiftUI

struct HWKClipboardSettingsView: View {
    let snippetCount: Int
    let isSuggestionsEnabled: Bool
    let addSnippetAction: () -> Void
    let clearAllSnippetsAction: () -> Void

    var body: some View {
        List {
            Section(header: Text("Clipboard")) {
                HStack {
                    Text("Snippets")
                    Spacer()
                    Text("\(snippetCount)")
                        .foregroundColor(.secondary)
                }
                HStack {
                    Text("Status")
                    Spacer()
                    Text(isSuggestionsEnabled ? "Enabled" : "Locked")
                        .foregroundColor(.secondary)
                }
                if snippetCount == 0 {
                    Text("No clipboard snippets are saved yet.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                } else {
                    Text("Snippets are kept encrypted in local-only storage.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            }

            Section {
                Button("Add from Clipboard") {
                    addSnippetAction()
                }
                .disabled(!isSuggestionsEnabled)
                Button("Delete All Saved Snippets") {
                    clearAllSnippetsAction()
                }
                .disabled(snippetCount == 0)
                .foregroundColor(snippetCount == 0 ? .secondary : .red)
            }
        }
        .navigationTitle("Clipboard")
    }
}
