# cgp-bigwig defines environment variable OPT,
# this is reused here to install PCAP-core.
# As such there is no need to update PATH and PERL5LIB.

# Locale is also set to:
# ENV LC_ALL en_US.UTF-8
# ENV LANG en_US.UTF-8

# Finally PCAP-core these dependencies are provided:
# build-essential
# libbz2-dev
# libcurl4-gnutls-dev
# liblzma-dev
# libncurses5-dev
# libssl-dev
# nettle-dev
# wget
# zlib1g-dev
FROM cancerit/cgp-bigwig:0.4.4

# Set maintainer labels.
LABEL maintainer Keiran M. Raine <kr2@sanger.ac.uk>

# Add repo.
COPY . /code

# Install package and dependencies.
RUN \
    apt-get -yqq update --fix-missing && \
    apt-get -yqq install \
        libexpat1-dev \
        libgoogle-perftools-dev \
        lsof \
        time \
    && \
    apt-get clean

# Install package.
RUN \
    cd /code && \
    ./setup.sh $OPT && \
    cd ~ && \
    rm -rf /code

# Set volume to data as per:
# https://github.com/BD2KGenomics/cgl-docker-lib
VOLUME /data
WORKDIR /data
