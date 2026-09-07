import Foundation

@main
struct FootballResponseGuardTests {
    static func main() {
        var passed = 0
        func check(_ condition: Bool, _ name: String) {
            precondition(condition, "FAIL: \(name)")
            passed += 1
            print("PASS: \(name)")
        }
        func accepts(_ json: String) -> Bool {
            do { try FootballResponseGuard.validate(Data(json.utf8)); return true }
            catch { return false }
        }
        check(accepts(#"{"errors":[],"response":[]}"#), "Empty provider response without errors is valid")
        check(accepts(#"{"errors":{},"response":[1]}"#), "Empty error dictionary is valid")
        check(accepts(#"{"errors":null,"response":[]}"#), "Null errors are accepted")
        check(accepts(#"{"response":[]}"#), "Optional errors field may be absent")
        check(!accepts(#"{"errors":{"requests":"Limit reached"},"response":[]}"#), "Provider error with HTTP 200 is not an empty success")
        check(!accepts(#"{"error":"Service unavailable","response":[]}"#), "Backend error envelope is rejected")
        check(!accepts(#"{"errors":["denied"],"response":[]}"#), "Error arrays are rejected")
        check(!accepts(#"{"response":[],"errors":7}"#), "Unexpected error shape fails closed")
        check(!accepts(#"{"ok":true}"#) && !accepts("<html>bad gateway</html>"), "Malformed football responses are rejected")
        print("\(passed) FootballResponseGuard checks passed")
    }
}
