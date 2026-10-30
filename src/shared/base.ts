/**
 * Primitive types every process shares: branded ids, time, geometry, platform.
 *
 * Pure module: no Electron, DOM, or Node imports. It compiles into the node, web, and e2e projects alike.
 */
import { z } from 'zod'

/** Nominal typing: an `ItemId` is a string, but a `SpaceId` is not an `ItemId`. */
export type Brand<T, Name extends string> = T & { readonly __brand: Name }

/** Any sidebar item: tab, folder, split, or section root (Arc: `Identifier<SidebarItem>`). */
export type ItemId = Brand<string, 'ItemId'>
/** Arc: `Identifier<SpaceModel>`. */
export type SpaceId = Brand<string, 'SpaceId'>
/** Arc: `ADKModels.WindowID`. */
export type WindowId = Brand<string, 'WindowId'>
/** One archive entry. A tab archived, restored, and archived again gets a second entry. */
export type ArchiveId = Brand<string, 'ArchiveId'>
/**
 * Epoch milliseconds from the main process's injected clock. Domain and renderer code never call `Date.now()`
 * for domain time, so e2e can move the clock (auto-archive scenario) and every surface agrees on "now".
 */
export type Instant = Brand<number, 'Instant'>

export type Platform = 'darwin' | 'linux' | 'win32'

export interface Point {
  readonly x: number
  readonly y: number
}
export interface Size {
  readonly width: number
  readonly height: number
}
export interface Rect extends Point, Size {}

/**
 * A valid id is a non-empty string of at most 64 chars that does not name an `Object.prototype` member. Ids reach
 * plain-object record keys (`doc.spaces[id]`, `doc.items[id]`); a name like "__proto__", "constructor" or "toString"
 * would read an inherited member as if it were an entry (truthy) or, on write, pollute `Object.prototype`. Rejecting
 * them here is the boundary fix; `own` (src/domain/model.ts) is the in-domain backstop. Real ids are random UUIDs, so
 * nothing legitimate is rejected. `!(value in {})` catches every inherited prototype member name.
 */
const isId = (value: unknown): boolean =>
  typeof value === 'string' && value.length > 0 && value.length <= 64 && value !== 'prototype' && !(value in {})

export const ItemIdSchema = z.custom<ItemId>(isId, 'expected an item id')
export const SpaceIdSchema = z.custom<SpaceId>(isId, 'expected a space id')
export const WindowIdSchema = z.custom<WindowId>(isId, 'expected a window id')
export const ArchiveIdSchema = z.custom<ArchiveId>(isId, 'expected an archive id')
export const InstantSchema = z.custom<Instant>(
  (value) => typeof value === 'number' && Number.isFinite(value),
  'expected an instant',
)
export const PointSchema = z.object({ x: z.number(), y: z.number() })
export const SizeSchema = z.object({ width: z.number().nonnegative(), height: z.number().nonnegative() })
export const RectSchema = z.object({
  x: z.number(),
  y: z.number(),
  width: z.number().nonnegative(),
  height: z.number().nonnegative(),
})
