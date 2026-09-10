import Foundation

enum FreeConnectionCheck {
    static func time(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Riyadh")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
    struct Result: Identifiable {
        let id: String
        let title: String
        let available: Bool
        let message: String
    }
    static func valid(_ data: Data, health: Bool) -> Bool {
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return false }
        if health { return object["ok"] as? Bool == true && object["service"] as? String == "90plus-free" }
        return object["events"] is [Any]
    }
    static func run(gateway raw: String) async -> [Result] {
        let source = URL(string: "https://site.web.api.espn.com/apis/site/v2/sports/soccer/ksa.1/scoreboard")!
        var probes: [(String, String, URL, Bool)] = []
        if let base = FreeSourceTransport.gateway(raw), let routed = FreeSourceTransport.proxied(source, base: base) {
            probes.append(("gateway", "خادم 90+", base.appending(path: "api/health"), true))
            probes.append(("gateway-data", "المباريات عبر الخادم", routed, false))
        }
        probes.append(("direct", "المباريات بالاتصال المباشر", source, false))
        return await withTaskGroup(of: Result.self) { group in
            for (id, title, url, health) in probes {
                group.addTask {
                    do {
                        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
                        request.timeoutInterval = 8
                        let (data, response) = try await URLSession.shared.data(for: request)
                        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode), valid(data, health: health) else {
                            return Result(id: id, title: title, available: false, message: "وصل رد غير صالح؛ جرّب الاتصال المباشر أو أعد الفحص لاحقًا.")
                        }
                        return Result(id: id, title: title, available: true, message: health ? "الخادم يستجيب." : "وصلت استجابة مباريات صالحة؛ قد لا توجد مباريات اليوم.")
                    } catch {
                        return Result(id: id, title: title, available: false, message: "تعذّر الوصول من شبكتك الحالية.")
                    }
                }
            }
            var results: [Result] = []
            for await value in group { results.append(value) }
            return probes.compactMap { probe in results.first { $0.id == probe.0 } }
        }
    }
}
