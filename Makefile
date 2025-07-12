PWD := $(shell pwd)
GOPATH := $(shell go env GOPATH)
# Sets the build version based on the output of the following command, if we are building for a tag, that's the build else it uses the current git branch as the build
BUILD_VERSION:=$(shell git describe --exact-match --tags $(git log -n1 --pretty='%h') 2>/dev/null || git rev-parse --abbrev-ref HEAD 2>/dev/null)
BUILD_TIME:=$(shell date 2>/dev/null)
TAG ?= "minio/console:$(BUILD_VERSION)-dev"
MINIO_VERSION ?= "quay.io/minio/minio:latest"
TARGET_BUCKET ?= "target"
NODE_VERSION := $(shell cat .nvmrc)
CTR ?= docker

default: console

.PHONY: console
console:
	@echo "Building Console binary to './console'"
	@(GO111MODULE=on CGO_ENABLED=0 go build -trimpath --tags=kqueue --ldflags "-s -w" -o console ./cmd/console)

container: console
	$(CTR) build -t openmaxio-object-browser:${BUILD_VERSION} .

getdeps:
	@mkdir -p ${GOPATH}/bin
	@echo "Installing golangci-lint" && curl -sSfL https://raw.githubusercontent.com/golangci/golangci-lint/master/install.sh | sh -s -- -b $(GOPATH)/bin

verifiers: getdeps fmt lint

fmt:
	@echo "Running $@ check"
	@(env bash $(PWD)/verify-gofmt.sh)

crosscompile:
	@(env bash $(PWD)/cross-compile.sh $(arg1))

lint:
	@echo "Running $@ check"
	@GO111MODULE=on ${GOPATH}/bin/golangci-lint cache clean
	@GO111MODULE=on ${GOPATH}/bin/golangci-lint run --timeout=5m --config ./.golangci.yml

lint-fix: getdeps ## runs golangci-lint suite of linters with automatic fixes
	@echo "Running $@ check"
	@GO111MODULE=on ${GOPATH}/bin/golangci-lint run --timeout=5m --config ./.golangci.yml --fix

install: console
	@echo "Installing console binary to '$(GOPATH)/bin/console'"
	@mkdir -p $(GOPATH)/bin && cp -f $(PWD)/console $(GOPATH)/bin/console
	@echo "Installation successful. To learn more, try \"console --help\"."

swagger-gen: clean-swagger swagger-console apply-gofmt
	@echo "Done Generating swagger server code from yaml"

apply-gofmt:
	@echo "Applying gofmt to all generated an existing files"
	@GO111MODULE=on gofmt -w .

clean-swagger:
	@echo "cleaning"
	@rm -rf models
	@rm -rf api/operations

swagger-console:
	@echo "Generating swagger server code from yaml"
	@swagger generate server -A console --main-package=management --server-package=api --exclude-main -P models.Principal -f ./swagger.yml -r NOTICE
	@echo "Generating typescript api"
	@npx swagger-typescript-api -p ./swagger.yml -o ./web-app/src/api -n consoleApi.ts --custom-config generator.config.js
	@git restore api/server.go


assets:
	@(if [ -f "${NVM_DIR}/nvm.sh" ]; then \. "${NVM_DIR}/nvm.sh"; nvm install; nvm use; npm install -g yarn ; fi &&\
	  cd web-app; corepack enable; yarn install; make build-static; yarn prettier --write . --log-level warn; cd ..)

test-integration:
	@($(CTR) stop pgsqlcontainer || true)
	@($(CTR) stop minio || true)
	@($(CTR) stop minio2 || true)
	@($(CTR) network rm mynet123 || true)
	@echo "create container network to communicate containers MinIO & PostgreSQL"
	@($(CTR) network create --subnet=173.18.0.0/29 mynet123)
	@echo "Container run with MinIO Version below:"
	@echo $(MINIO_VERSION)
	@echo "MinIO 1"
	@($(CTR) run -v /data1 -v /data2 -v /data3 -v /data4 --net=mynet123 -d --name minio --rm -p 9000:9000 -p 9091:9091 -e MINIO_KMS_SECRET_KEY=my-minio-key:OSMM+vkKUTCvQs9YL/CVMIMt43HFhkUpqJxTmGl6rYw= $(MINIO_VERSION) server /data{1...4} --console-address ':9091' && sleep 5)
	@echo "MinIO 2"
	@($(CTR) run -v /data1 -v /data2 -v /data3 -v /data4 --net=mynet123 -d --name minio2 --rm -p 9001:9001 -p 9092:9092 -e MINIO_KMS_SECRET_KEY=my-minio-key:OSMM+vkKUTCvQs9YL/CVMIMt43HFhkUpqJxTmGl6rYw= $(MINIO_VERSION) server /data{1...4} --address ':9001' --console-address ':9092' && sleep 5)
	@echo "Postgres"
	@($(CTR) run --net=mynet123 --ip=173.18.0.4 --name pgsqlcontainer --rm -p 5432:5432 -e POSTGRES_PASSWORD=password -d postgres && sleep 5)
	@echo "execute test and get coverage for test-integration:"
	@(cd integration && go test -coverpkg=../api -c -tags testrunmain . && mkdir -p coverage &&  ./integration.test -test.v -test.run "^Test*" -test.coverprofile=coverage/system.out)
	@($(CTR) stop pgsqlcontainer)
	@($(CTR) stop minio)
	@($(CTR) stop minio2)
	@($(CTR) network rm mynet123)

test-replication:
	@($(CTR) stop minio || true)
	@($(CTR) stop minio1 || true)
	@($(CTR) stop minio2 || true)
	@($(CTR) network rm mynet123 || true)
	@($(CTR) network create mynet123)
	@($(CTR) run -v /data1 -v /data2 -v /data3 -v /data4 \
	  --net=mynet123 -d \
	  --name minio \
	  --rm \
	  -p 9000:9000 \
	  -p 6000:6000 \
	  -e MINIO_KMS_SECRET_KEY=my-minio-key:OSMM+vkKUTCvQs9YL/CVMIMt43HFhkUpqJxTmGl6rYw= \
	  -e MINIO_ROOT_USER="minioadmin" \
	  -e MINIO_ROOT_PASSWORD="minioadmin" \
	  $(MINIO_VERSION) server /data{1...4} \
	  --address :9000 \
	  --console-address :6000)
	@($(CTR) run -v /data1 -v /data2 -v /data3 -v /data4 \
	  --net=mynet123 -d \
	  --name minio1 \
	  --rm \
	  -p 9001:9001 \
	  -p 6001:6001 \
	  -e MINIO_KMS_SECRET_KEY=my-minio-key:OSMM+vkKUTCvQs9YL/CVMIMt43HFhkUpqJxTmGl6rYw= \
	  -e MINIO_ROOT_USER="minioadmin" \
	  -e MINIO_ROOT_PASSWORD="minioadmin" \
	  $(MINIO_VERSION) server /data{1...4} \
	  --address :9001 \
	  --console-address :6001)
	@($(CTR) run -v /data1 -v /data2 -v /data3 -v /data4 \
	  --net=mynet123 -d \
	  --name minio2 \
	  --rm \
	  -p 9002:9002 \
	  -p 6002:6002 \
	  -e MINIO_KMS_SECRET_KEY=my-minio-key:OSMM+vkKUTCvQs9YL/CVMIMt43HFhkUpqJxTmGl6rYw= \
	  -e MINIO_ROOT_USER="minioadmin" \
	  -e MINIO_ROOT_PASSWORD="minioadmin" \
	  $(MINIO_VERSION) server /data{1...4} \
	  --address :9002 \
	  --console-address :6002)
	@(cd replication && go test -coverpkg=../api -c -tags testrunmain . && mkdir -p coverage && ./replication.test -test.v -test.run "^Test*" -test.coverprofile=coverage/replication.out)
	@($(CTR) stop minio || true)
	@($(CTR) stop minio1 || true)
	@($(CTR) stop minio2 || true)
	@($(CTR) network rm mynet123 || true)

test-sso-integration:
	@echo "create the network in bridge mode to communicate all containers"
	@($(CTR) network create my-net)
	@echo "run openldap container using MinIO Image: quay.io/minio/openldap:latest"
	@($(CTR) run \
		-e LDAP_ORGANIZATION="MinIO Inc" \
		-e LDAP_DOMAIN="min.io" \
		-e LDAP_ADMIN_PASSWORD="admin" \
		--network my-net \
		-p 389:389 \
		-p 636:636 \
		--name openldap \
		--detach quay.io/minio/openldap:latest)
	@echo "Run Dex container using MinIO Image: quay.io/minio/dex:latest"
	@($(CTR) run \
		-e DEX_ISSUER=http://dex:5556/dex \
		-e DEX_CLIENT_REDIRECT_URI=http://127.0.0.1:9090/oauth_callback \
		-e DEX_LDAP_SERVER=openldap:389 \
		--network my-net \
		-p 5556:5556 \
		--name dex \
		--detach quay.io/minio/dex:latest)
	@echo "running minio server"
	@($(CTR) run \
	-v /data1 -v /data2 -v /data3 -v /data4 \
	--network my-net \
	-d \
	--name minio \
	--rm \
	-p 9000:9000 \
	-p 9001:9001 \
	-e MINIO_IDENTITY_OPENID_CLIENT_ID="minio-client-app" \
	-e MINIO_IDENTITY_OPENID_CLIENT_SECRET="minio-client-app-secret" \
	-e MINIO_IDENTITY_OPENID_CLAIM_NAME=name \
	-e MINIO_IDENTITY_OPENID_CONFIG_URL=http://dex:5556/dex/.well-known/openid-configuration \
	-e MINIO_IDENTITY_OPENID_REDIRECT_URI=http://127.0.0.1:9090/oauth_callback \
	-e MINIO_ROOT_USER=minio \
	-e MINIO_ROOT_PASSWORD=minio123 $(MINIO_VERSION) server /data{1...4} --address :9000 --console-address :9001)
	@echo "run mc commands to set the policy"
	@($(CTR) run --name minio-client --network my-net -dit --entrypoint=/bin/sh minio/mc)
	@($(CTR) exec minio-client mc alias set myminio/ http://minio:9000 minio minio123)
	@echo "adding policy to Dillon Harper to be able to login:"
	@(cd sso-integration && $(CTR) cp allaccess.json minio-client:/ && $(CTR) exec minio-client mc admin policy create myminio "Dillon Harper" allaccess.json)
	@echo "starting bash script"
	@(env bash $(PWD)/sso-integration/set-sso.sh)
	@echo "add python module"
	@(pip3 install bs4)
	@echo "Executing the test:"
	@(cd sso-integration && go test -coverpkg=../api -c -tags testrunmain . && mkdir -p coverage && ./sso-integration.test -test.v -test.run "^Test*" -test.coverprofile=coverage/sso-system.out)

test-permissions-1:
	@($(CTR) run -v /data1 -v /data2 -v /data3 -v /data4 -d --name minio --rm -p 9000:9000 quay.io/minio/minio:latest server /data{1...4})
	@(env bash $(PWD)/web-app/tests/scripts/permissions.sh "web-app/tests/permissions-1/")
	@($(CTR) stop minio)

test-permissions-2:
	@($(CTR) run -v /data1 -v /data2 -v /data3 -v /data4 -d --name minio --rm -p 9000:9000 quay.io/minio/minio:latest server /data{1...4})
	@(env bash $(PWD)/web-app/tests/scripts/permissions.sh "web-app/tests/permissions-2/")
	@($(CTR) stop minio)

test-permissions-3:
	@($(CTR) run -v /data1 -v /data2 -v /data3 -v /data4 -d --name minio --rm -p 9000:9000 quay.io/minio/minio:latest server /data{1...4})
	@(env bash $(PWD)/web-app/tests/scripts/permissions.sh "web-app/tests/permissions-3/")
	@($(CTR) stop minio)

test-permissions-4:
	@($(CTR) run -v /data1 -v /data2 -v /data3 -v /data4 -d --name minio --rm -p 9000:9000 quay.io/minio/minio:latest server /data{1...4})
	@(env bash $(PWD)/web-app/tests/scripts/permissions.sh "web-app/tests/permissions-4/")
	@($(CTR) stop minio)

test-permissions-5:
	@($(CTR) run -v /data1 -v /data2 -v /data3 -v /data4 -d --name minio --rm -p 9000:9000 quay.io/minio/minio:latest server /data{1...4})
	@(env bash $(PWD)/web-app/tests/scripts/permissions.sh "web-app/tests/permissions-5/")
	@($(CTR) stop minio)

test-permissions-6:
	@($(CTR) run -v /data1 -v /data2 -v /data3 -v /data4 -d --name minio --rm -p 9000:9000 quay.io/minio/minio:latest server /data{1...4})
	@(env bash $(PWD)/web-app/tests/scripts/permissions.sh "web-app/tests/permissions-6/")
	@($(CTR) stop minio)

test-apply-permissions:
	@(env bash $(PWD)/web-app/tests/scripts/initialize-env.sh)

test-start-docker-minio:
	@($(CTR) run -v /data1 -v /data2 -v /data3 -v /data4 -d --name minio --rm -p 9000:9000 quay.io/minio/minio:latest server /data{1...4})

initialize-permissions: test-start-docker-minio test-apply-permissions
	@echo "Done initializing permissions test"

cleanup-permissions:
	@(env bash $(PWD)/web-app/tests/scripts/cleanup-env.sh)
	@($(CTR) stop minio)

initialize-docker-network:
	@($(CTR) network create test-network)

test-start-docker-minio-w-redirect-url: initialize-docker-network
	@($(CTR) run \
    -e MINIO_BROWSER_REDIRECT_URL='http://localhost:8000/console/subpath/' \
    -e MINIO_SERVER_URL='http://localhost:9000' \
    -v /data1 -v /data2 -v /data3 -v /data4 \
    -d --network host --name minio --rm\
    quay.io/minio/minio:latest server /data{1...4})

test-start-docker-nginx-w-subpath:
	@($(CTR) run \
	--network host \
	-d --rm \
	--add-host=host.docker.internal:host-gateway \
	-v ./web-app/tests/subpath-nginx/nginx.conf:/etc/nginx/nginx.conf \
	--name test-nginx nginx)

test-initialize-minio-nginx: test-start-docker-minio-w-redirect-url test-start-docker-nginx-w-subpath

cleanup-minio-nginx:
	@($(CTR) stop minio test-nginx & $(CTR) network rm test-network)

# https://stackoverflow.com/questions/19200235/golang-tests-in-sub-directory
# Note: go test ./... will run tests on the current folder and all subfolders.
# This is needed because tests can be in the folder or sub-folder(s), let's include them all please!.
test:
	@echo "execute test and get coverage"
	@(cd api && mkdir -p coverage && GO111MODULE=on go test ./... -test.v -coverprofile=coverage/coverage.out)


# https://stackoverflow.com/questions/19200235/golang-tests-in-sub-directory
# Note: go test ./... will run tests on the current folder and all subfolders.
# This is since tests in pkg folder are in subfolders and were not executed.
test-pkg:
	@echo "execute test and get coverage"
	@(cd pkg && mkdir -p coverage && GO111MODULE=on go test ./... -test.v -coverprofile=coverage/coverage-pkg.out)

coverage:
	@(GO111MODULE=on go test -v -coverprofile=coverage.out github.com/minio/console/api/... && go tool cover -html=coverage.out && open coverage.html)

clean:
	@echo "Cleaning up all the generated files"
	@find . -name '*.test' | xargs rm -fv
	@find . -name '*~' | xargs rm -fv
	@rm -vf console

docker:
	@$(CTR) buildx build --output=type=docker --platform linux/amd64 -t $(TAG) --build-arg build_version=$(BUILD_VERSION) --build-arg build_time='$(BUILD_TIME)' --build-arg NODE_VERSION='$(NODE_VERSION)' .

release: swagger-gen
	@echo "Generating Release: $(RELEASE)"
	@make assets
	@git add -u .
	@git add web-app/build/
