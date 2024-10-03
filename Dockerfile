FROM ubuntu:22.04 as base
WORKDIR /workdir

ARG sdk_nrf_branch=v2.7-branch
ARG toolchain_version=v2.7.0
ARG sdk_nrf_commit

ENV DEBIAN_FRONTEND=noninteractive
ENV NRFUTIL_HOME=/usr/local/share/nrfutil

SHELL [ "/bin/bash", "-euxo", "pipefail", "-c" ]

# gcc-multilib make = Host tools for native_sim build
# python 3.8 is installed by toolchain manager hence older version of libffi is required
RUN <<EOT
    apt-get -y update

    apt-get install -y software-properties-common
    apt-add-repository ppa:git-core/ppa

    apt-get -y upgrade
    apt-get -y install \
        ca-certificates \
        ccache \
        cmake \
        curl \
        tar \
        unzip \
        wget \
        zip \
        git \
        apt-transport-https \
        software-properties-common \
        ninja-build xz-utils gcc g++ gcc-multilib device-tree-compiler libncurses5 libncurses5-dev


    git config --global --add safe.directory '*'

    source /etc/os-release
    wget -q https://packages.microsoft.com/config/ubuntu/$VERSION_ID/packages-microsoft-prod.deb
    dpkg -i packages-microsoft-prod.deb
    rm packages-microsoft-prod.deb
    apt-get update
    apt-get install -y powershell

    wget -q https://developer.nordicsemi.com/.pc-tools/nrfutil/x64-linux/nrfutil
    mv nrfutil /usr/local/bin
    chmod +x /usr/local/bin/nrfutil
    nrfutil install toolchain-manager
    nrfutil toolchain-manager search
    nrfutil toolchain-manager install --ncs-version ${toolchain_version}
    echo "installed toolchains list"
    nrfutil toolchain-manager list

    rm -rf /root/ncs/downloads/*
    apt-get -y clean
    rm -rf /var/lib/apt/lists/*
EOT

# Prepare image with a ready to use build environment
SHELL ["nrfutil","toolchain-manager","launch","/bin/bash","--","-c"]
RUN <<EOT
    west init -m https://github.com/nrfconnect/sdk-nrf --mr ${sdk_nrf_branch} .
    if [[ $sdk_nrf_commit =~ "^[a-fA-F0-9]{32}$" ]]; then
        git checkout ${sdk_nrf_commit};
    fi
    west update --narrow -o=--depth=1
EOT

RUN pwshProfile="/opt/microsoft/powershell/7/profile.ps1" && \
    pwsh -c "New-Item -ItemType File -Path $pwshProfile -Force" && \
    echo "\$Env:PATH += \"/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:\"" >> $pwshProfile && \
    echo "\$Env:HOME = \"/root\"" >> $pwshProfile && \
    cat $pwshProfile

# Launch into build environment with the passed arguments
# Currently this is not supported in GitHub Actions
# See https://github.com/actions/runner/issues/1964
ENTRYPOINT [ "nrfutil", "toolchain-manager", "launch", "/bin/bash", "--", "/root/entry.sh" ]
COPY ./entry.sh /root/entry.sh

ENV LC_ALL=C.UTF-8
ENV LANG=C.UTF-8
ENV XDG_CACHE_HOME=/root/.cache