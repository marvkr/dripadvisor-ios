# syntax=docker/dockerfile:1.7
# Multi-stage build → small static binary on a distroless runtime.
# Build context = repo root; this Dockerfile lives in apps/backend/.

FROM golang:1.26-alpine AS build
WORKDIR /src
RUN apk add --no-cache git
COPY apps/backend/go.mod apps/backend/go.sum ./
RUN go mod download
COPY apps/backend/ ./
ARG VERSION=dev
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 \
    go build -trimpath -ldflags "-s -w -X main.version=${VERSION}" \
    -o /out/server ./cmd/server

FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=build /out/server /server
USER nonroot
EXPOSE 8080
ENTRYPOINT ["/server"]
