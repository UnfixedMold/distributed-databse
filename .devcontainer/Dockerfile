# cspell:words devcontainers TLAPS adduser libncurses opam rebar tlapm fontconfig sandboxing
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
## Use .tool-versions-devcontainer instead of .tool-versions to avoid
## interference with files found in the original workspace.
##
RUN set -xe \
    && wget https://github.com/asdf-vm/asdf/releases/download/v0.18.0/asdf-v0.18.0-linux-arm64.tar.gz -O bin/asdf.tar.gz \
    && (cd bin && tar -xzf asdf.tar.gz && rm asdf.tar.gz)
ENV PATH="${HOME}/.asdf/shims:${PATH}"
ENV LC_ALL="C.utf8"
ENV ASDF_DEFAULT_TOOL_VERSIONS_FILENAME=".tool-versions-devcontainer"


##
## Install the Erlang/Elixir and related tools.
##
RUN set -xe \
    && asdf plugin add erlang \
    && asdf plugin add elixir \
    && asdf plugin add rebar

# Erlang 28 is not supported either by Elixir 1.18 or the Lexical,
# thus keep Erlang 27 for now.
RUN set -xe \
    && asdf set erlang 27.3.4.3 \
    && asdf set elixir 1.18.4-otp-27 \
    && asdf set rebar  3.25.1

RUN set -xe && asdf install erlang
RUN set -xe && asdf install elixir && mix local.hex --force
RUN set -xe && asdf install

##
## Install TLA+ and TLAPS.
##

USER root
RUN set -xe \
    && apt-get update \
    && apt-get install -y opam zlib1g-dev gawk time pkg-config fontconfig openjdk-21-jdk \
    && apt-get clean
USER vscode

RUN set -xe \
    && opam init --disable-sandboxing --yes --shell-setup \
    && opam switch create 5.3.0

RUN set -xe \
    && eval $(opam env --switch=5.3.0) \
    && git clone https://github.com/tlaplus/tlapm /tmp/tlapm \
    && cd /tmp/tlapm \
    && make opam-update \
    && make opam-deps \
    && make opam-deps-opt \
    && make \
    && make install \
    && cd $HOME \
    && rm -rf /tmp/tlapm
