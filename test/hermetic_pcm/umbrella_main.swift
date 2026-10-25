import HermeticUmbrella

@main
struct Main {
    static func main() {
        let answer = hermetic_value()
        precondition(answer.value == 42)
        print(answer.value)
    }
}
