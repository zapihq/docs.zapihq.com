#!/usr/bin/env bash
set -Eeuo pipefail

rm -rf deploy-bundle
mkdir -p deploy-bundle/.next
cp -R .next/standalone/. deploy-bundle/
cp -R .next/static deploy-bundle/.next/static
mkdir -p deploy-bundle/public
cp -R public/. deploy-bundle/public/
tar -C deploy-bundle -czf "${APP_NAME}-${GITHUB_SHA}.tar.gz" .
