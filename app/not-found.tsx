import Link from "next/link";
import { Home, ChevronRight, HelpCircle } from "lucide-react";

export default function NotFound() {
  return (
    <main className="flex min-h-[calc(100vh-80px)] flex-col items-center justify-center p-6 text-center">
      <div className="relative">
        <div className="absolute -inset-4 rounded-full bg-fd-primary/20 blur-3xl" />
        <h1 className="relative text-9xl font-black tracking-tighter text-fd-foreground/20 sm:text-[12rem]">
          404
        </h1>
      </div>

      <div className="mt-8 max-w-md">
        <h2 className="text-3xl font-bold tracking-tight text-fd-foreground sm:text-4xl">
          Page not found
        </h2>
        <p className="mt-4 text-lg text-fd-muted-foreground">
          Sorry, we couldn’t find the page you’re looking for. It might have
          been moved or deleted.
        </p>
      </div>

      <div className="mt-12 flex flex-col items-center gap-4 sm:flex-row sm:gap-6">
        <Link
          href="/"
          className="flex items-center gap-2 rounded-full bg-fd-primary px-8 py-3 text-sm font-semibold text-fd-primary-foreground shadow-lg transition-all hover:scale-105 hover:bg-fd-primary/90 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-fd-primary"
        >
          <Home className="w-4 h-4" />
          Back to Home
        </Link>
        <Link
          href="/docs"
          className="flex items-center gap-2 rounded-full border border-fd-border bg-fd-background px-8 py-3 text-sm font-semibold text-fd-foreground shadow-sm transition-all hover:bg-fd-secondary/50 group"
        >
          <HelpCircle className="w-4 h-4 text-fd-muted-foreground group-hover:text-fd-primary" />
          Visit Documentation
          <ChevronRight className="w-4 h-4 text-fd-muted-foreground group-hover:translate-x-1 transition-transform" />
        </Link>
      </div>

      <div className="mt-16 text-sm text-fd-muted-foreground">
        Need assistance?{" "}
        <a
          href="mailto:support@vitetechsolutions.com"
          className="font-semibold text-fd-primary hover:underline"
        >
          Contact Support
        </a>
      </div>
    </main>
  );
}
