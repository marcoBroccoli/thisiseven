# Even admin console. Three stages: build the SPA, build the Go binary with the
# SPA embedded, run it on distroless nonroot (no shell, no package manager, no
# root — same posture as evend).
#
# Build context is admin/ :  docker build -t even-admin admin/

# --- 1. the SPA ---------------------------------------------------------------
FROM node:22-alpine AS web
WORKDIR /web
COPY web/package.json web/package-lock.json* ./
# `npm ci` when there is a lockfile, `npm install` on a first build without one.
RUN if [ -f package-lock.json ]; then npm ci --no-audit --no-fund; \
    else npm install --no-audit --no-fund; fi
COPY web/ ./
# vite.config.ts writes to ../server/internal/web/dist, which does not exist in
# this stage — build to a local dist and let the next stage place it.
RUN npx vite build --outDir dist --emptyOutDir

# --- 2. the binary ------------------------------------------------------------
FROM golang:1.24-alpine AS build
WORKDIR /src
COPY server/go.mod server/go.sum* ./
RUN go mod download
COPY server/ ./
# The placeholder dist is replaced by the real bundle before go:embed runs.
RUN rm -rf internal/web/dist
COPY --from=web /web/dist ./internal/web/dist
RUN CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags="-s -w" -o /adminsrv ./cmd/adminsrv

# --- 3. the runtime -----------------------------------------------------------
FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=build /adminsrv /adminsrv
EXPOSE 3025
USER nonroot:nonroot
ENTRYPOINT ["/adminsrv"]
