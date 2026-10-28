import type { BaseLayoutProps } from "fumadocs-ui/layouts/shared";
import type * as PageTree from "fumadocs-core/page-tree";
import { appName, gitConfig } from "./shared";
import { getDocsPageTree } from "./source";
import { ThemeSwitch } from "@/components/theme-switch";
import { DocsMenu, type DocsMenuGroup } from "@/components/docs-menu";
import { ChevronDown } from "lucide-react";
import Image from "next/image";

const DEFAULT_GROUP = "Documentation";

function firstPageUrl(folder: PageTree.Folder): string | undefined {
  for (const node of folder.children) {
    if (node.type === "page") return node.url;
    if (node.type === "folder") {
      const url = firstPageUrl(node);
      if (url) return url;
    }
  }
}

// The menu shows the same tree as the sidebar: root separators start a group,
// and each root page or folder becomes one row with its own description.
// Adding a page to the root meta.json is enough; nothing here names a page.
function getDocsMenuGroups(): DocsMenuGroup[] {
  const groups: DocsMenuGroup[] = [];
  let group: DocsMenuGroup = { name: DEFAULT_GROUP, items: [] };

  const flush = () => {
    if (group.items.length > 0) groups.push(group);
  };

  for (const node of getDocsPageTree({ keepFolderIndex: true }).children) {
    if (node.type === "separator") {
      flush();
      group = { name: node.name ?? DEFAULT_GROUP, items: [] };
      continue;
    }

    const url =
      node.type === "page" ? node.url : (node.index?.url ?? firstPageUrl(node));
    if (!url) continue;

    group.items.push({
      name: node.name ?? url,
      url,
      description: node.description,
    });
  }

  flush();
  return groups;
}

export function baseOptions(): BaseLayoutProps {
  return {
    nav: {
      title: (
        <Image
          src="/logo.svg"
          alt={appName}
          width={30}
          height={20}
          className="h-8 w-auto"
        />
      ),
    },
    githubUrl: `https://github.com/${gitConfig.user}/${gitConfig.repo}`,
    links: [
      {
        type: "menu",
        text: (
          <span className="inline-flex items-center gap-1">
            Documentation
            <ChevronDown
              className="docs-trigger-icon opacity-70 transition-transform duration-240 ease-[cubic-bezier(0.16,1,0.3,1)] motion-reduce:transition-none max-[639px]:hidden"
              aria-hidden
            />
          </span>
        ),
        items: [
          {
            type: "custom",
            children: <DocsMenu groups={getDocsMenuGroups()} />,
          },
        ],
      },
      { text: "Changelog", url: "/changelog" },
    ],
    slots: {
      themeSwitch: ThemeSwitch,
    },
  };
}
