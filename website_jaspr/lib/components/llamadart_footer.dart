import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

class LlamadartFooter extends StatelessComponent {
  const LlamadartFooter({super.key});

  @override
  Component build(BuildContext context) {
    final year = DateTime.now().year;

    return footer(classes: 'site-footer', [
      div(classes: 'site-footer-inner', [
        div(classes: 'site-footer-grid', [
          _FooterColumn(
            title: 'Docs',
            links: const [
              _FooterLink(label: 'Introduction', href: '/docs/intro'),
              _FooterLink(
                label: 'Quickstart',
                href: '/docs/getting-started/quickstart',
              ),
              _FooterLink(
                label: 'API Reference',
                href: 'https://pub.dev/packages/llamadart',
              ),
            ],
          ),
          _FooterColumn(
            title: 'Community',
            links: const [
              _FooterLink(
                label: 'Issues',
                href: 'https://github.com/leehack/llamadart/issues',
              ),
            ],
          ),
          _FooterColumn(
            title: 'More',
            links: const [
              _FooterLink(
                label: 'Repository',
                href: 'https://github.com/leehack/llamadart',
              ),
              _FooterLink(
                label: 'License',
                href: 'https://github.com/leehack/llamadart/blob/main/LICENSE',
              ),
            ],
          ),
        ]),
        div(classes: 'site-footer-copy', [
          Component.text('Copyright © $year llamadart contributors.'),
        ]),
      ]),
    ]);
  }
}

class _FooterColumn extends StatelessComponent {
  const _FooterColumn({
    required this.title,
    required this.links,
  });

  final String title;
  final List<_FooterLink> links;

  @override
  Component build(BuildContext context) {
    return div(classes: 'site-footer-col', [
      h3([Component.text(title)]),
      ul([
        for (final link in links)
          li([
            a(href: link.href, [Component.text(link.label)]),
          ]),
      ]),
    ]);
  }
}

class _FooterLink {
  const _FooterLink({
    required this.label,
    required this.href,
  });

  final String label;
  final String href;
}
