import { getApps, initializeApp, type FirebaseApp } from "firebase/app";
import { getAnalytics, isSupported, type Analytics } from "firebase/analytics";

// Firebase web config is a public identifier, not a secret.
const firebaseConfig = {
  apiKey: "AIzaSyBPzv_ZqC07o1SkzSEDvq8lDiTD7CuGsF0",
  authDomain: "finetext-55423.firebaseapp.com",
  projectId: "finetext-55423",
  storageBucket: "finetext-55423.firebasestorage.app",
  messagingSenderId: "327491769766",
  appId: "1:327491769766:web:bb0d5f0eda52335f7e2b67",
  measurementId: "G-MK1KYD2TPB",
};

let analytics: Promise<Analytics | null> | undefined;

/** Lazily initializes Google Analytics in the browser. Resolves to null on the server or unsupported browsers. */
export function getBrowserAnalytics(): Promise<Analytics | null> {
  if (typeof window === "undefined") return Promise.resolve(null);
  analytics ??= isSupported()
    .then((supported) => {
      if (!supported) return null;
      const app: FirebaseApp = getApps()[0] ?? initializeApp(firebaseConfig);
      // Sends the initial page_view automatically; PageViewTracker logs later client-side navigations.
      return getAnalytics(app);
    })
    .catch(() => null);
  return analytics;
}
