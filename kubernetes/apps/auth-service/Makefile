IMAGE ?= ghcr.io/timkrebs/auth-service
TAG   ?= v0.1.0

.PHONY: fmt vet test cover build check image push deploy logs token jwks

fmt:   ; gofmt -w .
vet:   ; go vet ./...
test:  ; go test ./... -race -count=1
cover: ; go test ./... -coverprofile=cover.out && go tool cover -func=cover.out | tail -1
build: ; CGO_ENABLED=0 go build -trimpath -o bin/auth-service ./cmd/server

check: fmt vet test

image: ; docker build -t $(IMAGE):$(TAG) .
push:  ; docker push $(IMAGE):$(TAG)

deploy: ; kubectl apply -k deploy/
logs:   ; kubectl -n auth-service logs -l app.kubernetes.io/name=auth-service -c auth-service -f --tail=100

# Smoke tests against the running service. No LoadBalancer: this is an internal
# service, so reach it through a port-forward.
#   kubectl -n auth-service port-forward svc/auth-service 8080:8080
token:
	@curl -s -X POST localhost:8080/v1/token \
	  -H 'Content-Type: application/json' \
	  -d '{"username":"dev1","password":"'"$$DEV1_PASSWORD"'"}' | python3 -m json.tool

jwks:
	@curl -s localhost:8080/.well-known/jwks.json | python3 -m json.tool
