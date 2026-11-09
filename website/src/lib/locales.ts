export const locales = ["en", "zh-CN", "zh-TW", "zh-HK"] as const;
export type Locale = (typeof locales)[number];
export const localeNames: Record<Locale, string> = {
  en: "English", "zh-CN": "简体中文", "zh-TW": "繁體中文（台灣）", "zh-HK": "繁體中文（香港）",
};
export const localeCookie = "finetext-locale";
export function isLocale(value: unknown): value is Locale {
  return typeof value === "string" && locales.includes(value as Locale);
}
function matchLanguage(language: string): Locale | undefined {
  const value = language.toLowerCase();
  if (value === "en" || value.startsWith("en-")) return "en";
  if (value === "zh-hk" || value === "zh-mo" || value.startsWith("zh-hant-hk")) return "zh-HK";
  if (value === "zh-tw" || value.startsWith("zh-hant")) return "zh-TW";
  if (value === "zh" || value.startsWith("zh-")) return "zh-CN";
}
export function preferredLocale(saved: string | undefined, acceptLanguage: string | null): Locale {
  if (isLocale(saved)) return saved;
  const languages = (acceptLanguage ?? "").split(",").map((entry, index) => {
    const [language, ...params] = entry.trim().split(";");
    const quality = params.find((param) => param.trim().startsWith("q="));
    const q = quality ? Number(quality.trim().slice(2)) : 1;
    return { language, q, index };
  }).filter(({ q }) => Number.isFinite(q) && q > 0 && q <= 1)
    .sort((a, b) => b.q - a.q || a.index - b.index);
  for (const { language } of languages) {
    const locale = matchLanguage(language);
    if (locale) return locale;
  }
  return "en";
}
