import {
  defineCollections,
  defineConfig,
  defineDocs,
} from "fumadocs-mdx/config";
import { metaSchema, pageSchema } from "fumadocs-core/source/schema";
import lastModified from "fumadocs-mdx/plugins/last-modified";
import { remarkFeedbackBlock } from "fumadocs-core/mdx-plugins/remark-feedback-block";
import { z } from "zod";

// You can customize Zod schemas for frontmatter and `meta.json` here
// see https://fumadocs.dev/docs/mdx/collections
export const docs = defineDocs({
  dir: "content/docs",
  docs: {
    // `description` is required: it is the page lede, the search result, and
    // the social card, so a page without one is a broken page. See WRITING.md.
    schema: pageSchema.extend({
      description: z.string().min(1),
    }),
    postprocess: {
      includeProcessedMarkdown: true,
    },
  },
  meta: {
    schema: metaSchema,
  },
});

// The changelog is its own surface, not a docs page: it has a different layout,
// a different URL, and no place in the docs sidebar.
export const changelog = defineCollections({
  type: "doc",
  dir: "content/changelog",
  schema: pageSchema.extend({
    description: z.string().min(1),
  }),
  postprocess: {
    includeProcessedMarkdown: true,
  },
});

export default defineConfig({
  plugins: [lastModified()],
  mdxOptions: {
    remarkPlugins: [remarkFeedbackBlock],
    remarkNpmOptions: {
      persist: {
        id: "persist-install",
      },
    },
  },
});
