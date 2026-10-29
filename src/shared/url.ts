export interface UrlOrSearch {
  kind: 'url' | 'search';
  value: string;
}

const HAS_SCHEME = /^[a-z][a-z\d+.-]*:\/\//i;
const LOCALHOST = /^localhost(:\d+)?(\/\S*)?$/i;
const BARE_HOST = /^[a-z\d-]+(\.[a-z\d-]+)+(:\d+)?(\/\S*)?$/i;

/** Decide whether command bar input is a URL to open or text to search for. */
export function parseUrlOrSearch(input: string): UrlOrSearch {
  const text = input.trim();
  if (HAS_SCHEME.test(text) || text.startsWith('about:')) return { kind: 'url', value: text };
  if (LOCALHOST.test(text)) return { kind: 'url', value: `http://${text}` };
  if (BARE_HOST.test(text)) return { kind: 'url', value: `https://${text}` };
  return { kind: 'search', value: text };
}
