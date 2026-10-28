"use client";

import { createOpenAPIPage } from "fumadocs-openapi/ui";

/**
 * Renders a generated API reference page. The document travels with the page
 * props, so the reference needs no separate schema route. The playground sends
 * its requests from the browser to the server URL in the spec.
 */
export const OpenAPIPage = createOpenAPIPage({
  playground: {
    enabled: true,
  },
});
