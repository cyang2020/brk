import { createRoot } from 'react-dom/client';
import { SIDEBAR_WIDTH } from '../../shared/layout';

function Chrome() {
  return <aside className="sidebar" data-testid="sidebar" style={{ width: SIDEBAR_WIDTH }} />;
}

createRoot(document.getElementById('root')!).render(<Chrome />);
