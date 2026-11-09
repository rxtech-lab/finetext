import { ImageResponse } from "next/og";
import { isLocale, locales, type Locale } from "@/lib/locales";
import { messages } from "@/lib/messages";
import { iconSvg } from "@/lib/icon-svg";

export const alt = "FineText — rewrite, translate, and create images from your Mac’s menu bar";
export const size = { width: 1200, height: 630 };
export const contentType = "image/png";

// Satori's bundled font has no CJK glyphs, so Chinese locales load a subset of Noto Sans.
const cjkFamilies: Partial<Record<Locale, string>> = { "zh-CN": "Noto+Sans+SC", "zh-TW": "Noto+Sans+TC", "zh-HK": "Noto+Sans+HK" };

async function loadFont(family: string, weight: number, text: string): Promise<ArrayBuffer | null> {
  try {
    const css = await (await fetch(`https://fonts.googleapis.com/css2?family=${family}:wght@${weight}&text=${encodeURIComponent(text)}`)).text();
    const url = css.match(/src: url\((.+?)\) format\('(?:opentype|truetype)'\)/)?.[1];
    if (!url) return null;
    const response = await fetch(url);
    return response.ok ? await response.arrayBuffer() : null;
  } catch {
    return null;
  }
}

export function generateStaticParams() {
  return locales.map(locale => ({ locale }));
}

/** Splits the headline after its first clause so each half can be lit on its own line. */
function headline(title: string): [string, string] {
  const match = title.match(/^(.+?[.。，,])\s*(.+)$/);
  return match ? [match[1], match[2]] : [title, ""];
}

export default async function Image({ params }: { params: Promise<{ locale: string }> }) {
  const requested = (await params).locale;
  const locale: Locale = isLocale(requested) ? requested : "en";
  const t = messages[locale];
  const family = cjkFamilies[locale];
  const [lead, payoff] = headline(t.title);
  const [medium, bold] = family ? await Promise.all([500, 700].map(weight => loadFont(family, weight, `FineText${t.title}${t.eyebrow}`))) : [null, null];
  const fonts = [
    ...(medium ? [{ name: "Noto", data: medium, weight: 500 as const, style: "normal" as const }] : []),
    ...(bold ? [{ name: "Noto", data: bold, weight: 700 as const, style: "normal" as const }] : []),
  ];
  const icon = `data:image/svg+xml;base64,${Buffer.from(iconSvg).toString("base64")}`;
  const latin = locale === "en";
  return new ImageResponse(
    <div style={{ width: "100%", height: "100%", display: "flex", flexDirection: "column", alignItems: "center", justifyContent: "center", position: "relative", backgroundColor: "#050b10",
      // Key light from above, cool fill from below, and a vignette to frame the shot.
      backgroundImage: "radial-gradient(circle at 50% 0%, #2f6f8a 0%, #17384b 22%, #050b1000 48%), radial-gradient(circle at 50% 100%, #1b4a3e 0%, #050b1000 34%), radial-gradient(circle at 50% 50%, #050b1000 50%, #020507 95%)", color: "#f3f6f4", ...(fonts.length ? { fontFamily: "Noto" } : {}) }}>
      {/* eslint-disable-next-line @next/next/no-img-element */}
      <img src={icon} width={92} height={92} alt="" style={{ borderRadius: 22, boxShadow: "0 0 80px #4fa3c455, 0 20px 40px #00000099" }} />
      <div style={{ display: "flex", flexDirection: "column", alignItems: "center", marginTop: 46 }}>
        <div style={{ fontSize: latin ? 78 : 70, fontWeight: 500, letterSpacing: latin ? -3 : -1, lineHeight: 1.08, color: "#c9d6d8" }}>{lead}</div>
        {payoff && <div style={{ fontSize: latin ? 78 : 70, fontWeight: 700, letterSpacing: latin ? -3 : -1, lineHeight: 1.18, backgroundImage: "linear-gradient(90deg, #ffffff 0%, #bfe6ef 45%, #8fd3b6 100%)", backgroundClip: "text", color: "transparent" }}>{payoff}</div>}
      </div>
      <div style={{ display: "flex", marginTop: 44, fontSize: 18, letterSpacing: latin ? 7 : 8, color: "#7f9aa3", fontWeight: 500 }}>{latin ? "FINETEXT" : `FineText · ${t.eyebrow}`}</div>
      {/* Letterbox bars. */}
      <div style={{ position: "absolute", left: 0, right: 0, top: 0, height: 34, background: "#000", display: "flex" }} />
      <div style={{ position: "absolute", left: 0, right: 0, bottom: 0, height: 34, background: "#000", display: "flex" }} />
    </div>,
    { ...size, ...(fonts.length ? { fonts } : {}) },
  );
}
