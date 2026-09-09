import UpstreamLib
import UpstreamLibNoEvolution

public func downstreamMixed(name: String) -> Int {
    let greeting = UpstreamGreeting(name: name)
    _ = greeting.message()
    var counter = UpstreamCounter()
    counter.advance()
    return counter.count
}
