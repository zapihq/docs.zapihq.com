import { createMDX } from "fumadocs-mdx/next";

const withMDX = createMDX();

/** @type {import('next').NextConfig} */
const config = {
  output: "standalone",
  devIndicators: false,
  experimental: {
    optimizePackageImports: ["lucide-react"],
  },
  /**
   * The changelog is a docs page, but marketing advertises it at
   * `docs.zapihq.com/changelog`. This is a rewrite (the URL never changes),
   * not part of a legacy redirect map.
   */
  async rewrites() {
    return [{ source: "/changelog", destination: "/docs/changelog" }];
  },
};

export default withMDX(config);
