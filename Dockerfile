## Define the basic image and Run time image enviroment#####################################
ARG BASE_IMAGE=ubuntu:24.04
ARG RUNTIME_BASE=ubuntu:24.04

##### developer stage：construct development env############################################
FROM ${BASE_IMAGE} AS developer

## setup construct parameter################################################################
ARG EPICS_TARGET_ARCH=linux-x86_64
ARG EPICS_HOST_ARCH=linux-x86_64

## set environment variable#################################################################
ENV EPICS_VERSION=7.0
ENV EPICS_TARGET_ARCH=${EPICS_TARGET_ARCH}
ENV EPICS_HOST_ARCH=${EPICS_HOST_ARCH}
ENV EPICS_ROOT=/epics
ENV EPICS_BASE=${EPICS_ROOT}/epics-base
ENV SUPPORT=${EPICS_ROOT}/support
ENV IOC=${EPICS_ROOT}/ioc
ENV PATH=/venv/bin:${EPICS_BASE}/bin/${EPICS_HOST_ARCH}:${PATH}
ENV LD_LIBRARY_PATH=${EPICS_BASE}/lib/${EPICS_HOST_ARCH}

## install the system dependence#############################
RUN apt-get update -y && apt-get upgrade -y && \
    apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    build-essential \
    busybox \
    g++ \
    gdb \
    git \
    inotify-tools \
    libevent-dev \
    libreadline-dev \
    libtirpc-dev \
    perl \
    python3-minimal \
    python3-pip \
    python3-ptrace \
    python3-venv \
    re2c \
    rsync \
    ssh-client \
    telnet \
    vim \
    libxml2-dev \
    && rm -rf /var/lib/apt/lists/*

## copy epics directory#####################################
COPY epics ${EPICS_ROOT}

## Download and Install EPICS Base##########################
RUN git clone https://github.com/epics-base/epics-base \
        --branch ${EPICS_VERSION} -q ${EPICS_BASE}
RUN cd ${EPICS_BASE}/configure/os && \
    sed -i 's/-m64//' CONFIG.Common.linux-x86_64 && \
    sed -i 's/-m64//' CONFIG_SITE.linux-x86_64.linux-x86_64
RUN cd ${EPICS_BASE} && make -j$(nproc) && make install INSTALL_LOCATION=${EPICS_BASE}

## Download and Install asyn，link to R4-44 branch and connect to libtirpc
RUN git clone https://github.com/epics-modules/asyn.git ${EPICS_ROOT}/asyn && \
    cd ${EPICS_ROOT}/asyn && \
    git checkout R4-44 && \
    echo "EPICS_BASE=${EPICS_BASE}" > configure/RELEASE.local && \
    echo "USR_CPPFLAGS += -I/usr/include/tirpc" > configure/CONFIG_SITE.local && \
    echo "SHARED_LIBRARIES=YES" >> configure/CONFIG_SITE.local && \
    echo "STATIC_BUILD=NO" >> configure/CONFIG_SITE.local && \
    echo "USR_SYS_LIBS += tirpc" >> configure/CONFIG_SITE.local && \
    make V=1 > make.log 2>&1 && \
    make install V=1 >> make.log 2>&1 || (cat make.log; exit 1)

## Download and Install motor 
RUN git clone https://github.com/epics-modules/motor.git ${EPICS_ROOT}/motor && \
    cd ${EPICS_ROOT}/motor && \
    echo "EPICS_BASE=${EPICS_BASE}" > configure/RELEASE.local && \
    echo "ASYN=${EPICS_ROOT}/asyn" >> configure/RELEASE.local && \
    rm -f configure/RELEASE && ln -s RELEASE.local configure/RELEASE && \
    make -j$(nproc) && make install

## Create Python virtual environment
RUN python3 -m venv /venv

##### runtime preparation stage: runtime files ################################################
FROM developer AS runtime_prep
RUN bash epics/scripts/move_runtime.sh /assets

##### runtime stage：environment for execution##################################################
FROM ${RUNTIME_BASE} AS runtime

ARG EPICS_TARGET_ARCH=linux-x86_64
ARG EPICS_HOST_ARCH=linux-x86_64

ENV EPICS_VERSION=7.0
ENV EPICS_TARGET_ARCH=${EPICS_TARGET_ARCH}
ENV EPICS_HOST_ARCH=${EPICS_HOST_ARCH}
ENV EPICS_ROOT=/epics
ENV EPICS_BASE=${EPICS_ROOT}/epics-base
ENV SUPPORT=${EPICS_ROOT}/support
ENV IOC=${EPICS_ROOT}/ioc
ENV PATH=/venv/bin:${EPICS_BASE}/bin/${EPICS_HOST_ARCH}:${PATH}
ENV LD_LIBRARY_PATH=${EPICS_BASE}/lib/${EPICS_HOST_ARCH}

COPY --from=runtime_prep /assets /

RUN apt-get update -y && apt-get upgrade -y && \
    apt-get install -y --no-install-recommends \
    libevent-dev \
    libpython3-stdlib \
    libreadline8 \
    libtirpc3 \
    python3-minimal \
    telnet \
    && rm -rf /var/lib/apt/lists/*
