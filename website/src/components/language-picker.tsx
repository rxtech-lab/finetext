"use client";
import { useState } from "react";
import { useRouter } from "next/navigation";
import { Button, Dialog, DialogActions, DialogContent, DialogTitle, List, ListItemButton, ListItemText } from "@mui/material";
import { localeCookie, localeNames, locales, type Locale } from "@/lib/locales";
import type { Messages } from "@/lib/messages";
export function LanguagePicker({ locale, text }: { locale: Locale; text: Messages }) {
  const [open, setOpen] = useState(false);
  const router = useRouter();
  function choose(value: Locale) {
    document.cookie = `${localeCookie}=${value}; Path=/; Max-Age=31536000; SameSite=Lax${location.protocol === "https:" ? "; Secure" : ""}`;
    setOpen(false);
    router.push(`/${value}${location.search}${location.hash}`);
  }
  return <>
    <Button color="inherit" onClick={() => setOpen(true)} aria-label={text.chooseLanguage} className="language-button">
      <span aria-hidden="true" className="language-symbol">◎</span> {localeNames[locale]} <span aria-hidden="true">⌄</span>
    </Button>
    <Dialog open={open} onClose={() => setOpen(false)} fullWidth maxWidth="xs" aria-labelledby="language-title">
      <DialogTitle id="language-title">{text.chooseLanguage}</DialogTitle>
      <DialogContent><p className="dialog-description">{text.remembered}</p><List aria-label={text.language}>
        {locales.map(value => <ListItemButton key={value} selected={value === locale} onClick={() => choose(value)} lang={value} sx={{ borderRadius: 3, mb: 1 }}>
          <ListItemText primary={localeNames[value]} />{value === locale && <span aria-hidden="true">✓</span>}
        </ListItemButton>)}
      </List></DialogContent>
      <DialogActions><Button onClick={() => setOpen(false)}>{text.close}</Button></DialogActions>
    </Dialog>
  </>;
}
