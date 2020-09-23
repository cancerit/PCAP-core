#!/bin/bash

# ALL tool versions used by opt-build.sh
# need to keep in sync with Dockerfile

# newer gitlab versions do not work
export BBB2_URL="https://gitlab.com/german.tischler/biobambam2/uploads/178774a8ece96d2201fcd0b5249884c7/biobambam2-2.0.146-release-20191030105216-x86_64-linux-gnu.tar.xz"
export BWAMEM2_URL="https://github.com/bwa-mem2/bwa-mem2/releases/download/v2.0pre2/bwa-mem2-2.0pre2_x64-linux.tar.bz2"
export STADEN="https://iweb.dl.sourceforge.net/project/staden/staden/2.0.0b11/staden-2.0.0b11-2016-linux-x86_64.tar.gz"
export VER_BIODBHTS="3.01"
export VER_BWA="v0.7.17"
export VER_SAMTOOLS="1.11"
# only used for Bio::DB::HTS, tests fail with 1.11
export VER_HTSLIB="1.10.2"


if [[ ($# -ne 1 && $# -ne 2) ]] ; then
  echo "Please provide an installation path and optionally perl lib paths to allow, e.g."
  echo "  ./setup.sh /opt/myBundle"
  echo "OR all elements versioned:"
  echo "  ./setup.sh /opt/cgpPinel-X.X.X /opt/cgpVcf-X.X.X/lib/perl:/opt/PCAP-core-X.X.X/lib/perl"
  exit 1
fi

INST_PATH=$1

if [[ $# -eq 2 ]] ; then
  CGP_PERLLIBS=$2
fi

# get current directory
INIT_DIR=`pwd`

set -e

# cleanup inst_path
mkdir -p $INST_PATH/bin
cd $INST_PATH
INST_PATH=`pwd`
cd $INIT_DIR

# make sure that build is self contained
PERLROOT=$INST_PATH/lib/perl5

# allows user to knowingly specify other PERL5LIB areas.
if [ -z ${CGP_PERLLIBS+x} ]; then
  export PERL5LIB="$PERLROOT"
else
  export PERL5LIB="$PERLROOT:$CGP_PERLLIBS"
fi

export OPT=$INST_PATH

bash build/opt-build.sh $INST_PATH
bash build/opt-build-local.sh $INST_PATH

echo
echo
echo "Please add the following to beginning of path:"
echo "  $INST_PATH/bin"
echo "Please add the following to beginning of PERL5LIB:"
echo "  $PERLROOT"
echo

exit 0
