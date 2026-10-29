export const dynamic = "force-dynamic";

/**
 * Stable health contract for the image, compose, and deploy checks.
 * Keep it dependency-free: no auth, no upstream calls, no caching.
 */
export function GET() {
  return Response.json(
    { status: "ok" },
    {
      status: 200,
      headers: {
        "Cache-Control": "no-store, max-age=0",
      },
    }
  );
}
