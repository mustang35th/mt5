import createCache from "@emotion/cache";
import { CacheProvider } from "@emotion/react";
import CssBaseline from "@mui/material/CssBaseline";
import { ThemeProvider } from "@mui/material/styles";
import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import App from "./App";
import { viewerTheme } from "./theme";

const nonceMeta = document.querySelector<HTMLMetaElement>('meta[property="csp-nonce"]');
const rawNonce = nonceMeta?.nonce.trim();
const styleNonce = rawNonce && rawNonce !== "__CSP_NONCE__" ? rawNonce : undefined;
const emotionCache = createCache({
  key: "mui",
  nonce: styleNonce,
  prepend: true,
});

createRoot(document.getElementById("root")!).render(
  <StrictMode>
    <CacheProvider value={emotionCache}>
      <ThemeProvider theme={viewerTheme}>
        <CssBaseline />
        <App styleNonce={styleNonce} />
      </ThemeProvider>
    </CacheProvider>
  </StrictMode>,
);
