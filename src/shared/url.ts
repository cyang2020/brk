/**
 * Typed-input resolution and URL policy. The overlay calls `resolveTypedInput` to label the "open what you typed"
 * row; main calls it again when `commandBar/submit` arrives, so a renderer's guess is never trusted.
 */

export type TypedInput =
  | { readonly kind: 'url'; readonly url: string }
  | { readonly kind: 'search'; readonly query: string; readonly url: string }

/** Our choice. Arc's search engine is a per-profile setting whose default is not in static data. */
export const SEARCH_TEMPLATE = 'https://www.google.com/search?q=%s'

const SCHEME = /^[a-z][a-z0-9+.-]*:/i
/** `host[:port]` followed by the end, a path, a query or a fragment. */
const HOST_AND_REST = /^([^/?#\s]+)([/?#].*)?$/
const LABEL = /^[a-z0-9](?:[a-z0-9-]*[a-z0-9])?$/i
const IPV4 = /^(?:\d{1,3}\.){3}\d{1,3}$/

function parse(url: string): URL | null {
  try {
    return new URL(url)
  } catch {
    return null
  }
}

/** `example.com`, `a.b.co`, `127.0.0.1`, or any host with a numeric port (`localhost:5173`). */
function hostLike(authority: string): { readonly local: boolean } | null {
  const portAt = authority.lastIndexOf(':')
  const hasPort = portAt > 0 && /^\d{1,5}$/.test(authority.slice(portAt + 1))
  const host = hasPort ? authority.slice(0, portAt) : authority
  if (IPV4.test(host)) return host.split('.').every((n) => Number(n) <= 255) ? { local: true } : null
  const labels = host.split('.')
  if (!labels.every((l) => LABEL.test(l))) return null
  if (host.toLowerCase() === 'localhost') return hasPort ? { local: true } : null
  if (labels.length >= 2 && /^[a-z]{2,63}$/i.test(labels[labels.length - 1]!)) return { local: false }
  return hasPort ? { local: true } : null
}

function search(query: string): TypedInput {
  return { kind: 'search', query, url: SEARCH_TEMPLATE.replace('%s', encodeURIComponent(query)) }
}

/**
 * `localhost:5173/a`, `127.0.0.1:8080`, `example.com`, `https://x.y/z` are URLs (scheme added when missing: `http://`
 * for localhost and IP addresses, `https://` otherwise); anything with spaces or without a dot/port/known scheme is
 * a search. A scheme that `isAllowedUrl` refuses (`javascript:`, `chrome:`) is searched, never returned as a URL.
 * Empty or whitespace input returns null.
 */
export function resolveTypedInput(text: string): TypedInput | null {
  const input = text.trim()
  if (input === '') return null
  if (/\s/.test(input)) return search(input)
  const hostMatch = HOST_AND_REST.exec(input)
  const host = hostMatch ? hostLike(hostMatch[1]!) : null
  if (SCHEME.test(input) && !host) {
    const url = parse(input)
    return url && isAllowedUrl(url.href) ? { kind: 'url', url: url.href } : search(input)
  }
  if (host) {
    const url = parse(`${host.local ? 'http' : 'https'}://${input}`)
    if (url && isAllowedUrl(url.href)) return { kind: 'url', url: url.href }
  }
  return search(input)
}

/**
 * Schemes a tab may load: http and https (with a host), file, and exactly about:blank. javascript:, data:, chrome:,
 * devtools: and every other scheme are refused.
 */
export function isAllowedUrl(url: string): boolean {
  if (url === 'about:blank') return true
  const parsed = parse(url)
  if (!parsed) return false
  if (parsed.protocol === 'http:' || parsed.protocol === 'https:') return parsed.hostname !== ''
  return parsed.protocol === 'file:'
}

/** URL pill text: host plus path, no scheme, no trailing slash, `www.` dropped. A file URL shows its path. */
export function displayUrl(url: string): string {
  const parsed = parse(url)
  if (!parsed || (parsed.protocol !== 'http:' && parsed.protocol !== 'https:' && parsed.protocol !== 'file:')) return url
  const host = parsed.host.replace(/^www\./i, '')
  const text = `${host}${parsed.pathname}`.replace(/\/+$/, '')
  return text === '' ? url : text
}
