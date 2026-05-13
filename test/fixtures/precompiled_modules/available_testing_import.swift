import Testing

@main
struct AvailableTestingImport {
    static func main() {
        if #available(macOS 14.0, iOS 16.0, tvOS 16.0, *) {
            printTestingType()
        } else {
            print("Testing is unavailable")
        }
    }

    @available(macOS 14.0, iOS 16.0, tvOS 16.0, *)
    private static func printTestingType() {
        print("Testing is available: \(Testing.Test.self)")
    }
}
