import Foundation

enum OwnedWidgetProcess {
    /// Match the complete executable path, including spaces. Never match by name.
    static func identifiers(in rows: String, executablePath: String) -> [Int32] {
        rows.split(separator: "\n").compactMap { row in
            let parts = row.trimmingCharacters(in: .whitespaces).split(maxSplits: 1, whereSeparator: { $0 == " " || $0 == "\t" })
            guard parts.count == 2, parts[1] == executablePath else { return nil }
            return Int32(parts[0])
        }
    }
}
