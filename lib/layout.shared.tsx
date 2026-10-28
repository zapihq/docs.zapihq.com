import type { BaseLayoutProps, MenuItemType } from "fumadocs-ui/layouts/shared";
import {
  BookOpen,
  Braces,
  Lightbulb,
  Rocket,
  Scale,
  Sparkles,
  Wallet,
} from "lucide-react";
import { appName, gitConfig } from "./shared";
import { ThemeSwitch } from "@/components/theme-switch";
import Image from "next/image";

const docsMenu: MenuItemType["items"] = [
  {
    type: "custom",
    children: (
      <p className="col-span-full px-3 pt-2 pb-1 text-xs font-medium text-fd-muted-foreground">
        Introduction
      </p>
    ),
  },
  {
    text: "Quickstart",
    url: "/docs/quickstart",
    icon: <Rocket />,
  },
  {
    text: "What is Zapi",
    url: "/docs/what-is-zapi",
    icon: <Sparkles />,
  },
  {
    text: "Comparisons",
    url: "/docs/comparisons",
    icon: <Scale />,
  },
  {
    type: "custom",
    children: (
      <p className="col-span-full px-3 pt-2 pb-1 text-xs font-medium text-fd-muted-foreground">
        Integrations
      </p>
    ),
  },
  {
    text: "Guides",
    url: "/docs/guides/api-keys",
    icon: <BookOpen />,
  },
  {
    text: "Concepts",
    url: "/docs/concepts/payments",
    icon: <Lightbulb />,
  },
  {
    text: "Payment methods",
    url: "/docs/payment-methods/telebirr",
    icon: <Wallet />,
  },
  {
    text: "API reference",
    url: "/docs/api-reference/payments",
    icon: <Braces />,
  },
];

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
      { type: "menu", text: "Docs", items: docsMenu },
      { text: "Changelog", url: "/changelog" },
    ],
    slots: {
      themeSwitch: ThemeSwitch,
    },
  };
}
