## Summary

- What changed:
- Why:
- How validated:

## Cross-Platform Safety Checklist

- [ ] I confirmed shared/core code paths did not introduce `dart:io` or `dart:ffi` imports.
- [ ] Any platform-specific behavior is isolated behind backend interfaces and conditional imports.
- [ ] Unsupported platform behavior is explicit (e.g. `LlamaUnsupportedException`) rather than silent fallback/drift.

## Testing Checklist

- [ ] `dart format --output=none --set-exit-if-changed .`
- [ ] `dart analyze`
- [ ] `dart test -p vm -j 1 --exclude-tags local-only`
- [ ] `dart test -p chrome --exclude-tags local-only`

## Public API / Behavior Checklist

- [ ] If public API behavior changed, I added/updated tests for that behavior.
- [ ] If shared behavior changed, I validated both VM and browser-compatible paths.
- [ ] If this affects native/runtime logging or backend loading, I verified behavior during model load (not only after load).

## Release / Compatibility Notes

- Native bundle tag impact:
- Web bridge asset impact:
- Breaking change risk:

