import { createMDX } from 'fumadocs-mdx/next';

const withMDX = createMDX();

/** @type {import('next').NextConfig} */
const config = {
  experimental: {
    optimizePackageImports:['lucide-react']
  },
  devIndicators: false
};

export default withMDX(config);
