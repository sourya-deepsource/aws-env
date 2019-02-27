BINARIES = aws-env
WD ?= $(shell pwd)
NAMESPACE=sendgrid
APPNAME=aws-env

GIT_COMMIT = $(shell git rev-parse --verify HEAD)
BUILD_DATE = $(shell date -u)
VERSION = $(if $(shell cat version_wf),$(shell cat version_wf),0.0.1)
BUILD_NUMBER = $(if $(BUILDKITE_BUILD_NUMBER),$(BUILDKITE_BUILD_NUMBER),0)

GO_FILES = $(shell find . -type f -name "*.go")

all: test vet vet-hard build

.PHONY: build
build: $(BINARIES)

$(BINARIES): $(GO_FILES)
	@echo "[$@]\n\tVersion: $(VERSION)\n\tBuild Date: $(BUILD_DATE)\n\tGit Commit: $(GIT_COMMIT)"
	@go build -mod readonly -a -tags netgo \
		-ldflags '-w -X "main.version=$(VERSION)" -X "main.builtAt=$(BUILD_DATE)" -X "main.gitHash=$(GIT_COMMIT)" -extldflags -static' \
		./cmd/$@

.PHONY: build-docker
build-docker:
	@docker build -t aws-env --target build .

.PHONY: clean
clean: 
	@rm -rf $(BINARIES) .image coverage.* 

.PHONY: test
test: coverage.txt
coverage.txt: build-docker $(GO_FILES)
	@docker run --rm \
		-v $(WD):/code \
		aws-env \
		sh -c "\
		go test -v -race -coverprofile=coverage.out ./... && \
		go tool cover -html=coverage.out -o coverage.html && \
		go tool cover -func=coverage.out | tail -n1 > coverage.txt"

.PHONY: report
report: coverage.txt
ifeq ($(BUILDKITE_PULL_REQUEST),)
	@echo "Not reporting coverage, not running in BuildKite"
else ifeq ($(BUILDKITE_PULL_REQUEST),false)
	@echo "Not reporting coverage, no PR"
else
	@echo "Reporting coverage"
	@docker run \
		-e GHI_TOKEN=$(OPSBOT_GITHUB_KEY) \
		docker.sendgrid.net/sendgrid/ghi \
		comment -m "**Code coverage result**: $(shell cat coverage.txt)" $(BUILDKITE_PULL_REQUEST) -- $(BUILDKITE_ORGANIZATION_SLUG)/$(BUILDKITE_PIPELINE_SLUG)
endif

.PHONY: vet
vet: build-docker
	@docker run --rm aws-env \
		go vet -v ./...

.PHONY: vet-hard
vet-hard:
	@docker run --rm aws-env \
		gometalinter --vendor --deadline 1h ./...

.PHONY: release
release: 
ifeq ($(BUILDKITE_PULL_REQUEST),)
	@echo "Not releasing, not running in BuildKite"
else
	@docker run \
		-v $(WD):/code \
		buildkite/github-release \
		"$(VERSION)" code/build/$(BINARIES) --commit "master" \
                                      --tag "$(VERSION)" \
                                      --github-repository "$(NAMESPACE)/$(APPNAME)" \
                                      --github-access-token "$(OPSBOT_GITHUB_KEY)"
endif
