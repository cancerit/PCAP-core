# Installation

    ./setup.sh /path/to/installation

`/path/to/installation` is where you want the `bin`, `lib` folders to be created. The following tools will be installed: `PCAP-core`, `biobambam`, `bwa`, and `samtools`.

⚠️ *This distribution will only works on `*NIX` type systems.*

⚠️ **NOTE**

    bwa_aln.pl will only function when 0.6.x installed
    bwa_mem.pl will only function when 0.7.x installed
    (you will need to make this available on path manually)

# System Dependencies

**Perl:** Minimum version is `5.10.1` (tested with `5.16.3`).

<!-- we should not duplicate this info -->
* Ubuntu 16.04: see [`Dockerfile`](Dockerfile).

* Ubuntu 14.04:

        apt-get update && \
        apt-get -y install \
            build-essential \
            time \
            zlib1g-dev \
            libncurses5-dev \
            libcurl4-gnutls-dev \
            libssl-dev \
            libexpat1-dev \
            nettle-dev \
            lsof \
            libgoogle-perftools-dev \
            && \
        apt-get clean

* Amazon Linux AMI (2016.03.0 x86_64):

        yum -q -y update && \
        yum -y install \
        make glibc-devel gcc patch ncurses-devel expat-devel perl-core openssl-devel libcurl-devel gnutls-devel libtasn1-devel p11-kit-devel gmp-devel nettle-devel

    ⚠️ Should nettle-devel not exist:

        yum -q -y install autoconf ghostscript texinfo-tex
        wget https://git.lysator.liu.se/nettle/nettle/repository/archive.tar.gz?ref=nettle_3.2_release_20160128 -O nettle.tar.gz
        mkdir -p nettle
        tar --strip-components 1 -C nettle -zxf nettle.tar.gz
        cd nettle
        ./.bootstrap
        ./configure --disable-pic --disable-shared && \
        sudo make && \
        sudo make check && \
        sudo make install && \
        cd .. && \
        rm -rf nettle nettle.tar.gz
