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
    template: "%s | Zapi Docs",
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
        {/* Fumadocs highlights search matches with the CSS Custom Highlight API.
            Lightning CSS cannot parse `::highlight()`, so these two rules ship as
            a raw style tag instead of through the compiled stylesheet. */}
        <style
          href="fumadocs-search-highlight"
          precedence="default"
        >{`::highlight(fd-search) {
          color: var(--color-fd-primary);
          text-decoration: underline;
        }`}</style>
        <RootProvider>{children}</RootProvider>
      </body>
    </html>
  );
}
