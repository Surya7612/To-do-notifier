import { createRoot } from "react-dom/client";
import App from "./App";

// No StrictMode — it mount/unmounts effects twice and was stopping the mic session.
createRoot(document.getElementById("root")!).render(<App />);
