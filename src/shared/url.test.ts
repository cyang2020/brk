import { describe, expect, it } from 'vitest';
import { parseUrlOrSearch } from './url';

describe('parseUrlOrSearch', () => {
  it('keeps a URL that already has a scheme', () => {
    expect(parseUrlOrSearch('  https://arc.net/max  ')).toEqual({ kind: 'url', value: 'https://arc.net/max' });
  });

  it('adds https to a bare domain', () => {
    expect(parseUrlOrSearch('example.com/docs?q=1')).toEqual({ kind: 'url', value: 'https://example.com/docs?q=1' });
  });

  it('adds http to localhost', () => {
    expect(parseUrlOrSearch('localhost:5173')).toEqual({ kind: 'url', value: 'http://localhost:5173' });
  });

  it('treats words and dotted text with spaces as a search', () => {
    expect(parseUrlOrSearch('arc browser')).toEqual({ kind: 'search', value: 'arc browser' });
    expect(parseUrlOrSearch('node.js tutorial')).toEqual({ kind: 'search', value: 'node.js tutorial' });
  });
});
