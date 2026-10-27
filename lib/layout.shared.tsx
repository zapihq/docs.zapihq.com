import type { BaseLayoutProps } from "fumadocs-ui/layouts/shared";
import { appName, gitConfig } from "./shared";
import { ThemeSwitch } from "@/components/theme-switch";
import Image from "next/image";

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
      { text: "Quickstart", url: "/docs/quickstart" },
      { text: "API reference", url: "/docs/api-reference" },
      { text: "Webhooks", url: "/docs/webhooks" },
    ],
    slots: {
      themeSwitch: ThemeSwitch,
    },
  };
}
