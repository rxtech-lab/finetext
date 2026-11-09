export function Icon({ kind, className }: { kind: "download" | "arrow" | "rewrite" | "translate" | "image"; className?: string }) {
  const paths = {
    download: <><path d="M12 3v12m-5-5 5 5 5-5"/><path d="M4 16v5h16v-5"/></>,
    arrow: <><path d="M5 12h14m-6-6 6 6-6 6"/></>,
    rewrite: <><path d="m5 19 3-1 11-11-3-3L5 15v4Z"/><path d="m14 6 3 3M5 5v4M3 7h4m12 7v6m-3-3h6"/></>,
    translate: <><path d="M3 5h12M9 3v2m-4 3c1 4 4 7 8 9M13 5c-1 6-4 10-10 13m11 3 4-11 4 11m-6-4h4"/></>,
    image: <><rect x="3" y="3" width="18" height="18" rx="4"/><circle cx="8" cy="8" r="1"/><path d="m3 17 6-6 4 4 3-3 5 5"/></>,
  };
  return <svg className={className} aria-hidden="true" viewBox="0 0 24 24" width="22" height="22" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round">{paths[kind]}</svg>;
}
