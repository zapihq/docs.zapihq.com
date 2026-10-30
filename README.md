# .

This is a Next.js application generated with
[Create Fumadocs](https://github.com/fuma-nama/fumadocs).

Run development server:

```bash
npm run dev
# or
pnpm dev
# or
yarn dev
```

Open http://localhost:3000 with your browser to see the result.

## Run the container

The image runs the Next.js standalone server as the non-root `node` user on
port 3000. Build it from the repository root; no Node install is needed on the
host, only Docker.

```bash
docker build --build-arg NEXT_PUBLIC_SITE_URL=https://docs.zapihq.com -t zapi-docs .
docker run --rm -p 3000:3000 zapi-docs
```

`NEXT_PUBLIC_SITE_URL` is required as a build argument because it is rendered
into the output. `PORT` and `HOSTNAME` are runtime variables and default to
`3000` and `0.0.0.0`. The site starts without secrets; chat and page feedback
also need `OPENROUTER_API_KEY`, `GITHUB_APP_ID`, and `GITHUB_APP_PRIVATE_KEY` at
runtime.

CI builds the image and exercises it on every pull request with
`scripts/check-container.sh` (Docker, bash, and curl). Run the same checks
against a local image:

```bash
bash scripts/check-container.sh zapi-docs
```

## Explore

In the project, you can see:

- `lib/source.ts`: Code for content source adapter, [`loader()`](https://fumadocs.dev/docs/headless/source-api) provides the interface to access your content.
- `lib/layout.shared.tsx`: Shared options for layouts, optional but preferred to keep.

| Route                     | Description                                            |
| ------------------------- | ------------------------------------------------------ |
| `app/(home)`              | The route group for your landing page and other pages. |
| `app/docs`                | The documentation layout and pages.                    |
| `app/api/search/route.ts` | The Route Handler for search.                          |

### Fumadocs MDX

A `source.config.ts` config file has been included, you can customise different options like frontmatter schema.

Read the [Introduction](https://fumadocs.dev/docs/mdx) for further details.

## Learn More

To learn more about Next.js and Fumadocs, take a look at the following
resources:

- [Next.js Documentation](https://nextjs.org/docs) - learn about Next.js
  features and API.
- [Learn Next.js](https://nextjs.org/learn) - an interactive Next.js tutorial.
- [Fumadocs](https://fumadocs.dev) - learn about Fumadocs
