import Foundation
import MinOSLib
import Greeter

@main
struct App {
    static func main() {
        print(minOSLibFunc())
        print(Greeter.greeting())
    }
}
