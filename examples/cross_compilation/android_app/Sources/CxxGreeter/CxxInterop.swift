import CxxGreeting

@_cdecl("cxx_greeting_length")
public func cxxGreetingLength() -> Int {
  return cxxGreeting(subject: "Android").utf8.count
}
