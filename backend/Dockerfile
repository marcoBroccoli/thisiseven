# evend — Even's backend. Multi-stage: full toolchain to build, distroless
# nonroot to run. The runtime image has no shell, no package manager, no root.
FROM golang:1.24-alpine AS build
WORKDIR /src
COPY go.mod go.sum* ./
RUN go mod download 2>/dev/null || true
COPY . .
RUN go mod tidy && CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags="-s -w" -o /evend ./cmd/evend

FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=build /evend /evend
EXPOSE 8080
USER nonroot:nonroot
ENTRYPOINT ["/evend"]
