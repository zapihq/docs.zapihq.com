import type { Metadata } from "next";
import { notFound } from "next/navigation";
import {
  DocsBody,
  DocsDescription,
  DocsTitle,
} from "fumadocs-ui/layouts/docs/page";
import { getMDXComponents } from "@/components/mdx";
import { changelogSource } from "@/lib/source";

export async function generateMetadata(): Promise<Metadata> {
  const page = changelogSource.getPage([]);
  if (!page) notFound();

  return {
    title: page.data.title,
    description: page.data.description,
    alternates: {
      canonical: "/changelog",
    },
    openGraph: {
      title: page.data.title,
      description: page.data.description,
    },
  };
}

export default function ChangelogPage() {
  const page = changelogSource.getPage([]);
  if (!page) notFound();

  const MDX = page.data.body;

  return (
    <main className="mx-auto w-full max-w-2xl px-4 py-14 sm:py-20">
      <DocsTitle>{page.data.title}</DocsTitle>
      <DocsDescription className="mb-8">
        {page.data.description}
      </DocsDescription>
      <DocsBody>
        <MDX components={getMDXComponents()} />
      </DocsBody>
    </main>
  );
}
