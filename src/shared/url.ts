/**
 * Typed-input resolution and URL policy. The overlay calls `resolveTypedInput` to label the "open what you typed"
 * row; main calls it again when `commandBar/submit` arrives, so a renderer's guess is never trusted.
 */

export type TypedInput =
  | { readonly kind: 'url'; readonly url: string }
  | { readonly kind: 'search'; readonly query: string; readonly url: string }

/** Our choice. Arc's search engine is a per-profile setting whose default is not in static data. */
export const SEARCH_TEMPLATE = 'https://www.google.com/search?q=%s'

/**
 * `localhost:5173/a`, `127.0.0.1:8080`, `example.com`, `https://x.y/z` are URLs (scheme added when missing);
 * anything with spaces or without a dot/port/known scheme is a search. Empty or whitespace input returns null.
 */
export function resolveTypedInput(text: string): TypedInput | null {
  throw new Error('not implemented')
}

/** Schemes a tab may load: http, https, about:blank. javascript:, file:, chrome:, devtools: are refused. */
export function isAllowedUrl(url: string): boolean {
  throw new Error('not implemented')
}

/** URL pill text: host plus path, no scheme, no trailing slash, `www.` dropped. */
export function displayUrl(url: string): string {
  throw new Error('not implemented')
}
