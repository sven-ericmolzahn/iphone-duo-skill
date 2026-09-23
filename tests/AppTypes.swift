//  AppTypes.swift — names real apps define that the probe must not trip over.
//
//  Not an app. `tests/typecheck.sh` compiles the probe together with this
//  file: an app with its own `Logger` type broke the probe's `Logger(…)` with
//  "'Logger' cannot be constructed because it has no accessible initializers".

enum Logger {
    static func info(_ message: String) {}
}
