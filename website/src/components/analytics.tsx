"use client";
import { useEffect } from "react";
import { usePathname } from "next/navigation";
import { logEvent } from "firebase/analytics";
import { getBrowserAnalytics } from "@/lib/firebase";

/**
 * Records Google Analytics page views. Firebase sends the initial page_view itself when Analytics starts,
 * so this only logs the App Router's client-side navigations that follow.
 */
// Module scope survives the layout remount that happens when the [locale] segment changes.
let lastTrackedPath: string | null = null;

export function PageViewTracker() {
  const pathname = usePathname();
  useEffect(() => {
    const isInitial = lastTrackedPath === null;
    if (lastTrackedPath === pathname) return;
    lastTrackedPath = pathname;
    let cancelled = false;
    getBrowserAnalytics().then((analytics) => {
      if (!analytics || cancelled || isInitial) return;
      logEvent(analytics, "page_view", {
        page_path: pathname,
        page_location: window.location.href,
        page_title: document.title,
      });
    });
    return () => { cancelled = true; };
  }, [pathname]);
  return null;
}
