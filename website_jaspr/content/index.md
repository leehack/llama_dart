---
title: llamadart documentation
description: Run llama.cpp from Dart and Flutter across native and web.
image: /images/logo.svg
---

<div class="landingRoot">
<section class="heroShell">
<div class="heroLeft">
<p class="heroKicker">Dart + Flutter local inference runtime</p>
<h1>Build offline-ready AI features with llamadart</h1>
<p class="heroLead">Documentation for product engineers and maintainers shipping local LLM features across Android, iOS, macOS, Linux, Windows, and web.</p>
<div class="heroActions">
<a class="button button--primary button--lg" href="/docs/intro">Read documentation</a>
<a class="button button--secondary button--lg" href="https://pub.dev/packages/llamadart">API on pub.dev</a>
</div>
<ul class="heroChecklist">
<li>Single Dart API across native and browser targets</li>
<li>GGUF model lifecycle and streaming-first generation</li>
<li>OpenAI-compatible local server example included</li>
</ul>
<div class="platformChips" aria-label="Supported platforms">
<span>Android</span><span>iOS</span><span>macOS</span><span>Linux</span><span>Windows</span><span>Web</span>
</div>
</div>
<div class="heroRight" aria-label="Quick start examples">
<h2>Quick start examples</h2>
<p class="heroAsideText"><code>dart pub add llamadart</code></p>
<p class="heroAsideText">Load a GGUF model and stream output from a single Dart API.</p>
<p class="heroAsideText">For OpenAI-compatible HTTP flows, start from <a href="/docs/examples/llamadart-server"><code>llamadart_server</code></a>.</p>
</div>
</section>

<section class="sectionShell" aria-label="Documentation paths">
<header class="sectionHeader">
<p class="sectionKicker">Start here</p>
<h2>Choose a path based on what you are shipping</h2>
</header>
<div class="pathGrid">
<article class="pathCard"><h3>Start in 10 minutes</h3><p>Install, load a GGUF model, and stream your first response.</p><a href="/docs/getting-started/quickstart">Open quickstart</a></article>
<article class="pathCard"><h3>Ship chat and tools</h3><p>Build tool calling, structured chat prompts, and streaming UX.</p><a href="/docs/guides/tool-calling">Read guides</a></article>
<article class="pathCard"><h3>Tune for production</h3><p>Choose backends and tune context/runtime parameters.</p><a href="/docs/configuration/runtime-parameters">Tune runtime</a></article>
<article class="pathCard"><h3>Run OpenAI-style server</h3><p>Expose local models over HTTP for existing OpenAI clients.</p><a href="/docs/examples/llamadart-server">See server example</a></article>
</div>
</section>

<section class="sectionShell" aria-label="Feature guides">
<header class="sectionHeader">
<p class="sectionKicker">Core guides</p>
<h2>Reference docs for real production workflows</h2>
</header>
<div class="featureGrid">
<article class="featureCard"><h3>Model lifecycle</h3><p>Predictable loading/unloading flow and resource cleanup patterns.</p><a href="/docs/guides/model-lifecycle">Lifecycle guide</a></article>
<article class="featureCard"><h3>Generation and streaming</h3><p>Token streaming patterns for CLI apps, servers, and Flutter UIs.</p><a href="/docs/guides/generation-and-streaming">Streaming guide</a></article>
<article class="featureCard"><h3>Multimodal</h3><p>Image + text prompting with platform-specific constraints.</p><a href="/docs/guides/multimodal">Multimodal guide</a></article>
<article class="featureCard"><h3>Platform matrix</h3><p>Understand native/web support boundaries before shipping.</p><a href="/docs/platforms/support-matrix">Support matrix</a></article>
<article class="featureCard"><h3>Performance tuning</h3><p>Tune context length, threads, and generation settings safely.</p><a href="/docs/guides/performance-tuning">Tuning guide</a></article>
<article class="featureCard"><h3>Troubleshooting</h3><p>Fast fixes for model loading, runtime, and platform issues.</p><a href="/docs/troubleshooting/common-issues">Debug issues</a></article>
</div>
</section>

<section class="sectionShell maintainerShell" aria-label="Maintainer docs">
<header class="sectionHeader">
<p class="sectionKicker">Maintainers</p>
<h2>llamadart-specific maintenance and release operations</h2>
</header>
<div class="maintainerGrid">
<article class="maintainerCard"><h3>Maintainer overview</h3><p>Repository ownership map and routine responsibilities.</p><a href="/docs/maintainers/docs-site">Maintainer docs</a></article>
<article class="maintainerCard"><h3>Runtime ownership</h3><p>Where to change native runtime, web bridge, and assets.</p><a href="/docs/maintainers/runtime-ownership">Ownership boundaries</a></article>
<article class="maintainerCard"><h3>Release checklist</h3><p>Versioning, docs validation, and post-release verification sequence.</p><a href="/docs/maintainers/release-workflow">Release workflow</a></article>
</div>
</section>
</div>

## Quick start snippets

```bash
dart pub add llamadart
```

```dart
import 'package:llamadart/llamadart.dart';

Future<void> main() async {
  final LlamaEngine engine = LlamaEngine(LlamaBackend());

  try {
    await engine.loadModel('path/to/model.gguf');
    await for (final token in engine.generate('Hello from llamadart')) {
      print(token);
    }
  } finally {
    await engine.dispose();
  }
}
```
