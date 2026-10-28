import Link from "next/link";
import { ArrowRight } from "lucide-react";
import type { ReactNode } from "react";

export type DocsMenuItem = {
  name: ReactNode;
  url: string;
  description?: ReactNode;
};

export type DocsMenuGroup = {
  name: ReactNode;
  items: DocsMenuItem[];
};

/**
 * The navbar's documentation menu: one column per root group, one row per
 * page, the page's own description underneath in at most two lines. No cards;
 * the panel is the container. Styles live here as utilities; global.css only
 * replaces the Fumadocs menu container around this component.
 */
export function DocsMenu({ groups }: { groups: DocsMenuGroup[] }) {
  return (
    <div
      data-docs-menu
      className="w-full px-4 py-7 text-ink max-[639px]:pt-3.5 max-[639px]:pb-4.5"
    >
      <div className="grid grid-cols-1 gap-y-4.5 min-[701px]:grid-cols-2 min-[701px]:gap-x-10 min-[1001px]:grid-cols-[minmax(0,0.85fr)_minmax(0,1.15fr)] min-[1001px]:gap-x-16">
        {groups.map((group, groupIndex) => (
          <section key={group.items[0]?.url ?? groupIndex}>
            <p className="mb-2 px-3 text-[0.8125rem] font-medium text-soft max-[639px]:mb-0.5">
              {group.name}
            </p>
            <ul className="m-0 flex list-none flex-col gap-0.5 p-0">
              {group.items.map((item, index) => (
                <li
                  key={item.url}
                  className="animate-[docs-menu-row-in_420ms_cubic-bezier(0.16,1,0.3,1)_both] motion-reduce:animate-none"
                  style={{
                    animationDelay: `${(groupIndex === 0 ? 0 : 40) + index * 35}ms`,
                  }}
                >
                  <Link
                    href={item.url}
                    data-docs-menu-item
                    className="group flex flex-col gap-0.75 rounded-[10px] px-3 pt-2.25 pb-2.5 text-inherit no-underline transition-colors hover:bg-panel-2 focus-visible:bg-panel-2 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand motion-reduce:transition-none"
                  >
                    <span className="flex items-center justify-between gap-4">
                      <span className="text-[0.9375rem] font-medium tracking-[-0.01em]">
                        {item.name}
                      </span>
                      <ArrowRight
                        className="size-3.75 shrink-0 -translate-x-1 text-brand opacity-0 transition-[opacity,transform] duration-200 ease-[cubic-bezier(0.16,1,0.3,1)] group-hover:translate-x-0 group-hover:opacity-90 group-focus-visible:translate-x-0 group-focus-visible:opacity-90 motion-reduce:transition-none max-[639px]:hidden"
                        aria-hidden
                      />
                    </span>
                    {item.description ? (
                      <span
                        className="line-clamp-2 text-[0.8125rem] leading-[1.45] text-soft text-pretty max-[639px]:hidden"
                        title={
                          typeof item.description === "string"
                            ? item.description
                            : undefined
                        }
                      >
                        {item.description}
                      </span>
                    ) : null}
                  </Link>
                </li>
              ))}
            </ul>
          </section>
        ))}
      </div>
    </div>
  );
}
