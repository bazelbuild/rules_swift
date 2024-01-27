public extension String {
    /// Specifies the type of random string that should be generated.
    enum RandomStringMode {
        case upperAlpha
        case lowerAlpha
        case upperAlphaNumeric
        case lowerAlphaNumeric
        case alpha
        case alphaNumeric

        /// Returns the characters that should be used for the mode.
        public var letters: String {
            switch self {
            case .upperAlpha:
                return "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
            case .lowerAlpha:
                return "abcdefghijklmnopqrstuvwxyz"
            case .upperAlphaNumeric:
                return "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
            case .lowerAlphaNumeric:
                return "abcdefghijklmnopqrstuvwxyz0123456789"
            case .alpha:
                return "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
            case .alphaNumeric:
                return "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
            }
        }
    }

    /// Generates a random string with the specified length and the specified contents.
    static func random(length: Int, mode: RandomStringMode) -> String {
        return String((0 ..< length).map { _ in mode.letters.randomElement()! })
    }
}
