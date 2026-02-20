import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr_content/jaspr_content.dart';

/// Docs layout with project-specific head tags, scripts, and visual tweaks.
class LlamadartDocsLayout extends DocsLayout {
  const LlamadartDocsLayout({
    required Component topHeader,
    required Component navigationSidebar,
    Component? pageFooter,
    this.siteUrl = 'https://llamadart.leehack.com',
  }) : super(
         header: topHeader,
         sidebar: navigationSidebar,
         footer: pageFooter,
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
        'Local LLM inference for Dart and Flutter across native and web.';
    final imageUrl = pageData['image']?.toString() ?? siteData['image']?.toString();

    yield link(rel: 'canonical', href: canonicalUrl);
    yield meta(attributes: {'property': 'og:type'}, content: 'website');
    yield meta(attributes: {'property': 'og:site_name'}, content: 'llamadart docs');
    yield meta(attributes: {'property': 'og:url'}, content: canonicalUrl);
    if (imageUrl != null && imageUrl.isNotEmpty) {
      yield meta(attributes: {'property': 'og:image'}, content: _absoluteUrl(resolvedSiteUrl, imageUrl));
    }

    yield meta(name: 'twitter:card', content: imageUrl == null ? 'summary' : 'summary_large_image');
    yield meta(name: 'twitter:title', content: title);
    yield meta(name: 'twitter:description', content: description);
    if (imageUrl != null && imageUrl.isNotEmpty) {
      yield meta(name: 'twitter:image', content: _absoluteUrl(resolvedSiteUrl, imageUrl));
    }

    yield link(
      rel: 'stylesheet',
      href: 'https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.11.1/styles/github.min.css',
    );
    yield link(
      rel: 'stylesheet',
      href: 'https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.11.1/styles/github-dark.min.css',
      attributes: {'media': '(prefers-color-scheme: dark)'},
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

    yield Style(styles: _styles);
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

  static List<StyleRule> get _styles => [
    css('.home-landing', [
      css('&').styles(
        display: Display.flex,
        flexDirection: FlexDirection.column,
        gap: Gap.all(1.25.rem),
      ),
      css('.home-hero', [
        css('&').styles(
          padding: Padding.only(top: 1.5.rem, left: 1.5.rem, right: 1.5.rem, bottom: 1.5.rem),
          radius: BorderRadius.circular(1.rem),
          border: Border.all(width: 1.px, color: Color('#86efac')),
          raw: {
            'background': 'linear-gradient(140deg, #ecfdf5 0%, #dbeafe 100%)',
          },
        ),
      ]),
      css('.home-eyebrow').styles(
        fontWeight: FontWeight.w700,
        fontSize: 0.8.rem,
        letterSpacing: 0.08.rem,
        textTransform: TextTransform.upperCase,
        color: Color('#047857'),
        margin: Margin.only(bottom: 0.5.rem),
      ),
      css('.home-title').styles(
        margin: Margin.only(bottom: 0.5.rem),
        fontSize: 2.1.rem,
        lineHeight: 1.1.em,
        color: Color('#0f172a'),
      ),
      css('.home-subtitle').styles(
        margin: Margin.only(bottom: 1.rem),
        fontSize: 1.05.rem,
        lineHeight: 1.55.em,
        color: Color('#1f2937'),
      ),
      css('.home-actions', [
        css('&').styles(
          display: Display.flex,
          gap: Gap.all(0.75.rem),
          flexWrap: FlexWrap.wrap,
        ),
        css('a').styles(
          display: Display.inlineBlock,
          padding: Padding.symmetric(horizontal: 0.9.rem, vertical: 0.55.rem),
          radius: BorderRadius.circular(0.6.rem),
          textDecoration: TextDecoration.none,
          fontWeight: FontWeight.w600,
          border: Border.all(width: 1.px, color: Color('#10b981')),
        ),
        css('a.primary').styles(
          backgroundColor: Color('#059669'),
          color: Colors.white,
        ),
        css('a.secondary').styles(
          backgroundColor: Colors.white,
          color: Color('#065f46'),
        ),
      ]),
      css('.home-grid', [
        css('&').styles(
          display: Display.grid,
          raw: {'grid-template-columns': 'repeat(auto-fit, minmax(220px, 1fr))'},
          gap: Gap.all(0.85.rem),
        ),
      ]),
      css('.home-card', [
        css('&').styles(
          display: Display.block,
          padding: Padding.only(top: 0.95.rem, left: 0.95.rem, right: 0.95.rem, bottom: 0.95.rem),
          radius: BorderRadius.circular(0.75.rem),
          textDecoration: TextDecoration.none,
          border: Border.all(width: 1.px, color: Color('#d6d3d1')),
          backgroundColor: Colors.white,
          color: Color('#0f172a'),
        ),
        css('&:hover').styles(
          border: Border.all(width: 1.px, color: Color('#34d399')),
        ),
        css('strong').styles(
          display: Display.block,
          margin: Margin.only(bottom: 0.3.rem),
        ),
        css('span').styles(
          display: Display.block,
          color: Color('#334155'),
          fontSize: 0.9.rem,
          lineHeight: 1.4.em,
        ),
      ]),
      css.media(MediaQuery.all(maxWidth: 768.px), [
        css('.home-title').styles(fontSize: 1.7.rem),
      ]),
    ]),
    css('html[data-theme="dark"] .home-landing .home-hero').styles(
      border: Border.all(width: 1.px, color: Color('#0f766e')),
      raw: {
        'background': 'linear-gradient(140deg, #052e2b 0%, #082f49 100%)',
      },
    ),
    css('html[data-theme="dark"] .home-landing .home-eyebrow').styles(color: Color('#6ee7b7')),
    css('html[data-theme="dark"] .home-landing .home-title').styles(color: Color('#e2e8f0')),
    css('html[data-theme="dark"] .home-landing .home-subtitle').styles(color: Color('#cbd5e1')),
    css('html[data-theme="dark"] .home-landing .home-actions a.secondary').styles(
      backgroundColor: Color('#111827'),
      color: Color('#99f6e4'),
      border: Border.all(width: 1.px, color: Color('#0f766e')),
    ),
    css('html[data-theme="dark"] .home-landing .home-card').styles(
      backgroundColor: Color('#09090b'),
      border: Border.all(width: 1.px, color: Color('#3f3f46')),
      color: Color('#f3f4f6'),
    ),
    css('html[data-theme="dark"] .home-landing .home-card span').styles(
      color: Color('#d1d5db'),
    ),
    css('.content section.content', [
      css('pre.mermaid').styles(
        backgroundColor: Color('#f8fafc'),
        border: Border.all(width: 1.px, color: Color('#cbd5e1')),
        radius: BorderRadius.circular(0.7.rem),
        padding: Padding.only(top: 0.9.rem, left: 0.9.rem, right: 0.9.rem, bottom: 0.9.rem),
        overflow: Overflow.auto,
      ),
    ]),
    css('html[data-theme="dark"] .content section.content pre.mermaid').styles(
      backgroundColor: Color('#0f172a'),
      border: Border.all(width: 1.px, color: Color('#334155')),
    ),
  ];
}
