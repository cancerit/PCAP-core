#!/bin/bash

set -ex

if [[ -z "${TMPDIR}" ]]; then
  TMPDIR=/tmp
fi

set -u

if [ "$#" -lt "1" ] ; then
  echo "Please provide an installation path such as /opt/ICGC"
  exit 1
fi

# get path to this script
SCRIPT_PATH=`dirname $0`;
SCRIPT_PATH=`(cd $SCRIPT_PATH && pwd)`

# get the location to install to
INST_PATH=$1
mkdir -p $1
INST_PATH=`(cd $1 && pwd)`
echo $INST_PATH

# get current directory
INIT_DIR=`pwd`

CPU=`grep -c ^processor /proc/cpuinfo`
if [ $? -eq 0 ]; then
  if [ "$CPU" -gt "6" ]; then
    CPU=6
  fi
else
  CPU=1
fi
echo "Max compilation CPUs set to $CPU"

mkdir -p $INST_PATH/bin

# make sure tools installed can see the install loc of libraries
set +u
BB_INST=$INST_PATH/biobambam2
export LD_LIBRARY_PATH=`echo $INST_PATH/lib:$LD_LIBRARY_PATH | perl -pe 's/:\$//;'`
export PATH=`echo $INST_PATH/bin:$BB_INST/bin:$PATH | perl -pe 's/:\$//;'`
export MANPATH=`echo $INST_PATH/man:$BB_INST/man:$INST_PATH/share/man:$MANPATH | perl -pe 's/:\$//;'`
export PERL5LIB=`echo $INST_PATH/lib/perl5:$PERL5LIB | perl -pe 's/:\$//;'`
set -u

##### PCAP-core installation

cpanm --no-wget --no-interactive --notest --mirror http://cpan.metacpan.org -l $INST_PATH Const::Fast
cpanm --no-wget --no-interactive --notest --mirror http://cpan.metacpan.org -l $INST_PATH File::Which

# won't build without "development" htslib structure:
## HTSLIB (tar.bz2)
rm -rf tmp_htslib
mkdir -p tmp_htslib
curl -sSL --retry 10 https://github.com/samtools/htslib/releases/download/${VER_HTSLIB}/htslib-${VER_HTSLIB}.tar.bz2 > distro.tar.bz2
tar --strip-components 1 -C tmp_htslib -jxf distro.tar.bz2
cd tmp_htslib
./configure --enable-plugins --enable-libcurl --prefix=$INST_PATH
make clean
make -j$CPU
cd ../
rm -rf distro.*

make -C c clean
export REF_CACHE=$PWD/t/data/ref_cache/%2s/%2s/%s
export REF_PATH=$REF_CACHE

env HTSLIB=$PWD/tmp_htslib make -C c -j$CPU prefix=$INST_PATH
cp bin/bam_stats $INST_PATH/bin/.
cp bin/reheadSQ $INST_PATH/bin/.
cp bin/diff_bams $INST_PATH/bin/.
cp bin/mismatchQc $INST_PATH/bin/.
cp bin/mmFlagModifier $INST_PATH/bin/.

rm -rf $REF_CACHE
rm -rf tmp_htslib

cpanm --no-wget --no-interactive --notest --mirror http://cpan.metacpan.org --notest -l $INST_PATH --installdeps .
cpanm -v --no-wget --no-interactive --mirror http://cpan.metacpan.org -l $INST_PATH .

cd $HOME
