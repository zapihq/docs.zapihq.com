import { changelog, docs } from "collections/server";
import { toFumadocsSource } from "fumadocs-mdx/runtime/server";
import { loader } from "fumadocs-core/source";
import type * as PageTree from "fumadocs-core/page-tree";
import { lucideIconsPlugin } from "fumadocs-core/source/lucide-icons";
import { openapi } from "./openapi";
import { docsContentRoute, docsImageRoute, docsRoute } from "./shared";

// See https://fumadocs.dev/docs/headless/source-api for more info.
// The OpenAPI pages are virtual: they come from content/openapi/*.yaml rather
// than content/docs, so the reference cannot drift from the contract.
export const source = loader(
  {
    docs: docs.toFumadocsSource(),
    openapi: await openapi.staticSource({
      baseDir: "api-reference",
      per: "tag",
      meta: false,
    }),
  },
  {
    baseUrl: docsRoute,
    plugins: [lucideIconsPlugin(), openapi.loaderPlugin()],
  }
);

// The changelog is a separate surface, not a docs page. It gets its own
// loader so it cannot leak into the docs sidebar or search tree.
export const changelogSource = loader(toFumadocsSource(changelog, []), {
  baseUrl: "/changelog",
});

/**
 * Sidebar sections are collapsible buttons, never pages, and by default they
 * carry no "Overview" child: the section's index page stays reachable at its
 * URL, but the list only shows the pages that do the work, the way Stripe and
 * Better Auth document themselves.
 *
 * Pass `keepFolderIndex` when the tree links rather than lists, such as the
 * navbar menu: there the folder's own index page is the right destination.
 */
export function getDocsPageTree({
  keepFolderIndex = false,
}: {
  keepFolderIndex?: boolean;
} = {}): PageTree.Root {
  const tree = source.getPageTree();

  return {
    ...tree,
    children: tree.children.map((node) => {
      if (node.type !== "folder" || !node.index || keepFolderIndex) return node;

      const folder: PageTree.Folder = { ...node };
      delete folder.index;

      return folder;
    }),
  };
}

export function getPageImage(page: (typeof source)["$inferPage"]) {
  const segments = [...page.slugs, "image.png"];

  return {
    segments,
    url: `${docsImageRoute}/${segments.join("/")}`,
  };
}

export function getPageMarkdownUrl(page: (typeof source)["$inferPage"]) {
  const segments = [...page.slugs, "content.md"];

  return {
    segments,
    url: `${docsContentRoute}/${segments.join("/")}`,
  };
}

export async function getLLMText(page: (typeof source)["$inferPage"]) {
  if (page.type === "openapi") {
    return `# ${page.data.title} (${page.url})

The endpoint reference for this group is generated from the OpenAPI contract in
content/openapi. See ${page.url} for the request and response fields.`;
  }

  const processed = await page.data.getText("processed");

  return `# ${page.data.title} (${page.url})

${processed}`;
}
