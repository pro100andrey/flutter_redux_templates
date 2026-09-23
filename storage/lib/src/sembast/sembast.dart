/// Where a sembast database lives, and which factory opens it — chosen once,
/// at compile time, by the library the platform actually has.
///
/// `js_interop` first: it is what both web compilers provide, dart2js and
/// dart2wasm alike. The web test this replaced, `bool.fromEnvironment(
/// 'dart.library.js_util')`, is false under `--wasm`, so a wasm build took the
/// native branch, asked path_provider for a directory, and never started. With
/// the choice made here and nowhere else, the factory and the path cannot
/// disagree about which platform they are on.
library;

export 'codec.dart';
export 'sembast_stub.dart'
    if (dart.library.js_interop) 'sembast_web.dart'
    if (dart.library.io) 'sembast_io.dart';
