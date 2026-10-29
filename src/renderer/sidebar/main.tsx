import { createRoot } from 'react-dom/client'
import { SidebarApp } from './SidebarApp'

/** Mounts for both the `sidebar` and `floating-sidebar` surfaces; SidebarApp branches on currentSurface(). */
const root = document.getElementById('root')
if (!root) throw new Error('missing #root')
createRoot(root).render(<SidebarApp />)
