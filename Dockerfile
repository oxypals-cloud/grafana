# [section:buildargs] ==================================================================
ARG BASE_IMAGE=ubuntu:24.04
ARG GF_UID="472"
ARG GF_GID="0"
ARG GF_NAME="grafana"
ARG GF_PORT=3000
ARG REPO_URL="https://github.com/grafana/grafana"
ARG REPO_TAG="v11.3.1"
ARG BUILD_PLATFORM="linux-amd64"

FROM ${BASE_IMAGE} AS base_env
ARG GF_NAME

# [section:environment] ===============================================================
ENV SYS_GF_ROOT="/usr/share"
ENV SYS_GF_LIB="/var/lib"
ENV SYS_GF_LOG="/var/log"

ENV GF_PATHS_CONFIG="/etc/${GF_NAME}/grafana.ini" 
ENV GF_PATHS_DATA="${SYS_GF_LIB}/${GF_NAME}" 
ENV GF_PATHS_HOME="${SYS_GF_ROOT}/${GF_NAME}" 
ENV GF_PATHS_BIN="${SYS_GF_ROOT}/${GF_NAME}/bin" 
ENV GF_PATHS_LOGS="${SYS_GF_LOG}/${GF_NAME}" 
ENV GF_PATHS_PLUGINS="${SYS_GF_LIB}/${GF_NAME}/plugins" 
ENV GF_PATHS_PROVISIONING="/etc/${GF_NAME}/provisioning"

ENV BUILD_ROOT="/usr/local"
ENV BUILD_REPO="${BUILD_ROOT}/${GF_NAME}-repo"
ENV BUILD_OUTPUT="${BUILD_REPO}/bin"
ENV BUILD_RUNSH="${BUILD_REPO}/packagaging/docker"

# [section:buildtools] ==================================================================
FROM base_env AS build_tools

RUN apt update && \ 
    apt -y upgrade && \
    apt -y install wget && \
    apt -y install curl && \
    apt -y install git-all && \
    apt -y install gcc && \
    apt -y install gcc g++ make && \
    apt-get update 

#[section:buildenv] =====================================================================
FROM build_tools AS build_env
ARG REPO_URL
ARG REPO_TAG

WORKDIR ${BUILD_ROOT}
RUN git clone ${REPO_URL} ${BUILD_REPO} && \ 
    cd ${BUILD_REPO} && \
    git checkout ${REPO_TAG}

# [section:go1.23.1] ====================================================================
FROM build_env AS go_build_env
WORKDIR ${BUILD_ROOT}

ENV GOROOT="${BUILD_ROOT}/go"
ENV PATH="${PATH}:${GOROOT}"
ENV GOPATH="${BUILD_ROOT}/go/bin"
ENV PATH="${PATH}:${GOPATH}"

RUN mkdir ${GOROOT} && mkdir ${GOPATH}
RUN mkdir ${BUILD_ROOT}/downloads && \
    cd ${BUILD_ROOT}/downloads && wget -c https://go.dev/dl/go1.23.1.linux-amd64.tar.gz && \
    tar -C ${BUILD_ROOT} -xzf go1.23.1.linux-amd64.tar.gz
RUN go version

#[section:node] ==========================================================================
FROM go_build_env AS node_build_env

RUN apt install -y ca-certificates curl gnupg && \
    mkdir -p /etc/apt/keyrings && \
    curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg

RUN apt update && \
    apt -y install npm nodejs
RUN node -v 
RUN npm -v

RUN curl -sL https://dl.yarnpkg.com/debian/pubkey.gpg | gpg --dearmor | tee /usr/share/keyrings/yarnkey.gpg >/dev/null && \
    echo "deb [signed-by=/usr/share/keyrings/yarnkey.gpg] https://dl.yarnpkg.com/debian stable main" | tee /etc/apt/sources.list.d/yarn.list && \
    apt update && apt-get install yarn -y    
RUN yarn -v

RUN apt-get update && \
    apt-get -y install build-essential python3

# [section:grafana-backend] ================================================================
FROM node_build_env AS grafana_backend_build
WORKDIR ${BUILD_REPO}

ENV GO_BUILD_DEV=1
RUN go work use . && \
    go mod tidy
RUN make build-go && \
    make gen-jsonnet

# [section:grafana-frontend] ===============================================================
FROM grafana_backend_build AS grafana_frontend_build
WORKDIR ${BUILD_REPO}

ENV NODE_OPTIONS=--max_old_space_size=8000
ENV NODE_ENV=production

RUN yarn install
RUN yarn build

# [section:grafana-host]
FROM grafana_frontend_build AS grafana_host
ARG GF_GID
ARG GF_UID
ARG BUILD_PLATFORM

WORKDIR ${GF_PATHS_HOME}

RUN DEBIAN_FRONTEND=noninteractive && \
    apt-get update && \
    apt-get install -y ca-certificates curl tzdata musl && \
    apt-get autoremove -y && \
    rm -rf /var/lib/apt/lists/*

RUN cp -r ${BUILD_REPO}/conf ./conf

RUN if [ ! $(getent group "$GF_GID") ]; then \
      addgroup --system --gid $GF_GID grafana; \
    fi && \
    GF_GID_NAME=$(getent group $GF_GID | cut -d':' -f1) && \
    mkdir -p "$GF_PATHS_HOME/.aws" && \
    adduser --system --uid $GF_UID --ingroup "$GF_GID_NAME" grafana && \
    mkdir -p "$GF_PATHS_PROVISIONING/datasources" \
           "$GF_PATHS_PROVISIONING/dashboards" \
           "$GF_PATHS_PROVISIONING/notifiers" \
           "$GF_PATHS_PROVISIONING/plugins" \
           "$GF_PATHS_PROVISIONING/access-control" \
           "$GF_PATHS_PROVISIONING/alerting" \
           "$GF_PATHS_LOGS" \
           "$GF_PATHS_PLUGINS" \
           "$GF_PATHS_DATA" \
           "$GF_PATHS_BIN" && \
    cp conf/sample.ini "$GF_PATHS_CONFIG" && \
    cp conf/ldap.toml /etc/grafana/ldap.toml && \
    chown -R "grafana:$GF_GID_NAME" "$GF_PATHS_DATA" "$GF_PATHS_HOME/.aws" "$GF_PATHS_LOGS" "$GF_PATHS_PLUGINS" "$GF_PATHS_PROVISIONING" && \
    chmod -R 777 "$GF_PATHS_DATA" "$GF_PATHS_HOME/.aws" "$GF_PATHS_LOGS" "$GF_PATHS_PLUGINS" "$GF_PATHS_PROVISIONING"

#local build output ${BUILD_OUTPUT}/*/grafana* 

RUN cp -r ${BUILD_OUTPUT}/grafana* ${GF_PATHS_BIN} && \
    cp -r ${BUILD_REPO}/public ./public && \
    cp -r ${BUILD_REPO}/LICENSE ./

# [section:entrypoint] =============================================================================
FROM grafana_host AS grafana_image
ARG GF_UID
ARG GF_PORT

WORKDIR ${GF_PATHS_HOME}

ENV PATH=$GF_PATHS_BIN:$PATH
RUN cp -r ${BUILD_REPO}/packaging/docker/run.sh ./run.sh

EXPOSE ${GF_PORT}
USER "$GF_UID"
ENTRYPOINT [ "./run.sh" ]