import { Space_Grotesk, Inter, Geist_Mono } from "next/font/google";
import "./globals.css";

const display = Space_Grotesk({
  subsets: ["latin"],
  display: "swap",
  weight: ["500", "600", "700"],
  variable: "--font-display",
});

const inter = Inter({
  subsets: ["latin"],
  display: "swap",
  variable: "--font-body",
});

const mono = Geist_Mono({
  subsets: ["latin"],
  display: "swap",
  variable: "--font-mono",
});

const SITE_URL = "https://liftoff.shostkevych.com";
const TITLE = "Liftoff — the terminal for the AI-agent era";
const DESCRIPTION =
  "A free, open-source macOS terminal built for engineers who run AI coding agents across many projects at once. Watch and steer Claude Code, Codex, Gemini and more — from your Mac, your phone, or any browser.";

export const metadata = {
  metadataBase: new URL(SITE_URL),
  title: {
    default: TITLE,
    template: "%s — Liftoff",
  },
  description: DESCRIPTION,
  applicationName: "Liftoff",
  keywords: [
    "AI terminal",
    "macOS terminal",
    "coding agents",
    "Claude Code",
    "Codex",
    "Gemini CLI",
    "AI agent terminal",
    "open source terminal",
    "developer tools",
    "terminal emulator",
  ],
  authors: [{ name: "Oleh Shostkevych" }],
  creator: "Oleh Shostkevych",
  alternates: {
    canonical: "/",
  },
  openGraph: {
    type: "website",
    url: SITE_URL,
    siteName: "Liftoff",
    title: TITLE,
    description: DESCRIPTION,
    images: [
      {
        url: "/og.png",
        width: 1200,
        height: 630,
        alt: "Liftoff — the terminal for the AI-agent era",
      },
    ],
  },
  twitter: {
    card: "summary_large_image",
    title: TITLE,
    description: DESCRIPTION,
    images: ["/og.png"],
  },
  robots: {
    index: true,
    follow: true,
    googleBot: {
      index: true,
      follow: true,
      "max-image-preview": "large",
      "max-snippet": -1,
    },
  },
  category: "technology",
};

export const viewport = {
  themeColor: "#0a0a0b",
  colorScheme: "dark",
};

const jsonLd = {
  "@context": "https://schema.org",
  "@type": "SoftwareApplication",
  name: "Liftoff",
  applicationCategory: "DeveloperApplication",
  operatingSystem: "macOS",
  description: DESCRIPTION,
  url: SITE_URL,
  image: `${SITE_URL}/og.png`,
  license: "https://opensource.org/licenses/MIT",
  offers: { "@type": "Offer", price: "0", priceCurrency: "USD" },
};

export default function RootLayout({ children }) {
  return (
    <html lang="en" className={`${display.variable} ${inter.variable} ${mono.variable}`}>
      <body>
        <script
          type="application/ld+json"
          dangerouslySetInnerHTML={{ __html: JSON.stringify(jsonLd) }}
        />
        {children}
      </body>
    </html>
  );
}
