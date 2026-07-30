import SQLite3

/// Returns the SQLite library version.
public func sqliteVersion() -> String {
  String(cString: sqlite3_libversion())
}
