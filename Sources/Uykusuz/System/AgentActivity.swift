import AppKit
import IOKit.pwr_mgt

/// Whether an agent app is at work, read from the power assertions apps
/// hold (fork addition). Claude's desktop app holds a "prevent idle sleep"
/// assertion (Electron's `NoIdleSleepAssertion`) while it runs Claude Code
/// sessions; `pmset -g assertions` lists it under the app's pid.
///
/// Read-only and local: one IOKit call for the assertions and one
/// `NSRunningApplication` lookup per holding pid. No permission is needed.
enum AgentActivity {
    /// Assertion types that keep the system awake. Display-only ones (a
    /// video playing) do not count.
    static let systemSleepTypes: Set<String> = [
        "NoIdleSleepAssertion",
        "PreventUserIdleSystemSleep",
        "PreventSystemSleep",
    ]

    /// Pids holding at least one assertion of `systemSleepTypes`, from a
    /// dictionary shaped like `IOPMCopyAssertionsByProcess`'s: pid to a list
    /// of assertion dictionaries with an `AssertType` entry.
    static func pidsHoldingSleepAssertions(_ byProcess: [NSNumber: [[String: Any]]]) -> Set<pid_t> {
        var pids = Set<pid_t>()
        for (pid, assertions) in byProcess where assertions.contains(where: { a in
            (a[kIOPMAssertionTypeKey] as? String).map(systemSleepTypes.contains) ?? false
        }) {
            pids.insert(pid.int32Value)
        }
        return pids
    }

    /// True when one of `pids` belongs to an app in `bundleIDs`.
    static func isActive(pids: Set<pid_t>, bundleIDs: [String], bundleOf: (pid_t) -> String?) -> Bool {
        guard !bundleIDs.isEmpty else { return false }
        let wanted = Set(bundleIDs)
        return pids.contains { bundleOf($0).map(wanted.contains) ?? false }
    }

    /// The live reading: the system's assertions now, against `bundleIDs`.
    static func isActive(bundleIDs: [String]) -> Bool {
        isActive(pids: livePids(), bundleIDs: bundleIDs) { pid in
            NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
        }
    }

    private static func livePids() -> Set<pid_t> {
        var unmanaged: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsByProcess(&unmanaged) == kIOReturnSuccess,
              let dict = unmanaged?.takeRetainedValue() as? [NSNumber: [[String: Any]]] else {
            return []
        }
        return pidsHoldingSleepAssertions(dict)
    }
}
