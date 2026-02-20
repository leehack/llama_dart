import 'package:jaspr/server.dart';
import 'package:jaspr_content/components/code_block.dart';
import 'package:jaspr_content/jaspr_content.dart';
import 'package:syntax_highlight_lite/syntax_highlight_lite.dart';

/// A safer code block renderer for jaspr_content.
///
/// `syntax_highlight_lite` only bundles Dart grammar by default, so attempting
/// to highlight unsupported languages can throw. This component keeps Dart
/// highlighting and falls back to plain `<pre><code>` rendering for others.
class SafeCodeBlock extends CustomComponent {
  SafeCodeBlock({
    this.defaultLanguage = 'dart',
    this.grammars = const {},
    this.codeTheme,
  }) : super.base();

  final String defaultLanguage;
  final Map<String, String> grammars;
  final HighlighterTheme? codeTheme;

  bool _initialized = false;
  HighlighterTheme? _defaultTheme;

  @override
  Component? create(Node node, NodesBuilder builder) {
    if (node
        case ElementNode(tag: 'Code' || 'CodeBlock', :final children, :final attributes) ||
            ElementNode(
              tag: 'pre',
              children: [ElementNode(tag: 'code', :final children, :final attributes)],
            )) {
      String? language = attributes['language'];
      if (language == null && (attributes['class']?.startsWith('language-') ?? false)) {
        language = attributes['class']!.substring('language-'.length);
      }

      if (!_initialized) {
        Highlighter.initialize(['dart']);
        for (final entry in grammars.entries) {
          Highlighter.addLanguage(entry.key, entry.value);
        }
        _initialized = true;
      }

      return AsyncBuilder(
        builder: (context) async {
          final source = children?.map((c) => c.innerText).join(' ') ?? '';
          final resolvedLanguage = _resolveLanguage(language);
          Highlighter? highlighter;

          if (resolvedLanguage != null) {
            highlighter = Highlighter(
              language: resolvedLanguage,
              theme: codeTheme ?? (_defaultTheme ??= await HighlighterTheme.loadDarkTheme()),
            );
          }

          return CodeBlock.from(source: source, highlighter: highlighter);
        },
      );
    }

    return null;
  }

  String? _resolveLanguage(String? rawLanguage) {
    final normalized = (rawLanguage == null || rawLanguage.trim().isEmpty)
        ? defaultLanguage
        : rawLanguage.trim().toLowerCase();

    if (normalized == 'dart') {
      return 'dart';
    }

    if (grammars.containsKey(normalized)) {
      return normalized;
    }

    // Return null for unsupported languages so the code block is rendered
    // without syntax highlighting instead of throwing during static generation.
    return null;
  }
}
