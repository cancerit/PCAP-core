#!/bin/bash

SOURCE_BWA="https://github.com/lh3/bwa/archive/v0.7.17.tar.gz"
SOURCE_BWAMEM2="https://github.com/bwa-mem2/bwa-mem2/releases/download/v2.0pre2/bwa-mem2-2.0pre2_x64-linux.tar.bz2"

# for bamstats and Bio::DB::HTS
SOURCE_HTSLIB="https://github.com/samtools/htslib/releases/download/1.7/htslib-1.7.tar.bz2"
SOURCE_SAMTOOLS="https://github.com/samtools/samtools/releases/download/1.7/samtools-1.7.tar.bz2"

# Bio::DB::HTS
SOURCE_BIOBDHTS="https://github.com/Ensembl/Bio-HTS/archive/2.10.tar.gz"

# for biobambam
SOURCE_BBB_BIN_DIST="https://github.com/gt1/biobambam2/releases/download/2.0.86-release-20180228171821/biobambam2-2.0.86-release-20180228171821-x86_64-etch-linux-gnu.tar.gz"

get_distro () {
  EXT=""
  if [[ $2 == *.tar.bz2* ]] ; then
    EXT="tar.bz2"
  elif [[ $2 == *.zip* ]] ; then
    echo "ERROR: zip archives are not supported by default, if pulling from github replace .zip with .tar.gz"
    exit 1
  elif [[ $2 == *.tar.gz* ]] ; then
    EXT="tar.gz"
  else
    echo "I don't understand the file type for $1"
    exit 1
  fi
  rm -f $1.$EXT
  if hash curl 2>/dev/null; then
    curl --retry 10 -sS -o $1.$EXT -L $2
  else
    echo "ERROR: curl not found"
    exit 1
  fi
}

get_file () {
# output, source
  if hash curl 2>/dev/null; then
    curl -sS -o $1 -L $2
  else
    wget -nv -O $1 $2
  fi
}

if [ "$#" -ne "1" ] ; then
  echo "Please provide an installation path  such as /opt/ICGC"
  exit 0
fi

set -e

CPU=`grep -c ^processor /proc/cpuinfo`
if [ $? -eq 0 ]; then
  if [ "$CPU" -gt "6" ]; then
    CPU=6
  fi
else
  CPU=1
fi
echo "Max compilation CPUs set to $CPU"

INST_PATH=$1

# get current directory
INIT_DIR=`pwd`

# cleanup inst_path
mkdir -p $INST_PATH
cd $INST_PATH
INST_PATH=`pwd`
mkdir -p $INST_PATH/bin
cd $INIT_DIR

# make sure that build is self contained
unset PERL5LIB
ARCHNAME=`perl -e 'use Config; print $Config{archname};'`
PERLROOT=$INST_PATH/lib/perl5
export PERL5LIB="$PERLROOT"
export PATH="$INST_PATH/biobambam2/bin:$INST_PATH/bin:$PATH"

#create a location to build dependencies
SETUP_DIR=$INIT_DIR/install_tmp
mkdir -p $SETUP_DIR

# check for cgpBigWig
if [ -e "$INST_PATH/bin/detectExtremeDepth" ]; then
  echo -e "\tcgpBigWig installation found";
else
  echo -e "\tERROR: Please see README.md and install cgpBigWig";
  exit 1
fi

## grab cpanm and stick in workspace, then do a self upgrade into bin:
get_file $SETUP_DIR/cpanm https://cpanmin.us/
perl $SETUP_DIR/cpanm --no-wget -l $INST_PATH App::cpanminus
CPANM=`which cpanm`
echo $CPANM

if ! ( perl -MExtUtils::MakeMaker -e 1 >/dev/null 2>&1); then
    echo
    echo "WARNING: Your Perl installation does not seem to include a complete set of core modules.  Attempting to cope with this, but if installation fails please make sure that at least ExtUtils::MakeMaker is installed.  For most users, the best way to do this is to use your system's package manager: apt, yum, fink, homebrew, or similar."
fi

if [ -e $SETUP_DIR/basePerlDeps.success ]; then
  echo "Previously installed base perl deps..."
else
  perlmods=( "ExtUtils::CBuilder" "Module::Build~0.42" "Const::Fast" "File::Which" "LWP::UserAgent" "Bio::Root::Version~1.006924")
  for i in "${perlmods[@]}" ; do
    $CPANM --no-wget --no-interactive --notest --mirror http://cpan.metacpan.org -l $INST_PATH $i
  done
  touch $SETUP_DIR/basePerlDeps.success
fi


echo -n "Get htslib ..."
if [ -e $SETUP_DIR/htslibGet.success ]; then
  echo " already staged ...";
else
  echo
  cd $SETUP_DIR
  get_distro "htslib" $SOURCE_HTSLIB
  touch $SETUP_DIR/htslibGet.success
fi

echo -n "Building htslib ..."
if [ -e $SETUP_DIR/htslib.success ]; then
  echo " previously installed ...";
else
  echo
  mkdir -p htslib
  tar --strip-components 1 -C htslib -jxf htslib.tar.bz2
  cd htslib
  ./configure --enable-plugins --enable-libcurl --prefix=$INST_PATH
  make -j$CPU
  make install
  cd $SETUP_DIR
  touch $SETUP_DIR/htslib.success
fi

export HTSLIB=$INST_PATH

CHK=`perl -le 'eval "require $ARGV[0]" and print $ARGV[0]->VERSION' Bio::DB::HTS`
if [[ "x$CHK" == "x" ]] ; then
  echo -n "Building Bio::DB::HTS ..."
  if [ -e $SETUP_DIR/biohts.success ]; then
    echo " previously installed ...";
  else
    echo
    cd $SETUP_DIR
    rm -rf bioDbHts
    get_distro "bioDbHts" $SOURCE_BIOBDHTS
    mkdir -p bioDbHts
    tar --strip-components 1 -C bioDbHts -zxf bioDbHts.tar.gz
    cd bioDbHts
    perl Build.PL --htslib=$HTSLIB --install_base=$INST_PATH
    ./Build
    ./Build test
    ./Build install
    cd $SETUP_DIR
    rm -f bioDbHts.tar.gz
    touch $SETUP_DIR/biohts.success
  fi
else
  echo "Bio::DB::HTS already installed ..."
fi

cd $INIT_DIR

echo -n "Building samtools ..."
if [ -e $SETUP_DIR/samtools.success ]; then
  echo " previously installed ...";
else
echo
  cd $SETUP_DIR
  rm -rf samtools
  get_distro "samtools" $SOURCE_SAMTOOLS
  mkdir -p samtools
  tar --strip-components 1 -C samtools -xjf samtools.tar.bz2
  cd samtools
  ./configure --enable-plugins --enable-libcurl --prefix=$INST_PATH
  make -j$CPU all all-htslib
  make install all all-htslib
  cd $SETUP_DIR
  rm -f samtools.tar.bz2
  touch $SETUP_DIR/samtools.success
fi


cd $SETUP_DIR
echo -n "Building BWA ..."
if [ -e $SETUP_DIR/bwa.success ]; then
  echo " previously installed ..."
else
  echo
  get_distro "bwa" $SOURCE_BWA
  mkdir -p bwa
  tar --strip-components 1 -C bwa -zxf bwa.tar.gz
  make -C bwa -j$CPU
  cp bwa/bwa $INST_PATH/bin/.
  rm -f bwa.tar.gz
  touch $SETUP_DIR/bwa.success
fi

## build BWA-mem2 (tar.gz)
cd $SETUP_DIR
echo -n "Building bwa-mem2 ..."
if [ ! -e $SETUP_DIR/bwa2.success ]; then
  curl -sSL $SOURCE_BWAMEM2 > distro.tar.bz2
  rm -rf distro/*
  tar --strip-components 1 -C distro -jxf distro.tar.bz2
  cp distro/bwa-mem2* $INST_PATH/bin/.
  rm -rf distro.* distro/*
  touch $SETUP_DIR/bwa2.success
fi

echo -n "Building biobambam2 ..."
if [ -e $SETUP_DIR/biobambam2.success ]; then
  echo " previously installed ..."
else
echo
  cd $SETUP_DIR
  get_distro "biobambam2" $SOURCE_BBB_BIN_DIST
  mkdir -p $INST_PATH/biobambam2
  tar -m --strip-components 3 -C $INST_PATH/biobambam2 -zxf biobambam2.tar.gz
  rm -f $INST_PATH/biobambam2/bin/curl # don't let this file in SSL doesn't work
  rm -f biobambam2.tar.gz
  touch $SETUP_DIR/biobambam2.success
fi

cd $INIT_DIR

echo -n "Building PCAP-c ..."
if [ -e $SETUP_DIR/bam_stats.success ]; then
  echo " previously installed ...";
else
  echo
  cd $INIT_DIR
  make -C c clean
  if [ -z ${REF_PATH+x} ]; then
    export REF_CACHE=$INIT_DIR/t/data/ref_cache/%2s/%2s/%s
    export REF_PATH=$REF_CACHE
  fi
  env HTSLIB=$SETUP_DIR/htslib make -C c -j$CPU prefix=$INST_PATH
  cp bin/bam_stats $INST_PATH/bin/.
  cp bin/reheadSQ $INST_PATH/bin/.
  cp bin/diff_bams $INST_PATH/bin/.
  cp bin/mismatchQc $INST_PATH/bin/.
  cp bin/mmFlagModifier $INST_PATH/bin/.
  touch $SETUP_DIR/bam_stats.success
  make -C c clean
fi

cd $INIT_DIR

echo -n "Building PCAP_perlPrereq ..."
if [ -e $SETUP_DIR/PCAP_perlPrereq.success ]; then
  echo "PCAP_perlPrereq previously installed ...";
else
  echo
  $CPANM --no-wget --no-interactive --notest --mirror http://cpan.metacpan.org --notest -l $INST_PATH --installdeps .
  touch $SETUP_DIR/PCAP_perlPrereq.success
fi

echo -n "Installing PCAP ..."
$CPANM --no-wget -v --no-interactive --mirror http://cpan.metacpan.org -l $INST_PATH .
echo

# cleanup all junk
rm -rf $SETUP_DIR

echo
echo
echo "Please add the following to beginning of path:"
echo "  $INST_PATH/biobambam2/bin:$INST_PATH/bin"
echo "Please add the following to beginning of PERL5LIB:"
echo "  $PERLROOT"
echo

exit 0
