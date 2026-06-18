import type { Metadata } from "next";
import { appName } from "./shared";

export function createMetadata(override: Metadata): Metadata {
  return {
    ...override,
    metadataBase: baseUrl,
    openGraph: {
      title: override.title ?? undefined,
      description: override.description ?? undefined,
      url: baseUrl.href,
      images: "/og.png",
      siteName: appName,
      ...override.openGraph,
    },
    twitter: {
      card: "summary_large_image",
      title: override.title ?? undefined,
      description: override.description ?? undefined,
      images: "/og.png",
      ...override.twitter,
    },
  };
}

export const baseUrl =
  process.env.NODE_ENV === "development" || !process.env.NEXT_PUBLIC_SITE_URL
    ? new URL("http://localhost:3000")
    : new URL(process.env.NEXT_PUBLIC_SITE_URL);
