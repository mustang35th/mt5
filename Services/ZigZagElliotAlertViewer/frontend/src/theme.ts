import { createTheme } from "@mui/material/styles";

export const viewerTheme = createTheme({
  palette: {
    mode: "dark",
    primary: {
      main: "#59d8c2",
    },
    success: {
      main: "#75d59b",
    },
    warning: {
      main: "#f2c66d",
    },
    error: {
      main: "#ff7f86",
    },
    background: {
      default: "#081017",
      paper: "#0f1a22",
    },
    divider: "#263946",
    text: {
      primary: "#edf5f5",
      secondary: "#8ba0aa",
    },
  },
  typography: {
    fontFamily: '"Segoe UI", "Yu Gothic UI", Meiryo, sans-serif',
    button: {
      fontWeight: 750,
      textTransform: "none",
    },
  },
  shape: {
    borderRadius: 9,
  },
  components: {
    MuiPaginationItem: {
      styleOverrides: {
        root: {
          borderColor: "#263946",
          color: "#8ba0aa",
          fontVariantNumeric: "tabular-nums",
          "&.Mui-selected": {
            borderColor: "#59d8c2",
            color: "#edf5f5",
            backgroundColor: "rgba(89, 216, 194, 0.12)",
          },
        },
      },
    },
  },
});
