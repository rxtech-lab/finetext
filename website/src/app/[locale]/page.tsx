import type { Metadata } from "next";
import Image from "next/image";
import { notFound } from "next/navigation";
import { Button, Chip } from "@mui/material";
import { isLocale, locales } from "@/lib/locales";
import { messages } from "@/lib/messages";
import { getLatestRelease } from "@/lib/releases";
import { repository } from "@/lib/release-data";
import { LanguagePicker } from "@/components/language-picker";
import { Icon } from "@/components/icon";
export const revalidate = 300;
export function generateStaticParams() { return locales.map(locale => ({ locale })); }
export async function generateMetadata({ params }: { params: Promise<{ locale: string }> }): Promise<Metadata> {
  const { locale } = await params;
  if (!isLocale(locale)) return {};
  const t = messages[locale];
  const socialImage = { url: "/og-image.png", width: 1752, height: 897, alt: t.previewNote };
  return {
    metadataBase: new URL("https://fintext.app"),
    title: `FineText — ${t.title}`, description: t.description,
    icons: { icon: "/icon.svg", apple: "/icon.svg" },
    alternates: { canonical: `/${locale}`, languages: { en: "/en", "zh-CN": "/zh-CN", "zh-TW": "/zh-TW", "zh-HK": "/zh-HK", "x-default": "/" } },
    openGraph: { title: `FineText — ${t.title}`, description: t.description, locale: locale.replace("-", "_"), type: "website", url: `/${locale}`, siteName: "FineText", images: [socialImage] },
    twitter: { card: "summary_large_image", title: `FineText — ${t.title}`, description: t.description, images: [socialImage] },
  };
}
export default async function Home({ params }: { params: Promise<{ locale: string }> }) {
  const { locale } = await params;
  if (!isLocale(locale)) notFound();
  const t = messages[locale];
  const release = await getLatestRelease();
  return <>
    <a href="#main" className="skip-link">{t.skip}</a>
    <header className="header wrap">
      <a href={`/${locale}`} className="brand"><Image src="/icon.svg" alt="" width={38} height={38} priority />FineText</a>
      <nav aria-label="FineText"><a className="nav-feature" href="#features">{t.featuresLink}</a><LanguagePicker locale={locale} text={t} /></nav>
    </header>
    <main id="main">
      <section className="hero wrap">
        <div className="hero-copy">
          <p className="eyebrow"><span className="tiny-star" aria-hidden="true">✧</span>{t.eyebrow}</p>
          <h1>{t.title}</h1>
          <p className="hero-description">{t.description}</p>
          <div className="hero-actions">
            {release ? <Button href={release.downloadUrl} variant="contained" size="large" startIcon={<Icon kind="download" />}>{t.download}</Button> : <Button href={`${repository}/releases`} variant="contained" size="large" endIcon={<Icon kind="arrow" />}>{t.github}</Button>}
            {release && <a className="text-link" href={release.url}>{t.releaseNotes}<Icon kind="arrow" /></a>}
          </div>
          <p className="requirements">{t.requirements}{release && <> · {release.version} · {Math.ceil(release.size / 1024 / 1024)} MB</>}</p>
          {!release && <div className="release-status"><span className="status-dot" aria-hidden="true"/><div><strong>{t.unavailable}</strong><p>{t.unavailableDetail}</p></div></div>}
        </div>
        <figure className="preview" aria-label={t.previewNote}>
          <div className="preview-orbit" aria-hidden="true"/><span className="preview-spark" aria-hidden="true">✧</span>
          <div className="app-preview">
            <div className="preview-title"><span className="preview-brand"><Image src="/icon.svg" alt="" width={24} height={24}/>FineText</span><span aria-hidden="true">◷ &nbsp; ⚙</span></div>
            <div className="preview-content">
              <p className="draft-label">{t.original}</p><p className="draft-text">{t.draft}</p>
              <div className="preview-tabs"><span className="selected">{t.rewrite}</span><span>{t.translate}</span><span>{t.image}</span></div>
              <div className="result-card"><div className="result-label"><Icon kind="rewrite"/>{t.platform}<span aria-hidden="true">✓</span></div><p>{t.result}</p></div>
            </div>
            <div className="preview-footer"><span aria-hidden="true">✧</span>{t.ready}</div>
          </div>
          <figcaption>{t.preview}</figcaption>
        </figure>
      </section>
      <section className="features wrap" id="features">
        <p className="eyebrow">{t.sectionLabel}</p><h2>{t.sectionTitle}</h2>
        <div className="feature-grid">{t.features.map((feature, index) => <article key={feature.title} className={`feature-card feature-${index}`}>
          <span className="feature-icon"><Icon kind={(["rewrite", "translate", "image"] as const)[index]}/></span><span className="feature-number" aria-hidden="true">0{index + 1}</span>
          <h3>{feature.title}</h3><p>{feature.body}</p>
        </article>)}</div>
      </section>
      <section className="model-section wrap"><div className="model-inner"><div><p className="eyebrow">{t.modelLabel}</p><h2>{t.modelTitle}</h2><p className="model-body">{t.modelBody}</p><a href={repository} className="text-link">{t.github}<Icon kind="arrow"/></a></div><div className="model-options">{t.modelChips.map((label, i) => <Chip key={label} label={label} variant="outlined" icon={<span className="chip-dot" style={{background: ["#3f7d6e", "#6b739b", "#b4854c", "#6c8fa2"][i]}}/>}/>)}</div></div></section>
    </main>
    <footer className="footer wrap"><div><a href={`/${locale}`} className="brand"><Image src="/icon.svg" alt="" width={28} height={28}/>FineText</a><p>{t.footer}</p></div><div className="footer-links"><a href={repository}>{t.source}</a><span>© {new Date().getFullYear()} RxLab</span></div></footer>
  </>;
}
