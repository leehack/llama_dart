import 'package:jaspr/dom.dart';
import 'package:jaspr/server.dart';
import 'package:jaspr_content/components/_internal/code_block_copy_button.dart';
import 'package:jaspr_content/jaspr_content.dart';

/// A resilient code block renderer that supports Mermaid and highlight.js.
class SafeCodeBlock extends CustomComponent {
  SafeCodeBlock({this.defaultLanguage = 'plaintext'}) : super.base();

  final String defaultLanguage;

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

      final source = children?.map((c) => c.innerText).join(' ') ?? '';
      final resolvedLanguage = _resolveLanguage(language);

      if (resolvedLanguage == 'mermaid') {
        return _MermaidBlock(source: source);
      }

      return _PlainCodeBlock(
        source: source,
        language: resolvedLanguage,
      );
    }

    return null;
  }

  String _resolveLanguage(String? rawLanguage) {
    final normalized = (rawLanguage == null || rawLanguage.trim().isEmpty)
        ? defaultLanguage
        : rawLanguage.trim().toLowerCase();

    if (normalized == 'text' || normalized == 'txt' || normalized == 'plain') {
      return 'plaintext';
    }

    if (normalized == 'shell' || normalized == 'sh' || normalized == 'zsh') {
      return 'bash';
    }

    if (normalized == 'yml') {
      return 'yaml';
    }

    return normalized;
  }

  @css
  static List<StyleRule> get styles => [
    css('.code-block', [
      css('&').styles(position: Position.relative()),
      css('button').styles(
        position: Position.absolute(top: 1.rem, right: 1.rem),
        opacity: 0,
        color: Colors.white,
        width: 1.25.rem,
        height: 1.25.rem,
        zIndex: ZIndex(10),
      ),
      css('&:hover button').styles(opacity: 0.75),
    ]),
  ];
}

class _MermaidBlock extends StatelessComponent {
  const _MermaidBlock({required this.source});

  final String source;

  @override
  Component build(BuildContext context) {
    return pre(classes: 'mermaid', [Component.text(source)]);
  }
}

class _PlainCodeBlock extends StatelessComponent {
  const _PlainCodeBlock({
    required this.source,
    required this.language,
  });

  final String source;
  final String language;

  @override
  Component build(BuildContext context) {
    return div(classes: 'code-block', [
      const CodeBlockCopyButton(),
      pre([
        code(
          classes: 'language-$language',
          [Component.text(source)],
        ),
      ]),
    ]);
  }
}
