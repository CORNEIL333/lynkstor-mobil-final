import React from "react"
import ReactDOM from "react-dom/client"
import App from "./App"
import "./index.css"
import { ThemeProvider } from './ui/ThemeProvider'
import { AppErrorBoundary } from './ui/primitives'

ReactDOM.createRoot(document.getElementById("root")!).render(
  <React.StrictMode>
    <AppErrorBoundary><ThemeProvider><App /></ThemeProvider></AppErrorBoundary>
  </React.StrictMode>,
)
