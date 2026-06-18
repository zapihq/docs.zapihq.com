import defaultMdxComponents from "fumadocs-ui/mdx";
import type { MDXComponents } from "mdx/types";
import { ImageZoom } from "fumadocs-ui/components/image-zoom";
import * as TabsComponents from "fumadocs-ui/components/tabs";
import { FeedbackBlock } from "./feedback/client";
import { onBlockFeedbackAction } from "@/lib/github";

export function getMDXComponents(components?: MDXComponents) {
  return {
    ...defaultMdxComponents,
    FeedbackBlock: (props) => (
      <FeedbackBlock {...props} onSendAction={onBlockFeedbackAction} />
    ),
    img: (props) => <ImageZoom {...(props as any)} />,
    ...TabsComponents,
    ...components,
  } satisfies MDXComponents;
}

export const useMDXComponents = getMDXComponents;

declare global {
  type MDXProvidedComponents = ReturnType<typeof getMDXComponents>;
}
