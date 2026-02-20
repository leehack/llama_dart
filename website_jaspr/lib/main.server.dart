/// The entrypoint for the **server** environment.
///
/// The [main] method will only be executed on the server during pre-rendering.
/// To run code on the client, check the `main.client.dart` file.
library;

// Server-specific Jaspr import.
import 'package:jaspr/server.dart';

import 'package:jaspr_content/components/callout.dart';
import 'package:jaspr_content/components/github_button.dart';
import 'package:jaspr_content/components/header.dart';
import 'package:jaspr_content/components/image.dart';
import 'package:jaspr_content/components/sidebar.dart';
import 'package:jaspr_content/components/theme_toggle.dart';
import 'package:jaspr_content/jaspr_content.dart';
import 'package:jaspr_content/theme.dart';

import 'components/safe_code_block.dart';

// This file is generated automatically by Jaspr, do not remove or edit.
import 'main.server.options.dart';

void main() {
  // Initializes the server environment with the generated default options.
  Jaspr.initializeApp(
    options: defaultServerOptions,
  );

  // Starts the app.
  //
  // [ContentApp] spins up the content rendering pipeline from jaspr_content to render
  // your markdown files in the content/ directory to a beautiful documentation site.
  runApp(
    ContentApp(
      // Enables mustache templating inside the markdown files.
      templateEngine: MustacheTemplateEngine(),
      parsers: [
        MarkdownParser(),
      ],
      extensions: [
        // Adds heading anchors to each heading.
        HeadingAnchorsExtension(),
        // Generates a table of contents for each page.
        TableOfContentsExtension(),
      ],
      components: [
        // The <Info> block and other callouts.
        Callout(),
        // Adds syntax highlighting to code blocks.
        SafeCodeBlock(),
        // Adds zooming and caption support to images.
        Image(zoom: true),
      ],
      layouts: [
        // Out-of-the-box layout for documentation sites.
        DocsLayout(
          header: Header(
            title: 'llamadart',
            logo: '/images/logo.svg',
            items: [
              // Enables switching between light and dark mode.
              ThemeToggle(),
              // Shows github stats.
              GitHubButton(repo: 'leehack/llamadart'),
            ],
          ),
          sidebar: Sidebar(
            groups: [
              SidebarGroup(
                title: 'Getting Started',
                links: [
                  SidebarLink(
                    text: 'Installation',
                    href: '/docs/getting-started/installation',
                  ),
                  SidebarLink(
                    text: 'Finding Models',
                    href: '/docs/getting-started/finding-models',
                  ),
                  SidebarLink(
                    text: 'Quickstart',
                    href: '/docs/getting-started/quickstart',
                  ),
                  SidebarLink(
                    text: 'First Chat Session',
                    href: '/docs/getting-started/first-chat-session',
                  ),
                ],
              ),
              SidebarGroup(
                title: 'Core Concepts',
                links: [
                  SidebarLink(
                    text: 'Architecture',
                    href: '/docs/guides/architecture',
                  ),
                  SidebarLink(
                    text: 'API Levels',
                    href: '/docs/guides/api-levels',
                  ),
                  SidebarLink(
                    text: 'Model Lifecycle',
                    href: '/docs/guides/model-lifecycle',
                  ),
                  SidebarLink(
                    text: 'Generation & Streaming',
                    href: '/docs/guides/generation-and-streaming',
                  ),
                  SidebarLink(
                    text: 'Chat Templates & Parsing',
                    href: '/docs/guides/chat-template-and-parsing',
                  ),
                  SidebarLink(
                    text: 'Template Engine Internals',
                    href: '/docs/guides/template-engine-internals',
                  ),
                ],
              ),
              SidebarGroup(
                title: 'Advanced Features',
                links: [
                  SidebarLink(
                    text: 'Tool Calling',
                    href: '/docs/guides/tool-calling',
                  ),
                  SidebarLink(
                    text: 'Multimodal',
                    href: '/docs/guides/multimodal',
                  ),
                  SidebarLink(
                    text: 'LoRA Adapters',
                    href: '/docs/guides/lora-adapters',
                  ),
                ],
              ),
              SidebarGroup(
                title: 'Configuration & Tuning',
                links: [
                  SidebarLink(
                    text: 'Runtime Parameters',
                    href: '/docs/configuration/runtime-parameters',
                  ),
                  SidebarLink(
                    text: 'Performance Tuning',
                    href: '/docs/guides/performance-tuning',
                  ),
                  SidebarLink(
                    text: 'Logging',
                    href: '/docs/configuration/logging',
                  ),
                ],
              ),
              SidebarGroup(
                title: 'Platforms',
                links: [
                  SidebarLink(
                    text: 'Platform & Backend Matrix',
                    href: '/docs/platforms/support-matrix',
                  ),
                  SidebarLink(
                    text: 'Native Build Hooks',
                    href: '/docs/platforms/native-build-hooks',
                  ),
                  SidebarLink(
                    text: 'Linux Prerequisites',
                    href: '/docs/platforms/linux-prerequisites',
                  ),
                  SidebarLink(
                    text: 'WebGPU Bridge',
                    href: '/docs/platforms/webgpu-bridge',
                  ),
                ],
              ),
              SidebarGroup(
                title: 'Examples',
                links: [
                  SidebarLink(text: 'Overview', href: '/docs/examples/overview'),
                  SidebarLink(
                    text: 'Basic App',
                    href: '/docs/examples/basic-app',
                  ),
                  SidebarLink(text: 'Chat App', href: '/docs/examples/chat-app'),
                  SidebarLink(
                    text: 'llamadart_cli',
                    href: '/docs/examples/llamadart-cli',
                  ),
                  SidebarLink(
                    text: 'llamadart_server',
                    href: '/docs/examples/llamadart-server',
                  ),
                ],
              ),
              SidebarGroup(
                title: 'Help & Reference',
                links: [
                  SidebarLink(text: "Overview", href: '/'),
                  SidebarLink(
                    text: 'Introduction',
                    href: '/docs/intro',
                  ),
                  SidebarLink(
                    text: 'Common Issues',
                    href: '/docs/troubleshooting/common-issues',
                  ),
                  SidebarLink(
                    text: 'Recent Releases',
                    href: '/docs/changelog/recent-releases',
                  ),
                ],
              ),
              SidebarGroup(
                title: 'Migration',
                links: [
                  SidebarLink(
                    text: 'Upgrade Checklist',
                    href: '/docs/migration/upgrade-checklist',
                  ),
                  SidebarLink(
                    text: '0.4.x -> 0.5.x',
                    href: '/docs/migration/0-4-to-0-5',
                  ),
                  SidebarLink(
                    text: '0.5.x -> 0.6.x',
                    href: '/docs/migration/0-5-to-0-6',
                  ),
                  SidebarLink(
                    text: 'Migration Status',
                    href: '/migration-status',
                  ),
                  SidebarLink(
                    text: 'Legacy Docusaurus',
                    href: '/legacy-docusaurus',
                  ),
                ],
              ),
              SidebarGroup(
                title: 'Maintainers',
                links: [
                  SidebarLink(
                    text: 'Maintainer Overview',
                    href: '/docs/maintainers/docs-site',
                  ),
                  SidebarLink(
                    text: 'Runtime Ownership',
                    href: '/docs/maintainers/runtime-ownership',
                  ),
                  SidebarLink(
                    text: 'Native and Web Sync',
                    href: '/docs/maintainers/native-and-web-sync',
                  ),
                  SidebarLink(
                    text: 'Release Workflow',
                    href: '/docs/maintainers/release-workflow',
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
      theme: ContentTheme(
        // Customizes the default theme colors.
        primary: ThemeColor(
          ThemeColors.emerald.$600,
          dark: ThemeColors.emerald.$300,
        ),
        background: ThemeColor(
          ThemeColors.stone.$50,
          dark: ThemeColors.zinc.$950,
        ),
        colors: [
          ContentColors.quoteBorders.apply(ThemeColors.emerald.$400),
        ],
      ),
    ),
  );
}
