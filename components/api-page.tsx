"use client";

import { createOpenAPIPage } from "fumadocs-openapi/ui";

/**
 * Renders a generated API reference page. The document travels with the page
 * props, so the reference needs no separate schema route. The playground is off
 * until a request proxy exists; the reference itself is complete.
 */
export const OpenAPIPage = createOpenAPIPage({
  playground: {
    enabled: true,
  },
});
