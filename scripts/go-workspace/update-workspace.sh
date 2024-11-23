#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

REPO_ROOT=$(dirname "${BASH_SOURCE[0]}")/../..

for mod in $(go run scripts/go-workspace/main.go list-submodules --path "${REPO_ROOT}/go.work"); do
    pushd "${mod}"
    echo "Running go mod tidy in ${mod}"
    go get github.com/grafana/grafana/apps/playlist/pkg/apis/playlist/v0alpha1
    go get github.com/grafana/grafana/apps/playlist/pkg/apis
    go get github.com/grafana/grafana/apps/playlist/pkg/app
    go mod tidy || true
    popd
done

pushd "${REPO_ROOT}"
    go get github.com/grafana/grafana/apps/playlist/pkg/apis/playlist/v0alpha1
    go get github.com/grafana/grafana/apps/playlist/pkg/apis
    go get github.com/grafana/grafana/apps/playlist/pkg/app

echo "running go mod download"
go mod download
echo "Running go mod tidy"
go mod tidy || true

echo "running go work sync"
go work sync
