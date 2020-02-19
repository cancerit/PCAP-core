FROM quay.io/wtsicgp/cgpbigwig:1.1.0 as builder

USER  root

ARG BBB2_URL="https://gitlab.com/german.tischler/biobambam2/uploads/178774a8ece96d2201fcd0b5249884c7/biobambam2-2.0.146-release-20191030105216-x86_64-linux-gnu.tar.xz"
ARG BWAMEM2_URL="https://github.com/bwa-mem2/bwa-mem2/releases/download/v2.0pre2/bwa-mem2-2.0pre2_x64-linux.tar.bz2"
ARG STADEN="https://iweb.dl.sourceforge.net/project/staden/staden/2.0.0b11/staden-2.0.0b11-2016-linux-x86_64.tar.gz"
ARG VER_BIODBHTS="3.01"
ARG VER_BWA="v0.7.17"
ARG VER_HTSLIB="1.9"
ARG VER_SAMTOOLS="1.9"

RUN apt-get -yq update
RUN apt-get install -yq --no-install-recommends\
  apt-transport-https\
  locales\
  curl\
  ca-certificates\
  libperlio-gzip-perl\
  make\
  bzip2\
  gcc\
  psmisc\
  time\
  zlib1g-dev\
  libbz2-dev\
  liblzma-dev\
  libcurl4-gnutls-dev\
  libncurses5-dev\
  nettle-dev\
  libp11-kit-dev\
  libtasn1-dev\
  libgnutls-dev\
  libgd-dev\
  libdb-dev

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

FROM  ubuntu:16.04

LABEL maintainer="cgphelp@sanger.ac.uk"\
      uk.ac.sanger.cgp="Cancer, Ageing and Somatic Mutation, Wellcome Sanger Institute" \
      version="5.0.1" \
      description="pcap-core"

ENV OPT /opt/wtsi-cgp
ENV PATH $OPT/bin:$OPT/biobambam2/bin:$OPT/scramble/bin:$PATH
ENV PATH $OPT/bin:$PATH
ENV PERL5LIB $OPT/lib/perl5
ENV LD_LIBRARY_PATH $OPT/lib:$OPT/scramble/lib
ENV LC_ALL C

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
libcurl3 \
moreutils \
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
