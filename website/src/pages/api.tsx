import Layout from '@theme/Layout';
import {useEffect} from 'react';

const pubDevApiDocsUrl = 'https://pub.dev/documentation/llamadart/latest/';

export default function ApiRedirectPage(): JSX.Element {
  useEffect(() => {
    window.location.replace(pubDevApiDocsUrl);
  }, []);

  return (
    <Layout title="API Reference" description="llamadart API docs on pub.dev">
      <main className="homeContainer">
        <section className="heroPanel">
          <h1>API Reference</h1>
          <p>Redirecting to the latest API docs on pub.dev.</p>
          <p>
            If redirection does not start, open:
            <br />
            <a href={pubDevApiDocsUrl}>{pubDevApiDocsUrl}</a>
          </p>
        </section>
      </main>
    </Layout>
  );
}
