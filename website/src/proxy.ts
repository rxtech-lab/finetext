import { NextRequest, NextResponse } from "next/server";
import { isLocale, localeCookie, preferredLocale } from "@/lib/locales";

export function proxy(request: NextRequest) {
  const { pathname } = request.nextUrl;
  if (isLocale(pathname.split("/")[1])) return NextResponse.next();
  // Only the entry URL negotiates language; unknown paths remain genuine 404s.
  if (pathname !== "/") return NextResponse.next();
  const locale = preferredLocale(request.cookies.get(localeCookie)?.value, request.headers.get("accept-language"));
  const url = request.nextUrl.clone();
  url.pathname = `/${locale}`;
  const response = NextResponse.redirect(url);
  response.headers.set("Vary", "Accept-Language, Cookie");
  response.headers.set("Cache-Control", "private, no-store");
  return response;
}
export const config = { matcher: ["/", "/((?!api|_next|.*\\..*).*)"] };
