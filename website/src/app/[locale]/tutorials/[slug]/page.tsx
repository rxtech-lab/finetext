import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { isLocale } from "@/lib/locales";
import { tutorialUI, tutorialsFor, tutorialAppLinks } from "@/lib/tutorials";
import { TutorialHeader } from "@/components/tutorials";
import { TutorialImage } from "@/components/tutorial-image";
import dimensions from "@/lib/tutorial-images.json";
import { messages } from "@/lib/messages";
type Props = { params: Promise<{ locale: string; slug: string }> };
export async function generateMetadata({ params }: Props): Promise<Metadata> {
  const { locale, slug } = await params;
  if (!isLocale(locale)) return {};
  const guide = tutorialsFor(locale).find(item => item.slug === slug);
  if (!guide) return {};
  return { title: `${guide.title} — FineText`, description: guide.description, alternates: { canonical: `https://fintext.app/${locale}/tutorials/${slug}` } };
}
export default async function Tutorial({ params }: Props) {
  const { locale, slug } = await params;
  if (!isLocale(locale)) notFound();
  const guides = tutorialsFor(locale);
  const index = guides.findIndex(item => item.slug === slug);
  if (index < 0) notFound();
  const guide = guides[index];
  const next = guides[index + 1];
  const ui = tutorialUI(locale);
  return <><a href="#main" className="skip-link">{messages[locale].skip}</a><TutorialHeader locale={locale} />
    <main id="main" className="wrap tutorial-detail">
      <nav className="tutorial-breadcrumb" aria-label={ui.nav}><Link href={`/${locale}/tutorials`}>← {ui.all}</Link><span>{String(index + 1).padStart(2, "0")} / 05</span></nav>
      <div className="tutorial-layout">
        <aside className="tutorial-sidebar"><nav aria-label={ui.all}>{guides.map((item, i) => <Link key={item.slug} href={`/${locale}/tutorials/${item.slug}`} aria-current={item.slug === slug ? "page" : undefined}><span>0{i + 1}</span>{item.title}</Link>)}</nav></aside>
        <article>
          <header className="tutorial-title"><p className="eyebrow">{ui.label} · {guide.time}</p><h1>{guide.title}</h1><p>{guide.description}</p></header>
          <div className="tutorial-body">
            <TutorialImage image={guide.image as keyof typeof dimensions} alt={guide.alt} caption={guide.caption} enlarge={ui.enlarge} close={ui.close} />
            <section aria-label={ui.steps}><ol className="tutorial-steps">{guide.steps.map((step, i) => <li key={step.title}><span className="step-number" aria-hidden="true">{i + 1}</span><div><h2>{step.title}</h2><p>{step.openText ? <>{step.body.slice(0, step.body.indexOf(step.openText))}<a className="tutorial-open-link" href={tutorialAppLinks[guide.slug]} title={`${ui.openApp} · ${ui.appHint}`}>{step.openText}<span aria-hidden="true"> ↗</span></a>{step.body.slice(step.body.indexOf(step.openText) + step.openText.length)}</> : step.body}</p></div></li>)}</ol></section>
          </div>
          <aside className="tutorial-note"><strong>{ui.note}</strong><p>{guide.note}</p>{guide.link && <a href={guide.link.href} className="text-link" rel="noreferrer" target="_blank">{guide.link.label} ↗</a>}</aside>
          <nav className="tutorial-next" aria-label={ui.next}>{next ? <Link href={`/${locale}/tutorials/${next.slug}`}><span>{ui.next} →</span><strong>{next.title}</strong></Link> : <Link href={`/${locale}/tutorials`}>{ui.all} →</Link>}</nav>
        </article>
      </div>
    </main>
  </>;
}
