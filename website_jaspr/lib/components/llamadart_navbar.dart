import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr_content/components/sidebar_toggle_button.dart';
import 'package:jaspr_content/components/theme_toggle.dart';

class LlamadartNavbar extends StatelessComponent {
  const LlamadartNavbar({super.key});

  @override
  Component build(BuildContext context) {
    return header(classes: 'header llm-navbar', [
      const SidebarToggleButton(),
      a(classes: 'header-title', href: '/', [
        img(src: '/images/logo.svg', alt: 'llamadart logo'),
        span([Component.text('llamadart')]),
      ]),
      nav(classes: 'llm-nav llm-nav-left', [
        a(href: '/docs/intro', [Component.text('Docs')]),
        a(href: 'https://pub.dev/packages/llamadart', [Component.text('API')]),
      ]),
      nav(classes: 'llm-nav llm-nav-right', [
        a(href: 'https://pub.dev/packages/llamadart', [Component.text('pub.dev')]),
        a(href: 'https://github.com/leehack/llamadart', [Component.text('GitHub')]),
        const ThemeToggle(),
      ]),
    ]);
  }
}
