import Foundation

/// Default values shared across CLI and MCP surfaces. Prefer adding new
/// defaults here over duplicating literals across entry points.
public enum Defaults {
    /// Bundle identifier of the `BH Demo` app — the default target for
    /// `start_heist` and benchmark runs when no explicit `--app` is supplied.
    public static let demoAppBundleID = "com.buttonheist.testapp"
}
