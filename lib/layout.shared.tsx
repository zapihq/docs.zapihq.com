import type { BaseLayoutProps, MenuItemType } from "fumadocs-ui/layouts/shared";
import type * as PageTree from "fumadocs-core/page-tree";
import { appName, gitConfig } from "./shared";
import { getDocsPageTree } from "./source";
import { ThemeSwitch } from "@/components/theme-switch";
import Image from "next/image";

function firstPageUrl(folder: PageTree.Folder): string | undefined {
  for (const node of folder.children) {
    if (node.type === "page") return node.url;
    if (node.type === "folder") {
      const url = firstPageUrl(node);
      if (url) return url;
    }
  }
}

// The menu shows the same tree as the sidebar: root separators become group
// labels, and each root page or folder becomes one link. Adding a page to the
// root meta.json is enough; nothing here names a page.
function getDocsMenu(): MenuItemType["items"] {
  const items: MenuItemType["items"] = [];

  for (const node of getDocsPageTree().children) {
    if (node.type === "separator") {
      items.push({
        type: "custom",
        children: (
          <p className="col-span-full px-3 pt-2 pb-1 text-xs font-medium text-fd-muted-foreground">
            {node.name}
          </p>
        ),
      });
      continue;
    }

    const url = node.type === "page" ? node.url : firstPageUrl(node);
    if (url) items.push({ text: node.name, url, icon: node.icon });
  }

  return items;
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
      { type: "menu", text: "Docs", items: getDocsMenu() },
      { text: "Changelog", url: "/changelog" },
    ],
    slots: {
      themeSwitch: ThemeSwitch,
    },
  };
}
