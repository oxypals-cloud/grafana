ARG BASE_IMAGE=ubuntu:24.04
ARG JS_IMAGE=node:20-alpine
ARG JS_PLATFORM=linux/amd64
ARG GO_IMAGE=golang:1.23.1-alpine

ARG GO_SRC=go-builder

FROM ubuntu:24.04
RUN apt update && apt -y upgrade
RUN apt -y install wget
RUN apt -y install curl
RUN apt -y install git-all
RUN apt-get update
RUN apt-get -y install make
RUN apt -y install golang-go
RUN apt -y install gcc

##COPY ./brwinst.sh brwinst.sh
#RUN chmod +x brwinst.sh
#ENV NOINTERACTIVE=1
#ENV CI=1
#RUN /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
# installs nvm (Node Version Manager)
#RUN /bin/bash -c "$(curl -fsSL curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.0/install.sh)"

#RUN curl -sS https://dl.yarnpkg.com/debian/pubkey.gpg | apt-key add -
#RUN echo "deb https://dl.yarnpkg.com/debian/ stable main" | tee /etc/apt/sources.list.d/yarn.list
#RUN apt update && apt install yarn
#RUN yarn install --immutable
#RUN yarn build

RUN git clone https://github.com/grafana/grafana
WORKDIR /grafana
RUN git checkout v11.3.1

ENV GO_BUILD_DEV=1
RUN go work use .
RUN go mod tidy
RUN make build-go
RUN make gen-jsonnet

ARG GF_UID="472"
ARG GF_GID="0"

ENV PATH="/usr/share/grafana/bin:$PATH" \
    GF_PATHS_CONFIG="/etc/grafana/grafana.ini" \
    GF_PATHS_DATA="/var/lib/grafana" \
    GF_PATHS_HOME="/usr/share/grafana" \
    GF_PATHS_LOGS="/var/log/grafana" \
    GF_PATHS_PLUGINS="/var/lib/grafana/plugins" \
    GF_PATHS_PROVISIONING="/etc/grafana/provisioning"

WORKDIR $GF_PATHS_HOME

RUN if grep -i -q alpine /etc/issue; then \
      apk add --no-cache ca-certificates bash curl tzdata musl-utils && \
      apk info -vv | sort; \
    elif grep -i -q ubuntu /etc/issue; then \
      DEBIAN_FRONTEND=noninteractive && \
      apt-get update && \
      apt-get install -y ca-certificates curl tzdata musl && \
      apt-get autoremove -y && \
      rm -rf /var/lib/apt/lists/*; \
    else \
      echo 'ERROR: Unsupported base image' && /bin/false; \
    fi

# glibc support for alpine x86_64 only
RUN if grep -i -q alpine /etc/issue && [ `arch` = "x86_64" ]; then \
      wget -q -O /etc/apk/keys/sgerrand.rsa.pub https://alpine-pkgs.sgerrand.com/sgerrand.rsa.pub && \
      wget https://github.com/sgerrand/alpine-pkg-glibc/releases/download/2.35-r0/glibc-2.35-r0.apk \
        -O /tmp/glibc-2.35-r0.apk && \
      wget https://github.com/sgerrand/alpine-pkg-glibc/releases/download/2.35-r0/glibc-bin-2.35-r0.apk \
        -O /tmp/glibc-bin-2.35-r0.apk && \
      apk add --force-overwrite --no-cache /tmp/glibc-2.35-r0.apk /tmp/glibc-bin-2.35-r0.apk && \
      rm -f /lib64/ld-linux-x86-64.so.2 && \
      ln -s /usr/glibc-compat/lib64/ld-linux-x86-64.so.2 /lib64/ld-linux-x86-64.so.2 && \
      rm -f /tmp/glibc-2.35-r0.apk && \
      rm -f /tmp/glibc-bin-2.35-r0.apk && \
      rm -f /lib/ld-linux-x86-64.so.2 && \
      rm -f /etc/ld.so.cache; \
    fi
COPY conf ./conf
RUN if [ ! $(getent group "$GF_GID") ]; then \
      if grep -i -q alpine /etc/issue; then \
        addgroup -S -g $GF_GID grafana; \
      else \
        addgroup --system --gid $GF_GID grafana; \
      fi; \
    fi && \
    GF_GID_NAME=$(getent group $GF_GID | cut -d':' -f1) && \
    mkdir -p "$GF_PATHS_HOME/.aws" && \
    if grep -i -q alpine /etc/issue; then \
      adduser -S -u $GF_UID -G "$GF_GID_NAME" grafana; \
    else \
      adduser --system --uid $GF_UID --ingroup "$GF_GID_NAME" grafana; \
    fi && \
    mkdir -p "$GF_PATHS_PROVISIONING/datasources" \
             "$GF_PATHS_PROVISIONING/dashboards" \
             "$GF_PATHS_PROVISIONING/notifiers" \
             "$GF_PATHS_PROVISIONING/plugins" \
             "$GF_PATHS_PROVISIONING/access-control" \
             "$GF_PATHS_PROVISIONING/alerting" \
             "$GF_PATHS_LOGS" \
             "$GF_PATHS_PLUGINS" \
             "$GF_PATHS_DATA" && \
    cp conf/sample.ini "$GF_PATHS_CONFIG" && \
    cp conf/ldap.toml /etc/grafana/ldap.toml && \
    chown -R "grafana:$GF_GID_NAME" "$GF_PATHS_DATA" "$GF_PATHS_HOME/.aws" "$GF_PATHS_LOGS" "$GF_PATHS_PLUGINS" "$GF_PATHS_PROVISIONING" && \
    chmod -R 777 "$GF_PATHS_DATA" "$GF_PATHS_HOME/.aws" "$GF_PATHS_LOGS" "$GF_PATHS_PLUGINS" "$GF_PATHS_PROVISIONING"

    COPY /bin/grafana* /tmp/grafana/bin/*/grafana* ./bin/

    EXPOSE 6000

    ARG RUN_SH=./packaging/docker/run.sh

    COPY ${RUN_SH} /run.sh
    
    USER "$GF_UID"
    ENTRYPOINT [ "/run.sh" ]

