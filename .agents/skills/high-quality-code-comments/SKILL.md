---
name: high-quality-code-comments
description: Use when adding, reviewing, or improving TypeScript/JavaScript comments, TSDoc, JSDoc, exported API docs, public interfaces, complex functions, invariants, edge cases, or non-obvious implementation choices.
---

# High-Quality Code Comments Skill

You improve comments so they preserve engineering intent, not line-by-line narration.

## Root cause

Bad comments usually come from weak incentives: authors and agents optimize for “explain what I just wrote” instead of “reduce future reader uncertainty.” This skill forces comments to justify why, document contracts, encode invariants, and avoid restating obvious code.

## Core rule

A good comment explains one or more of:

1. **Contract** — what callers may rely on.
2. **Intent** — why this exists.
3. **Invariant** — what must remain true.
4. **Edge case** — what surprising case is handled.
5. **Tradeoff** — why this design was chosen over alternatives.
6. **Failure mode** — what can go wrong and how it is surfaced.
7. **External coupling** — protocol, API, schema, browser/runtime behavior, performance constraint, or compatibility reason.

Do not add comments that merely restate the code.

Bad:

```ts
// Increment i by 1.
i += 1;
```

Good:

```ts
// Retry once before surfacing the error because transient 409s are common
// immediately after the provider creates a remote session.
```

## Opinionated rule: contract-first comments

Prioritize comments where future breakage compounds:

- Public APIs.
- Hardware/control boundaries.
- Retries, timeouts, cancellation, and backoff.
- Auth, privacy, permissions, and tenant boundaries.
- State machines and lifecycle transitions.
- Concurrency, ordering, locking, and race prevention.
- Schema transformations and migration compatibility.
- Vendor/API assumptions.
- Code that looks weird but is intentional.

These comments should primarily document the contract and the reason the contract exists.

## When to add TSDoc/JSDoc

Add TSDoc/JSDoc for:

- Exported functions, classes, interfaces, types, constants, hooks, components, and public methods.
- Functions whose behavior is non-obvious from the name and signature.
- Code with important side effects.
- Code with error, retry, timeout, cache, auth, permissions, concurrency, lifecycle, or resource-management behavior.
- Types that encode business meaning, not just structural shape.

Do not add TSDoc/JSDoc for private helpers unless the helper has meaningful hidden intent or tricky constraints.

## TSDoc/JSDoc format

Prefer concise TSDoc:

```ts
/**
 * Builds a stable cache key for a meal-plan request.
 *
 * The key intentionally excludes transient UI state so equivalent requests
 * reuse the same generated plan.
 *
 * @throws {InvalidMealPlanRequestError} When required household constraints are missing.
 */
export function buildMealPlanCacheKey(request: MealPlanRequest): string {
  // ...
}
```

Use this structure:

1. First sentence: what the symbol does, in business/domain terms.
2. Optional second paragraph: why the behavior exists.
3. Optional tags:
   - `@param` only when the parameter meaning is not obvious from the name/type.
   - `@returns` only when the return value has non-obvious semantics.
   - `@throws` for expected thrown errors.
   - `@remarks` for deeper context, tradeoffs, or external coupling.
   - `@internal` for non-public exports.

Avoid filler tags.

Bad:

```ts
/**
 * Gets user.
 * @param id The id.
 * @returns The user.
 */
```

Good:

```ts
/**
 * Loads the user record visible to the current tenant.
 *
 * This deliberately returns `null` instead of throwing when the user exists
 * outside the tenant boundary, so callers cannot distinguish missing users
 * from unauthorized users.
 */
```

## Inline comments

Use inline comments sparingly. Put them immediately above the surprising code.

Good inline comment targets:

- Workarounds.
- Race conditions.
- Ordering dependencies.
- Browser/runtime quirks.
- Performance shortcuts.
- Security decisions.
- Data migrations.
- Non-obvious math.
- Intentional duplication.
- Intentionally ignored errors.

Bad inline comments:

- Repeat syntax.
- Describe obvious control flow.
- Explain names that should be renamed instead.
- Apologize for messy code without explaining the constraint.

## Comment review checklist

Before finalizing, review every added or edited comment:

- Is it still true if the implementation changes slightly?
- Does it explain why, not merely what?
- Could a better name remove the need for this comment?
- Does it document a contract future callers need?
- Does it mention failure behavior where relevant?
- Does it avoid implementation trivia?
- Is it short enough to be maintained?
- Does it avoid promising behavior that tests do not enforce?

## If comments expose weak code

If a comment is needed because the code is confusing, prefer one of:

1. Rename the symbol.
2. Extract a helper.
3. Split the function.
4. Strengthen the type.
5. Add an assertion or explicit error.
6. Add a test for the documented contract.

Only keep the comment if the design remains non-obvious after the code is cleaned up.

## Output expectations

When asked to improve comments:

1. Inspect the surrounding code before editing comments.
2. Add comments only where they reduce future maintenance risk.
3. Preserve existing public API behavior.
4. Keep diffs minimal.
5. Do not generate large comment blocks for obvious code.
6. Prefer precise, durable comments over verbose explanations.
7. If documentation and implementation disagree, update the implementation only if requested; otherwise flag the mismatch.
