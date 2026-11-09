import { notFound } from "next/navigation";
import { isLocale } from "@/lib/locales";
import { Providers } from "@/components/providers";
import "../globals.css";
export default async function LocaleLayout({ children, params }: { children: React.ReactNode; params: Promise<{locale: string}> }) {
  const { locale } = await params;
  if (!isLocale(locale)) notFound();
  return <html lang={locale} data-scroll-behavior="smooth"><body><Providers>{children}</Providers></body></html>;
}
