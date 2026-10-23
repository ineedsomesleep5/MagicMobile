import "@fontsource/cormorant-sc/700.css";
import "@fontsource-variable/source-serif-4";
import "./ui/styles.css";
import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import { App } from "./ui/App";

createRoot(document.getElementById("root")!).render(<StrictMode><App /></StrictMode>);
