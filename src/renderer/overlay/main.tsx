import { createRoot } from 'react-dom/client'
import { OverlayApp } from './OverlayApp'

const root = document.getElementById('root')
if (!root) throw new Error('missing #root')
createRoot(root).render(<OverlayApp />)
