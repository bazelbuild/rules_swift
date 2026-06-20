import Compression
import SQLite3
import zlib

@main
struct CModuleImports {
    static func main() {
        _ = compression_encode_buffer
        _ = sqlite3_libversion()
        _ = zlibVersion()
    }
}
