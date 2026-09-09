import UpstreamLib

public func downstreamGreeting(name: String) -> String {
    let greeting = UpstreamGreeting(name: name)
    return greeting.message()
}
