# Scoped diagnostics

Explicitly select categories for owned enabled targets, and use the independent approved evidence workspace. The module queries the actual category catalog rather than guessing resource-specific category names. Unsupported categories fail clearly.

Root diagnostics default to an empty map. Root Log Analytics has 30-day retention and a 1-GB/day cap; validate evidence completeness and investigate ingestion-cap drops before assigning a resilience verdict. Keep detailed telemetry/private identifiers out of public reports.

This does not implement application metrics, data ledgers, a fault-stop controller, alert routing or automatic recovery. Those require the real application's SLOs and independently reachable operator notification path. Existing diagnostic settings must be inventoried first to avoid duplicate names or unintended ownership.
