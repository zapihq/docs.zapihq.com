import { createOpenAPI } from "fumadocs-openapi/server";

/**
 * The API reference is generated from the in-repo specs. They are canonical:
 * change a field in the YAML, never in a page. See docs/adr/0001.
 */
export const openapi = createOpenAPI({
  input: ["./content/openapi/payments.yaml", "./content/openapi/payouts.yaml"],
});
