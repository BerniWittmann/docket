import Foundation

public enum PromptTemplate {
    /// Fills {url}, {ticket}, {number} and {repo} from the item.
    public static func fill(_ template: String, item: WorkItem) -> String {
        let pr = item.primaryPR
        let values = [
            "{url}": pr?.url ?? item.ticket?.url ?? item.url ?? "",
            "{ticket}": item.linkedTicket?.identifier ?? "",
            "{number}": pr.map { String($0.number) } ?? "",
            "{repo}": pr?.repo ?? item.workspace?.repo ?? "",
        ]
        return values.reduce(template) { $0.replacingOccurrences(of: $1.key, with: $1.value) }
    }
}
