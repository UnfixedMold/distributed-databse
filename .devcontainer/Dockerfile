FROM mcr.microsoft.com/vscode/devcontainers/base:ubuntu-24.04

##
##  Install packages needed for the build.
##
RUN set -xe \
    && apt-get update \
    && apt-get install -y git curl wget libssl-dev libncurses-dev autoconf g++ \
    && apt-get clean

##
##  Create a non-root user.
##
# RUN set -xe && adduser --ingroup root --shell /bin/bash vscode
USER vscode
ENV HOME=/home/vscode
WORKDIR ${HOME}
RUN set -xe && mkdir -p bin
ENV PATH="${HOME}/bin:${PATH}"

##
## Setup the ASDF.
##
RUN set -xe \
    && wget https://github.com/asdf-vm/asdf/releases/download/v0.18.0/asdf-v0.18.0-linux-arm64.tar.gz -O bin/asdf.tar.gz \
    && (cd bin && tar -xzf asdf.tar.gz && rm asdf.tar.gz)
ENV PATH="${HOME}/.asdf/shims:${PATH}"
ENV LC_ALL="C.utf8"

##
## Install the stuff.
##
RUN set -xe \
    && asdf plugin add erlang \
    && asdf plugin add elixir \
    && asdf plugin add rebar

RUN set -xe \
    && asdf set erlang 28.0.2 \
    && asdf set elixir 1.18.4-otp-28 \
    && asdf set rebar  3.25.1

RUN set -xe && asdf install erlang
RUN set -xe && asdf install elixir && mix local.hex --force
RUN set -xe && asdf install
