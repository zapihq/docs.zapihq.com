import type { MetadataRoute } from "next";
import { baseUrl } from "@/lib/metadata";
import { changelogSource, source } from "@/lib/source";

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
    url: `${baseUrl.origin}${page.url}`,
    lastModified:
      page.type !== "openapi" && page.data.lastModified
        ? new Date(page.data.lastModified)
        : new Date(),
    changeFrequency: "weekly",
    priority: 0.7,
  }));

  const changelogPages: MetadataRoute.Sitemap = changelogSource
    .getPages()
    .map((page) => ({
      url: `${baseUrl.origin}${page.url}`,
      lastModified: new Date(),
      changeFrequency: "weekly",
      priority: 0.6,
    }));

  return [...basePages, ...docPages, ...changelogPages];
}
