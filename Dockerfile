# Node version comes from .nvmrc. Keep the two in step.
ARG NODE_VERSION=22.8.0

FROM node:${NODE_VERSION}-slim AS deps
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci

FROM node:${NODE_VERSION}-slim AS builder
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY . .

# NEXT_PUBLIC_* values are compiled into the browser bundle, so they are build
# arguments and not runtime environment variables. Changing one of these means
# rebuilding the image; setting it on the Cloud Run service does nothing.
#
# Every one carries an explicit default, deliberately. Several call sites use
# `??` (src/lib/config.ts:1, src/lib/utils/logger.ts:3), which treats an empty
# string as a real value rather than falling back - passing an unset build arg
# through would set the log level to "" and fail the build during prerender.
# The backend is the self-hosted walnut-server instance, reached through the
# load balancer that terminates TLS for it (walnut-infra loadbalancer.tf). It
# has to be the https hostname and not the load balancer's bare IP: this image
# is served over https at app.starkloupe.co, and a page on https calling http
# is blocked by the browser as mixed content.
ARG NEXT_PUBLIC_API_URL=https://api.starkloupe.co
ARG NEXT_PUBLIC_LOG_LEVEL=warn
ARG NEXT_PUBLIC_USE_TRACKING=false
ENV NEXT_PUBLIC_API_URL=${NEXT_PUBLIC_API_URL} \
    NEXT_PUBLIC_LOG_LEVEL=${NEXT_PUBLIC_LOG_LEVEL} \
    NEXT_PUBLIC_USE_TRACKING=${NEXT_PUBLIC_USE_TRACKING}

ENV NEXT_TELEMETRY_DISABLED=1
RUN npm run build

FROM node:${NODE_VERSION}-slim AS runner
WORKDIR /app

ENV NODE_ENV=production \
    NEXT_TELEMETRY_DISABLED=1 \
    PORT=8080 \
    # Next's standalone server binds to localhost unless told otherwise, which
    # would make it unreachable from outside the container.
    HOSTNAME=0.0.0.0

RUN groupadd --system --gid 1001 nodejs \
  && useradd --system --uid 1001 --gid nodejs nextjs

# output: 'standalone' does not copy .next/static - it has to come across by
# hand or the app serves no CSS and no client chunks.
#
# There is no public/ directory in this repo today. If one is ever added, it
# needs its own COPY line here or its contents will not be served.
COPY --from=builder --chown=nextjs:nodejs /app/.next/standalone ./
COPY --from=builder --chown=nextjs:nodejs /app/.next/static ./.next/static

USER nextjs
EXPOSE 8080

CMD ["node", "server.js"]
