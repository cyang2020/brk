/**
 * New space / edit space, inside the sidebar panel. Fields: name (TID.spaceDialogName); icon picker: an emoji input
 * (TID.spaceDialogEmoji), one of NAMED_ICONS as a glyph grid (TID.spaceDialogIcon(name)), or none
 * (TID.spaceDialogIconNone); color from THEME_PRESETS, all four sets of nine at once (TID.spaceDialogColor(set, i));
 * a live preview card painted with resolveTheme(theme). Picking a color sets themeFromPrimary(color). Submit
 * (TID.spaceDialogSubmit, or Enter in the name field) -> space/new or space/update with the chosen SpaceIcon.
 * Cancel (TID.spaceDialogCancel, or Escape) -> sidebar/dialog { dialog: null }. Form values are local state until
 * submit; the panel remounts this component per dialog opening.
 */
import { useState } from 'react'
import type { ReactElement } from 'react'
import type { Hex, NamedIcon, PresetSet, SpaceIcon, SpaceTheme } from '../../shared/theme'
import { DEFAULT_THEME, NAMED_ICONS, THEME_PRESETS, resolveTheme, themeFromPrimary } from '../../shared/theme'
import { COPY } from '../../shared/copy'
import { TID } from '../../shared/testids'
import type { SpaceDialogView } from '../../shared/view'
import { dispatch } from '../common/bridge'
import { gradientStyle } from './Background'
import { Glyph, NAMED_GLYPHS, SpaceGlyph } from './icons'

export interface SpaceDialogProps {
  readonly dialog: SpaceDialogView
  /** The name field's placeholder: the derived "Space N" display title for this space (or the next one when new). */
  readonly placeholder: string
}

const PRESET_SETS = Object.keys(THEME_PRESETS) as PresetSet[]

/** The last grapheme typed, so typing a second emoji replaces the first. */
function lastGrapheme(text: string): string {
  const parts = [...new Intl.Segmenter(undefined, { granularity: 'grapheme' }).segment(text.trim())]
  return parts[parts.length - 1]?.segment ?? ''
}

const sameColor = (a: string | undefined, b: string): boolean => a?.toLowerCase() === b.toLowerCase()

export function SpaceDialog(props: SpaceDialogProps): ReactElement {
  const editing = props.dialog.kind === 'edit-space' ? props.dialog : null
  const [title, setTitle] = useState(editing?.title ?? '')
  const [icon, setIcon] = useState<SpaceIcon>(editing?.icon ?? { kind: 'none' })
  const [theme, setTheme] = useState<SpaceTheme>(editing?.theme ?? DEFAULT_THEME)
  const preview = resolveTheme(theme)
  const placeholder = props.placeholder

  const submit = (): void => {
    const name = title.trim()
    dispatch(editing ? { type: 'space/update', spaceId: editing.spaceId, title: name, icon, theme } : { type: 'space/new', title: name, icon, theme })
  }
  const cancel = (): void => dispatch({ type: 'sidebar/dialog', dialog: null })
  const pickIcon = (name: NamedIcon): void => setIcon({ kind: 'named', name })

  return (
    <form
      data-testid={TID.spaceDialog}
      className="space-dialog"
      onSubmit={(e) => {
        e.preventDefault()
        submit()
      }}
      onKeyDown={(e) => {
        if (e.key === 'Escape') cancel()
      }}
    >
      <h2 className="dialog-title">{editing ? COPY.spaceDialog.editTitle : COPY.spaceDialog.newTitle}</h2>

      <div className="dialog-preview" data-scheme={preview.scheme} style={gradientStyle(preview.gradient)}>
        <span className="dialog-preview-label">
          <SpaceGlyph icon={icon} color={preview.gradient[0] ?? '#808080'} size={18} />
          <span>{title.trim() || placeholder}</span>
        </span>
      </div>

      <label className="dialog-field">
        <span className="dialog-label">{COPY.spaceDialog.name}</span>
        <input
          data-testid={TID.spaceDialogName}
          className="dialog-input"
          value={title}
          placeholder={placeholder}
          maxLength={100}
          autoFocus
          spellCheck={false}
          onChange={(e) => setTitle(e.target.value)}
        />
      </label>

      <div className="dialog-field">
        <span className="dialog-label">{COPY.spaceDialog.icon}</span>
        <div className="icon-row">
          <input
            data-testid={TID.spaceDialogEmoji}
            className="dialog-input emoji-input"
            value={icon.kind === 'emoji' ? icon.emoji : ''}
            placeholder={COPY.spaceDialog.emojiPlaceholder}
            aria-label={COPY.spaceDialog.emojiPlaceholder}
            onChange={(e) => {
              const emoji = lastGrapheme(e.target.value)
              setIcon(emoji ? { kind: 'emoji', emoji } : { kind: 'none' })
            }}
          />
          <button
            type="button"
            data-testid={TID.spaceDialogIconNone}
            className="icon-choice"
            title={COPY.spaceDialog.noIcon}
            aria-pressed={icon.kind === 'none'}
            onClick={() => setIcon({ kind: 'none' })}
          >
            <span className="space-dot" style={{ background: preview.gradient[0] }} />
          </button>
        </div>
        <div className="icon-grid">
          {NAMED_ICONS.map((name) => (
            <button
              type="button"
              key={name}
              data-testid={TID.spaceDialogIcon(name)}
              className="icon-choice"
              title={name}
              aria-pressed={icon.kind === 'named' && icon.name === name}
              onClick={() => pickIcon(name)}
            >
              <Glyph d={NAMED_GLYPHS[name]} size={14} />
            </button>
          ))}
        </div>
      </div>

      <div className="dialog-field">
        <span className="dialog-label">{COPY.spaceDialog.color}</span>
        {PRESET_SETS.map((set) => (
          <div key={set} className="swatches">
            {THEME_PRESETS[set].map((hex: Hex, i) => (
              <button
                type="button"
                key={hex}
                data-testid={TID.spaceDialogColor(set, i)}
                className="swatch"
                style={{ background: hex }}
                title={COPY.spaceDialog.setColor(hex)}
                aria-label={COPY.spaceDialog.setColor(hex)}
                aria-pressed={sameColor(theme.colors[0], hex)}
                onClick={() => setTheme(themeFromPrimary(hex))}
              />
            ))}
          </div>
        ))}
      </div>

      <div className="dialog-actions">
        <button type="button" data-testid={TID.spaceDialogCancel} className="btn" onClick={cancel}>
          {COPY.spaceDialog.cancel}
        </button>
        <button type="submit" data-testid={TID.spaceDialogSubmit} className="btn primary">
          {editing ? COPY.spaceDialog.save : COPY.spaceDialog.create}
        </button>
      </div>
    </form>
  )
}
