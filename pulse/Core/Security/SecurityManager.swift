// SecurityManager removed.
//
// This previously housed a jailbreak/debugger/tamper-detection helper
// (`SecurityManager.shared.performStartupChecks()`) that was never wired into
// the app — it had zero callers. Its jailbreak heuristic also false-positived
// on stock devices (e.g. probing for `fork`), so it was dead, risky code.
//
// Intentionally left empty to keep the file in the project while removing all
// behavior. Delete the file entirely if the build no longer references it.
