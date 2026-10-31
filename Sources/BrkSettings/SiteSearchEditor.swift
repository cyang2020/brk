import BrkBase
import BrkDomain
import BrkUIKit
import SwiftUI

struct SiteSearchEditor: View {
    let profile: ProfileID
    let engines: [SearchEngine]
    let dispatch: Dispatch
    @State private var name = ""
    @State private var keyword = ""
    @State private var template = ""

    private var draft: SearchEngine {
        SearchEngine(id: SearchEngineID("site-draft"), name: name, keyword: keyword.lowercased(), template: template, suggestTemplate: nil)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Site Search").font(.headline)
            ForEach(engines, id: \.id) { engine in
                HStack {
                    Text("\(engine.name) (\(engine.keyword))").help(engine.template)
                    Spacer()
                    Button("Remove") { dispatch(.settings(.profile(profile, .removeSiteSearch(engine.id)))) }
                }
            }
            TextField("Site name", text: $name)
            TextField("Keyword", text: $keyword)
            TextField("Search URL, with {q} for the query", text: $template)
            Button("Add Site Search") {
                dispatch(.settings(.profile(profile, .addSiteSearch(name: name, keyword: keyword, template: template))))
                name = ""; keyword = ""; template = ""
            }.disabled(!draft.isValidSiteSearch || (SearchEngine.builtIn + engines).contains { $0.keyword == draft.keyword })
            Text("Type the keyword in the command bar, press Tab, then enter a query.").font(.caption).foregroundStyle(.secondary)
        }
    }
}
