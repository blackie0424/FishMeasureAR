import Foundation

/// 漁獲紀錄 → CSV(RFC 4180 跳脫),供離線調查資料匯出。
public enum CSVExporter {

    static let header = "species,length_cm,method,captured_at,latitude,longitude,place,synced"

    public static func export(_ entries: [CatchEntry],
                              timeZone: TimeZone = .current) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.timeZone = timeZone
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"

        var lines = [header]
        for e in entries {
            let length: String = e.lengthCM.map { String(format: "%.1f", $0) } ?? ""
            let latitude: String = e.latitude.map { "\($0)" } ?? ""
            let longitude: String = e.longitude.map { "\($0)" } ?? ""
            let fields: [String] = [
                e.species,
                length,
                e.method ?? "",
                dateFormatter.string(from: e.capturedAt),
                latitude,
                longitude,
                e.placeName ?? "",
                e.isSynced ? "1" : "0",
            ]
            lines.append(fields.map(escape).joined(separator: ","))
        }
        return lines.joined(separator: "\n")
    }

    public static func filename(for date: Date,
                                timeZone: TimeZone = .current) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = timeZone
        f.dateFormat = "yyyyMMdd"
        return "catch_\(f.string(from: date)).csv"
    }

    private static func escape(_ field: String) -> String {
        guard field.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" }) else {
            return field
        }
        return "\"\(field.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
}
