import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr_content/jaspr_content.dart';

import 'llamadart_footer.dart';

/// Docs layout that aligns head metadata and global scripts/styles
/// with the existing llamadart docs experience.
class LlamadartDocsLayout extends DocsLayout {
  const LlamadartDocsLayout({
    required Component topHeader,
    required Component navigationSidebar,
    this.siteUrl = 'https://llamadart.leehack.com',
  }) : super(
         header: topHeader,
         sidebar: navigationSidebar,
       );

  final String siteUrl;

  @override
  Iterable<Component> buildHead(Page page) sync* {
    yield* super.buildHead(page);

    final pageData = page.data.page;
    final siteData = page.data.site;

    final resolvedSiteUrl = siteData['siteUrl']?.toString() ?? siteUrl;
    final canonicalUrl = _canonicalUrl(resolvedSiteUrl, page.url);
    final title = pageData['title']?.toString() ?? siteData['titleBase']?.toString() ?? 'llamadart docs';
    final description =
        pageData['description']?.toString() ??
        siteData['description']?.toString() ??
        'Run llama.cpp from Dart and Flutter across native and web.';
    final imageUrl = pageData['image']?.toString() ?? siteData['image']?.toString();

    yield link(rel: 'canonical', href: canonicalUrl);
    yield meta(attributes: {'property': 'og:type'}, content: 'website');
    yield meta(attributes: {'property': 'og:site_name'}, content: 'llamadart');
    yield meta(attributes: {'property': 'og:url'}, content: canonicalUrl);
    if (imageUrl != null && imageUrl.isNotEmpty) {
      yield meta(
        attributes: {'property': 'og:image'},
        content: _absoluteUrl(resolvedSiteUrl, imageUrl),
      );
    }

    yield meta(
      name: 'twitter:card',
      content: imageUrl == null ? 'summary' : 'summary_large_image',
    );
    yield meta(name: 'twitter:title', content: title);
    yield meta(name: 'twitter:description', content: description);
    if (imageUrl != null && imageUrl.isNotEmpty) {
      yield meta(
        name: 'twitter:image',
        content: _absoluteUrl(resolvedSiteUrl, imageUrl),
      );
    }

    yield link(
      rel: 'preconnect',
      href: 'https://fonts.googleapis.com',
    );
    yield link(
      rel: 'preconnect',
      href: 'https://fonts.gstatic.com',
      attributes: {'crossorigin': ''},
    );
    yield link(
      rel: 'stylesheet',
      href:
          'https://fonts.googleapis.com/css2?family=Chivo:wght@500;600;700&family=Inter:wght@400;500;600;700&family=IBM+Plex+Mono:wght@400;500&display=swap',
    );
    yield link(
      rel: 'stylesheet',
      href: 'https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.11.1/styles/github.min.css',
    );
    yield link(
      rel: 'stylesheet',
      href: 'https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.11.1/styles/github-dark.min.css',
      attributes: {'media': '(prefers-color-scheme: dark)'},
    );
    yield link(
      rel: 'stylesheet',
      href: '/styles/llamadart.css',
    );
    yield script(
      src: 'https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.11.1/highlight.min.js',
      defer: true,
    );
    yield script(
      src: 'https://cdn.jsdelivr.net/npm/mermaid@11.4.1/dist/mermaid.min.js',
      defer: true,
    );
    yield script(content: _docsClientScript);
  }

  @override
  Component buildBody(Page page, Component child) {
    return Component.fragment([
      super.buildBody(page, child),
      const LlamadartFooter(),
    ]);
  }

  String _canonicalUrl(String baseUrl, String pageUrl) {
    final normalizedBase = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
    final normalizedPath = pageUrl == '/' ? '' : pageUrl;
    return '$normalizedBase$normalizedPath';
  }

  String _absoluteUrl(String baseUrl, String target) {
    if (target.startsWith('http://') || target.startsWith('https://')) {
      return target;
    }

    final normalizedBase = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
    final normalizedTarget = target.startsWith('/') ? target : '/$target';
    return '$normalizedBase$normalizedTarget';
  }

  static const String _docsClientScript = '''
window.addEventListener('load', function () {
  if (window.hljs && typeof window.hljs.highlightAll === 'function') {
    window.hljs.highlightAll();
  }

  if (window.mermaid) {
    window.mermaid.initialize({
      startOnLoad: false,
      securityLevel: 'loose'
    });
    if (typeof window.mermaid.run === 'function') {
      window.mermaid.run({ querySelector: '.mermaid' });
    }
  }
});
''';
}
