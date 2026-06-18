import type { MetadataRoute } from "next";
import { baseUrl } from "@/lib/metadata";
import { source } from "@/lib/source";

export const revalidate = false;

export default async function sitemap(): Promise<MetadataRoute.Sitemap> {
  const basePages: MetadataRoute.Sitemap = [
    {
      url: baseUrl.href,
      lastModified: new Date(),
      changeFrequency: "daily",
      priority: 1,
    },
  ];

  const docPages: MetadataRoute.Sitemap = source.getPages().map((page) => ({
    url: `${baseUrl.href}${page.url}`,
    lastModified: page.data.lastModified
      ? new Date(page.data.lastModified)
      : new Date(),
    changeFrequency: "weekly",
    priority: 0.7,
  }));

  return [...basePages, ...docPages];
}
