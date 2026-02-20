import type { Config } from '@docusaurus/types';
import type * as Preset from '@docusaurus/preset-classic';
import { themes as prismThemes } from 'prism-react-renderer';

const config: Config = {
  title: 'llamadart',
  tagline: 'Run llama.cpp from Dart and Flutter across native and web',
  favicon: 'img/logo.svg',

  url: 'https://llamadart.leehack.com',
  baseUrl: '/',

  organizationName: 'leehack',
  projectName: 'llamadart',

  onBrokenLinks: 'throw',
  trailingSlash: false,
  markdown: {
    mermaid: true,
    hooks: {
      onBrokenMarkdownLinks: 'throw'
    }
  },
  themes: ['@docusaurus/theme-mermaid'],

  i18n: {
    defaultLocale: 'en',
    locales: ['en']
  },

  presets: [
    [
      'classic',
      {
        docs: {
          sidebarPath: './sidebars.ts',
          editUrl: 'https://github.com/leehack/llamadart/tree/main/website/'
        },
        blog: false,
        theme: {
          customCss: './src/css/custom.css'
        }
      } satisfies Preset.Options
    ]
  ],

  themeConfig: {
    image: 'img/logo.svg',
    colorMode: {
      defaultMode: 'light',
      respectPrefersColorScheme: true
    },
    navbar: {
      title: 'llamadart',
      logo: {
        alt: 'llamadart logo',
        src: 'img/logo.svg'
      },
      items: [
        {
          type: 'docSidebar',
          sidebarId: 'docsSidebar',
          position: 'left',
          label: 'Docs'
        },
        {
          to: '/api',
          label: 'API',
          position: 'left'
        },
        {
          href: 'https://pub.dev/packages/llamadart',
          label: 'pub.dev',
          position: 'right'
        },
        {
          href: 'https://github.com/leehack/llamadart',
          label: 'GitHub',
          position: 'right'
        }
      ]
    },
    footer: {
      style: 'dark',
      links: [
        {
          title: 'Docs',
          items: [
            {
              label: 'Introduction',
              to: '/docs/intro'
            },
            {
              label: 'Quickstart',
              to: '/docs/getting-started/quickstart'
            },
            {
              label: 'API Reference',
              to: '/api'
            }
          ]
        },
        {
          title: 'Community',
          items: [
            {
              label: 'Issues',
              href: 'https://github.com/leehack/llamadart/issues'
            }
          ]
        },
        {
          title: 'More',
          items: [
            {
              label: 'Repository',
              href: 'https://github.com/leehack/llamadart'
            },
            {
              label: 'License',
              href: 'https://github.com/leehack/llamadart/blob/main/LICENSE'
            }
          ]
        }
      ],
      copyright: `Copyright © ${new Date().getFullYear()} llamadart contributors.`
    },
    prism: {
      theme: prismThemes.github,
      darkTheme: prismThemes.dracula,
      additionalLanguages: ['dart', 'yaml', 'bash', 'json', 'diff']
    }
  } satisfies Preset.ThemeConfig
};

export default config;
