FROM quay.io/wtsicgp/cgpbigwig:1.3.0 as builder

USER  root

# ALL tool versions used by opt-build.sh
# need to keep in sync with setup.sh

# newer gitlab versions do not work
ARG BBB2_URL="https://github.com/gt1/biobambam2/releases/download/2.0.87-release-20180301132713/biobambam2-2.0.87-release-20180301132713-x86_64-etch-linux-gnu.tar.gz"
ARG BWAMEM2_URL="https://github.com/bwa-mem2/bwa-mem2/releases/download/v2.0pre2/bwa-mem2-2.0pre2_x64-linux.tar.bz2"
ARG STADEN="https://iweb.dl.sourceforge.net/project/staden/staden/2.0.0b11/staden-2.0.0b11-2016-linux-x86_64.tar.gz"
ARG VER_BIODBHTS="3.01"
ARG VER_BWA="v0.7.17"
ARG VER_HTSLIB="1.10.2"
ARG VER_SAMTOOLS="1.10"

RUN apt-get -yq update
RUN apt-get install -yq --no-install-recommends apt-transport-https
RUN apt-get install -yq --no-install-recommends locales
RUN apt-get install -yq --no-install-recommends curl
RUN apt-get install -yq --no-install-recommends ca-certificates
RUN apt-get install -yq --no-install-recommends libperlio-gzip-perl
RUN apt-get install -yq --no-install-recommends make
RUN apt-get install -yq --no-install-recommends bzip2
RUN apt-get install -yq --no-install-recommends gcc
RUN apt-get install -yq --no-install-recommends psmisc
RUN apt-get install -yq --no-install-recommends time
RUN apt-get install -yq --no-install-recommends zlib1g-dev
RUN apt-get install -yq --no-install-recommends libbz2-dev
RUN apt-get install -yq --no-install-recommends liblzma-dev
RUN apt-get install -yq --no-install-recommends libcurl4-gnutls-dev
RUN apt-get install -yq --no-install-recommends libncurses5-dev
RUN apt-get install -yq --no-install-recommends nettle-dev
RUN apt-get install -yq --no-install-recommends libp11-kit-dev
RUN apt-get install -yq --no-install-recommends libtasn1-dev
RUN apt-get install -yq --no-install-recommends libdb-dev
RUN apt-get install -yq --no-install-recommends libgnutls28-dev
RUN apt-get install -yq --no-install-recommends xz-utils
RUN apt-get install -yq --no-install-recommends libexpat1-dev

RUN locale-gen en_US.UTF-8
RUN update-locale LANG=en_US.UTF-8

ENV OPT /opt/wtsi-cgp
ENV PATH $OPT/bin:$OPT/biobambam2/bin:$PATH
ENV PERL5LIB $OPT/lib/perl5
ENV LD_LIBRARY_PATH $OPT/lib
ENV LC_ALL en_US.UTF-8
ENV LANG en_US.UTF-8

RUN mkdir -p $OPT/bin

WORKDIR /install_tmp

ADD build/opt-build.sh build/
RUN bash build/opt-build.sh $OPT

COPY . .
RUN bash build/opt-build-local.sh $OPT

FROM  ubuntu:20.04

LABEL maintainer="cgphelp@sanger.ac.uk"\
      uk.ac.sanger.cgp="Cancer, Ageing and Somatic Mutation, Wellcome Sanger Institute" \
      version="5.0.5" \
      description="pcap-core"

ENV OPT /opt/wtsi-cgp
ENV PATH $OPT/bin:$OPT/biobambam2/bin:$OPT/scramble/bin:$PATH
ENV PATH $OPT/bin:$PATH
ENV PERL5LIB $OPT/lib/perl5
ENV LD_LIBRARY_PATH $OPT/lib:$OPT/scramble/lib
ENV LC_ALL C
ENV GPERF_FOR_BWA /usr/lib/x86_64-linux-gnu/libtcmalloc_minimal.so.4

RUN apt-get -yq update
RUN apt-get install -yq --no-install-recommends \
apt-transport-https \
locales \
curl \
ca-certificates \
libperlio-gzip-perl \
bzip2 \
psmisc \
time \
zlib1g \
liblzma5 \
libncurses5 \
p11-kit \
libcurl3-gnutls \
libcurl4 \
moreutils \
google-perftools \
unattended-upgrades && \
unattended-upgrade -d -v && \
apt-get remove -yq unattended-upgrades && \
apt-get autoremove -yq

RUN mkdir -p $OPT
COPY --from=builder $OPT $OPT

## USER CONFIGURATION
RUN adduser --disabled-password --gecos '' ubuntu && chsh -s /bin/bash && mkdir -p /home/ubuntu

USER    ubuntu
WORKDIR /home/ubuntu

CMD ["/bin/bash"]
