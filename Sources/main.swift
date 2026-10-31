import AppKit

// Entry point. Screenshots runs either as a menu-bar (accessory) app, or — when invoked with
// CLI flags — performs a one-shot scripted action and exits. The CLI path exists mainly
// so the app can be driven deterministically for automated verification.

let rawArgs = Array(CommandLine.arguments.dropFirst())

// Headless one-shot commands exit inside CommandLineRunner. Everything else (including --edit)
// launches the normal GUI app.
let headlessCommands: Set<String> = ["--version", "--help", "--capture", "--capture-rect", "--list-windows", "--selftest"]
if let first = rawArgs.first, headlessCommands.contains(first) {
    CommandLineRunner.run(rawArgs)
}

// Top-level code runs on the main thread; make that isolation explicit for the compiler.
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory) // menu-bar app, no Dock icon
    app.run()
}
