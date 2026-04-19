## Code comments

When adding or reviewing TypeScript/JavaScript comments, use the `high-quality-code-comments` skill.

Comments should explain contracts, invariants, edge cases, tradeoffs, failure modes, and external coupling. Do not add comments that restate obvious code. Prefer better names, types, or structure over comments when possible.

Prioritize contract-first comments near public APIs, hardware/control boundaries, retries/timeouts, auth/privacy boundaries, state machines, concurrency, schema transformations, vendor/API assumptions, and code that looks weird but is intentional.
