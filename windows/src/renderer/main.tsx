import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import './styles.css'
import { App } from './screens/Shell'
import { CommandBar, ConsentPanel, Glow, Pill } from './surfaces/Surfaces'

// One bundle, several windows: the main window and the floating surfaces.
const surface = new URLSearchParams(location.search).get('surface') ?? 'main'
if (surface !== 'main') document.body.classList.add('transparent')

const view = {
  main: <App />,
  commandbar: <CommandBar />,
  consent: <ConsentPanel />,
  glow: <Glow />,
  pill: <Pill />,
}[surface] ?? <App />

createRoot(document.getElementById('root')!).render(<StrictMode>{view}</StrictMode>)
