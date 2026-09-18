# syntax=docker/dockerfile:1

FROM golang:1.27-alpine AS build
WORKDIR /src

COPY go.mod go.sum ./
RUN go mod download

COPY . .

# Tests run in the image build, so a broken build never produces a pushable
# artifact.
RUN go vet ./... && go test ./... -count=1

# CGO_ENABLED=0 for a static binary -- distroless/static ships no libc.
# -trimpath keeps local paths out of the binary.
RUN CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags="-s -w" \
    -o /out/auth-service ./cmd/server

FROM gcr.io/distroless/static-debian12:nonroot
# Root certificates come with the base image; the service needs them to verify
# nothing outbound except Vault, whose CA is mounted separately.
COPY --from=build /out/auth-service /auth-service
USER 65532:65532
EXPOSE 8080 9090
ENTRYPOINT ["/auth-service"]
