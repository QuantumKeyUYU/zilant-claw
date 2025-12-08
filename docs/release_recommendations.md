# Release readiness recommendations

This document summarizes technical improvements that can raise the Android VPN MVP to a reliable release candidate. It focuses on architecture, Android VPN internals, Flutter state management/UI, and areas to simplify or rewrite quickly.

## Architecture-level gaps
- **Lifecycle and health monitoring**: Introduce a single source of truth for protection state (e.g., background service heartbeat + foreground notifier) and emit structured events that Flutter listens to instead of inferring state from stats polling. This prevents the UI from drifting when the tunnel dies unexpectedly.
- **Resilient command channel**: Wrap MethodChannel calls with an idempotent command layer (start/stop/setMode requests that can be replayed, deduplicated, and time out). Emit explicit error codes for permission denial, binder death, and VpnService preparation so Flutter can show actionable UI.
- **Blocklist ingestion pipeline**: Normalize a pipeline that supports built-in lists plus user-provided URLs/files with signature/hash validation, incremental updates, and cache versioning. Store metadata (ETag/Last-Modified) to minimize downloads and to roll back on corrupt lists.
- **Logging and diagnostics**: Add structured logging (JSON lines) from both Kotlin and Dart, persisted to disk with rotation. Provide a minimal “export logs” action from Flutter. Include health metrics (tunnel uptime, reconnection attempts, DNS latency) to make field debugging viable.

## Android (VpnService, DNS interception, stability)
- **Foreground, sticky, and restartable service**: Run the VpnService in the foreground with a persistent notification, mark it STICKY, and implement a watchdog (e.g., a periodic WorkManager task) to detect binder death or lost tun interface and restart automatically.
- **DNS resolver hardening**: Move DNS interception off the main thread; keep a dedicated I/O dispatcher with bounded queues, timeouts, and cancellation. Enforce sane defaults (EDNS disabled, min/max UDP size) and detect recursion loops. Consider a pure-Dart fallback for low-end devices only for metadata display, not for interception.
- **Network and transport edge cases**: Handle captive portals, private DNS (DoT/DoH) detection, and IPv6-only or dual-stack networks explicitly. Expose a fail-open/fail-closed toggle and surface it in stats. Ensure that the VpnService builder advertises the correct DNS servers and routes only DNS traffic when in “filter-only” mode.
- **Permission and recovery flows**: Preflight VPN preparation with `prepare` and cache the intent result. On denial, present a clear rationale and shortcut to system VPN settings. After crashes or device reboots, auto-restore the last state (if user opted in) and reschedule the watchdog.

## Flutter (state management, UI, error handling)
- **State source of truth**: Replace ad-hoc `ChangeNotifier` usage with a predictable state container (e.g., Riverpod/BLoC) that consumes a stream of protection events from the native side. Decouple stats fetching from command execution so UI cannot get stuck in `turningOn/turningOff` if the service crashed.
- **Mode selection and validation**: Keep mode definitions in one model shared with native (enum + schema) and validate responses from MethodChannel before updating UI. Show mode descriptions and risk levels in the dropdown to reduce misconfiguration.
- **User-visible resilience**: Centralize error surfaces (SnackBar/dialog for transient errors, full-screen for fatal). Add inline spinners for start/stop, and display reconnection attempts with backoff. Provide a “report a problem” action that bundles logs/diagnostics for support.
- **Blocklist UX**: Provide a form to add a blocklist URL or file, validate checksum before enabling, and display the active list’s timestamp/size. Allow quick allow/deny overrides with a last-10 actions history for undo.

## Simplifications or rewrites worth considering
- **Service command layer**: Introduce a thin Kotlin command handler (start/stop/setMode) with debouncing and state replay to reduce Flutter-side branching. Flutter should only render the current state + last error.
- **Stats transport**: Swap JSON-over-MethodChannel for a typed codec or a small FFI/PlatformChannel data class to reduce parsing errors and to include timestamps and health flags atomically.
- **Testing hooks**: Add headless integration tests: a JVM test for the DNS engine (block/allow paths, IPv6, EDNS), and an Android instrumentation test that starts the VpnService, injects synthetic DNS queries, and asserts blocklist hits. Provide a fake resolver for Flutter widget tests to simulate mode changes and error codes.
- **Release guardrails**: Build a preflight checklist (permissions granted, foreground notification shown, blocklist loaded, watchdog scheduled) and block the “On” toggle until it passes. Surface a compact health badge on the home screen (OK / degraded / restarting) to reduce support load.
