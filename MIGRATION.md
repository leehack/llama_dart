# Migration Guide (`0.4.x` -> `0.5.0`)

This document covers the breaking changes introduced in `0.5.0`.

## 1) ChatSession API

- Old pattern (string-in, string-out helpers):
  - `session.chat(...)`
  - `session.chatText(...)`
- New pattern:
  - `session.create(List<LlamaContentPart> ...)`
  - stream `LlamaCompletionChunk`

Example migration:

```dart
// Before
await for (final token in session.chat('Hello')) {
  stdout.write(token);
}

// After
await for (final chunk in session.create([LlamaTextContent('Hello')])) {
  stdout.write(chunk.choices.first.delta.content ?? '');
}
```

## 2) LlamaChatMessage constructor names

- `LlamaChatMessage.text(...)` -> `LlamaChatMessage.fromText(...)`
- `LlamaChatMessage.multimodal(...)` -> `LlamaChatMessage.withContent(...)`

Example migration:

```dart
// Before
LlamaChatMessage.text(role: LlamaChatRole.user, content: 'Hi');

// After
LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'Hi');
```

## 3) Logging configuration moved off ModelParams

- Removed: `ModelParams(logLevel: ...)`
- Use engine-level controls instead:
  - `await engine.setDartLogLevel(...)`
  - `await engine.setNativeLogLevel(...)`
  - or `await engine.setLogLevel(...)` to set both

Example migration:

```dart
// Before
await engine.loadModel(path, modelParams: ModelParams(logLevel: LlamaLogLevel.info));

// After
await engine.setNativeLogLevel(LlamaLogLevel.info);
await engine.loadModel(path);
```

## 4) Model reload lifecycle

- `loadModel(...)` now throws if a model is already loaded.
- Call `await engine.unloadModel()` (or `dispose()`) before loading another model.

## 5) Public exports tightened

The package root (`package:llamadart/llamadart.dart`) no longer exports some
previous internals. In particular:

- `ToolRegistry`
- `LlamaTokenizer`
- `ChatTemplateProcessor`

Use `LlamaEngine`, `ChatSession`, `ToolDefinition`, and the template APIs as
the supported surface.

## 6) Custom backend implementers

If you maintain your own `LlamaBackend` implementation, update it to match the
current interface:

- Add `getVramInfo()`.
- Update `applyChatTemplate(...)` signature/return type (string-based prompt
  rendering input/output).

## 7) Template extensibility (new)

While migrating, you can adopt the new template routing hooks:

- `ChatTemplateEngine.registerHandler(...)`
- `ChatTemplateEngine.registerTemplateOverride(...)`
- per-call overrides via `customTemplate` / `customHandlerId`

## 8) Quick migration checklist

- Replace old `ChatSession` chat helpers with `create(...)` streaming.
- Rename `LlamaChatMessage` named constructors.
- Remove `ModelParams.logLevel` usage.
- Audit imports that depended on removed root exports.
- For custom backends, implement the latest `LlamaBackend` interface.
