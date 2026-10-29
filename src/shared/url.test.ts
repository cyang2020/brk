import { describe, expect, it } from 'vitest'
import { displayUrl, isAllowedUrl, resolveTypedInput } from './url'

describe('resolveTypedInput', () => {
  it('returns null for empty or whitespace input', () => {
    expect(resolveTypedInput('')).toBeNull()
    expect(resolveTypedInput('   \t ')).toBeNull()
  })

  it('treats a host with a port, an IP address or a dotted domain as a URL and adds the scheme', () => {
    expect(resolveTypedInput('localhost:5173/a')).toEqual({ kind: 'url', url: 'http://localhost:5173/a' })
    expect(resolveTypedInput('127.0.0.1:8080')).toEqual({ kind: 'url', url: 'http://127.0.0.1:8080/' })
    expect(resolveTypedInput('192.168.0.1')).toEqual({ kind: 'url', url: 'http://192.168.0.1/' })
    expect(resolveTypedInput('example.com')).toEqual({ kind: 'url', url: 'https://example.com/' })
    expect(resolveTypedInput('  news.ycombinator.com/item?id=1  ')).toEqual({ kind: 'url', url: 'https://news.ycombinator.com/item?id=1' })
  })

  it('keeps an explicit allowed scheme', () => {
    expect(resolveTypedInput('https://x.y/z')).toEqual({ kind: 'url', url: 'https://x.y/z' })
    expect(resolveTypedInput('http://127.0.0.1:9/page2.html')).toEqual({ kind: 'url', url: 'http://127.0.0.1:9/page2.html' })
    expect(resolveTypedInput('file:///tmp/a.html')).toEqual({ kind: 'url', url: 'file:///tmp/a.html' })
    expect(resolveTypedInput('about:blank')).toEqual({ kind: 'url', url: 'about:blank' })
  })

  it('searches a bare word, text with spaces, a number and a refused scheme', () => {
    expect(resolveTypedInput('arc')).toEqual({ kind: 'search', query: 'arc', url: 'https://www.google.com/search?q=arc' })
    expect(resolveTypedInput('localhost')).toEqual({ kind: 'search', query: 'localhost', url: 'https://www.google.com/search?q=localhost' })
    expect(resolveTypedInput('arc browser shortcuts')).toEqual({
      kind: 'search',
      query: 'arc browser shortcuts',
      url: 'https://www.google.com/search?q=arc%20browser%20shortcuts',
    })
    expect(resolveTypedInput('3.14')).toMatchObject({ kind: 'search', query: '3.14' })
    expect(resolveTypedInput('javascript:alert(1)')).toEqual({
      kind: 'search',
      query: 'javascript:alert(1)',
      url: 'https://www.google.com/search?q=javascript%3Aalert(1)',
    })
    expect(resolveTypedInput('chrome://settings')).toMatchObject({ kind: 'search' })
  })
})

describe('isAllowedUrl', () => {
  it('allows http, https, file and about:blank', () => {
    expect(isAllowedUrl('http://127.0.0.1:9/a')).toBe(true)
    expect(isAllowedUrl('https://example.com/')).toBe(true)
    expect(isAllowedUrl('file:///tmp/a.html')).toBe(true)
    expect(isAllowedUrl('about:blank')).toBe(true)
  })

  it('refuses every other scheme and unparseable text', () => {
    for (const url of ['javascript:alert(1)', 'data:text/html,hi', 'chrome://settings', 'devtools://devtools', 'about:config', 'not a url', 'http://']) {
      expect(isAllowedUrl(url), url).toBe(false)
    }
  })
})

describe('displayUrl', () => {
  it('drops the scheme, www. and the trailing slash', () => {
    expect(displayUrl('https://www.example.com/')).toBe('example.com')
    expect(displayUrl('https://example.com/a/b/')).toBe('example.com/a/b')
    expect(displayUrl('http://127.0.0.1:9/page2.html?x=1#top')).toBe('127.0.0.1:9/page2.html')
  })

  it('shows a file path and leaves other text alone', () => {
    expect(displayUrl('file:///tmp/a.html')).toBe('/tmp/a.html')
    expect(displayUrl('about:blank')).toBe('about:blank')
  })
})
