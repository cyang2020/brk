import Foundation

extension SearchEngine {
    public var isValidSiteSearch: Bool {
        guard !name.isEmpty, name.count <= 80, keyword.count >= 2, keyword.count <= 40,
              keyword.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || "-_.".contains($0)) }),
              template.count <= 4096, template.components(separatedBy: "{q}").count == 2,
              let url = searchURL("test"), ["http", "https"].contains(url.scheme), url.host?.isEmpty == false,
              url.user == nil, url.password == nil, SearchEngine.builtIn(id) == nil else { return false }
        return suggestTemplate == nil
    }
}
