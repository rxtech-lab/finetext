import Image from "next/image";
import Link from "next/link";
import type { Locale } from "@/lib/locales";
import { messages } from "@/lib/messages";
import { tutorialsFor, tutorialUI } from "@/lib/tutorials";
import { LanguagePicker } from "./language-picker";
import { Icon } from "./icon";

export function TutorialHeader({ locale }: { locale: Locale }) {
  const ui = tutorialUI(locale);
  return <header className="header wrap">
    <Link href={`/${locale}`} className="brand"><Image src="/icon.svg" alt="" width={38} height={38} />FineText</Link>
    <nav aria-label="FineText"><Link href={`/${locale}/tutorials`}>{ui.nav}</Link><LanguagePicker locale={locale} text={messages[locale]} /></nav>
  </header>;
}
export function TutorialCards({ locale }: { locale: Locale }) {
  const ui = tutorialUI(locale);
  return <div className="tutorial-grid">{tutorialsFor(locale).map((guide, index) => <Link key={guide.slug} href={`/${locale}/tutorials/${guide.slug}`} className={`tutorial-card tutorial-card-${index}`}>
    <div className="tutorial-card-top"><span className="tutorial-index">0{index + 1}</span><span>{guide.time}</span></div>
    <h3>{guide.title}</h3><p>{guide.description}</p>
    <span className="text-link">{ui.open}<Icon kind="arrow" /></span>
  </Link>)}</div>;
}
