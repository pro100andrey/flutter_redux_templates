

export 'codec.dart';
export 'sembast_stub.dart'
    if (dart.library.js_interop) 'sembast_web.dart'
    if (dart.library.io) 'sembast_io.dart';

