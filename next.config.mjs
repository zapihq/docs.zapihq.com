import { fileURLToPath } from "node:url";
import { createMDX } from "fumadocs-mdx/next";

const withMDX = createMDX();

// Pin the tracing root to this app. Without it Next infers a directory by
// walking up for lockfiles, which nests .next/standalone inside a parent path
// when the checkout lives in a worktree. The container expects server.js at
// the root of the standalone output.
const root = fileURLToPath(new URL(".", import.meta.url));

/** @type {import('next').NextConfig} */
const config = {
  output: "standalone",
  outputFileTracingRoot: root,
  // The OpenAPI YAML is read at request time by lib/openapi.ts. Ship it inside
  // the standalone output so dynamic route handlers such as /llms.txt work in
  // the runtime image, which carries no repository files.
  outputFileTracingIncludes: {
    "/**": ["./content/openapi/**/*.yaml"],
  },
  turbopack: { root },
  devIndicators: false,
  experimental: {
    optimizePackageImports: ["lucide-react"],
  },
};

export default withMDX(config);
