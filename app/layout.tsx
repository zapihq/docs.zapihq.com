import { type Metadata } from "next";
import { RootProvider } from "fumadocs-ui/provider/next";
import { Geist, Geist_Mono } from "next/font/google";

import "./global.css";
import { createMetadata } from "@/lib/metadata";

const fontSans = Geist({
  subsets: ["latin"],
  variable: "--font-sans",
});

const fontMono = Geist_Mono({
  subsets: ["latin"],
  variable: "--font-mono",
});

export const metadata: Metadata = createMetadata({
  title: {
    template: "Zapi Docs | %s",
    default: "Zapi Docs",
  },
  description:
    "The official documentation for Zapi, a financial infrastructure platform.",
});

export default function Layout({ children }: LayoutProps<"/">) {
  return (
    <html
      lang="en"
      className={`${fontSans.variable} ${fontMono.variable} font-sans antialiased`}
      suppressHydrationWarning
    >
      <body className="flex min-h-screen flex-col bg-fd-background text-fd-foreground selection:bg-brand-quiet selection:text-ink">
        <RootProvider>{children}</RootProvider>
      </body>
    </html>
  );
}
