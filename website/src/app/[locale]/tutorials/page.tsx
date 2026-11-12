import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { isLocale } from "@/lib/locales";
import { tutorialUI } from "@/lib/tutorials";
import { TutorialCards, TutorialHeader } from "@/components/tutorials";
import { messages } from "@/lib/messages";
export async function generateMetadata({ params }: { params: Promise<{ locale: string }> }): Promise<Metadata> {
  const { locale } = await params;
  if (!isLocale(locale)) return {};
  const ui = tutorialUI(locale);
  return { title: `${ui.nav} — FineText`, description: ui.intro, alternates: { canonical: `https://finetext.app/${locale}/tutorials` } };
}
export default async function Tutorials({ params }: { params: Promise<{ locale: string }> }) {
  const { locale } = await params;
  if (!isLocale(locale)) notFound();
  const ui = tutorialUI(locale);
  return <><a href="#main" className="skip-link">{messages[locale].skip}</a><TutorialHeader locale={locale} />
    <main id="main" className="wrap tutorial-hub">
      <Link href={`/${locale}`} className="text-link">← {ui.home}</Link>
      <div className="tutorial-intro"><p className="eyebrow">{ui.label}</p><h1>{ui.title}</h1><p>{ui.intro}</p></div>
      <TutorialCards locale={locale} />
    </main><footer className="footer wrap"><Link href={`/${locale}`} className="brand">FineText</Link><p>{messages[locale].footer}</p></footer>
  </>;
}
