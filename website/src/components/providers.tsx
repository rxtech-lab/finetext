"use client";
import { ThemeProvider, createTheme, CssBaseline } from "@mui/material";
import { AppRouterCacheProvider } from "@mui/material-nextjs/v16-appRouter";
const theme = createTheme({
  palette: { primary: { main: "#285c73" }, background: { default: "#fafaf6", paper: "#ffffff" }, text: { primary: "#1d333d", secondary: "#56676d" } },
  typography: { fontFamily: 'Arial, "PingFang SC", "PingFang TC", "Microsoft JhengHei", sans-serif', button: { textTransform: "none", fontWeight: 600 } },
  shape: { borderRadius: 20 },
  components: {
    MuiButton: { defaultProps: { disableElevation: true }, styleOverrides: { root: { borderRadius: 100, padding: "12px 23px" } } },
    MuiDialog: { styleOverrides: { paper: { borderRadius: 28, padding: 8 } } },
  },
});
export function Providers({ children }: { children: React.ReactNode }) {
  return <AppRouterCacheProvider><ThemeProvider theme={theme}><CssBaseline />{children}</ThemeProvider></AppRouterCacheProvider>;
}
