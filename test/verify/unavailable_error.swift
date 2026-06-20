@available(*, unavailable)
struct NeverAvailable {} // expected-note {{'NeverAvailable' has been explicitly marked unavailable here}}

let neverAvailable = NeverAvailable() // expected-error {{'NeverAvailable' is unavailable}}
