"use client";
import * as Primitive from "@radix-ui/react-collapsible";
import { useSyncExternalStore, type Ref } from "react";
import { cn } from "@/lib/cn";

const Collapsible = Primitive.Root;

const CollapsibleTrigger = Primitive.CollapsibleTrigger;

function useMounted(): boolean {
  return useSyncExternalStore(
    () => () => {},
    () => true,
    () => false
  );
}

function CollapsibleContent({
  children,
  ref,
  ...props
}: React.ComponentPropsWithoutRef<typeof Primitive.CollapsibleContent> & {
  ref?: Ref<HTMLDivElement>;
}) {
  const mounted = useMounted();

  return (
    <Primitive.CollapsibleContent
      ref={ref}
      {...props}
      className={cn(
        "overflow-hidden",
        mounted &&
          "data-[state=closed]:animate-fd-collapsible-up data-[state=open]:animate-fd-collapsible-down",
        props.className
      )}
    >
      {children}
    </Primitive.CollapsibleContent>
  );
}

export { Collapsible, CollapsibleTrigger, CollapsibleContent };

export type CollapsibleProps = Primitive.CollapsibleProps;
export type CollapsibleContentProps = Primitive.CollapsibleContentProps;
export type CollapsibleTriggerProps = Primitive.CollapsibleTriggerProps;
