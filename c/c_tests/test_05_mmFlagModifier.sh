#!/bin/bash

##########LICENCE##########
# PCAP - NGS reference implementations and helper code for the ICGC/TCGA Pan-Cancer Analysis Project
# Copyright (C) 2014-2018 ICGC PanCancer Project
# Copyright (C) 2018-2021 Cancer, Ageing and Somatic Mutation, Genome Research Limited
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not see:
#   http://www.gnu.org/licenses/gpl-2.0.html
##########LICENCE##########

compare_sam () {
  sam1 = $1;
  sam2 = $2;
  #Cut out the header and sort from first sam
  grep -e '^@' $1 | perl -aple '@F=sort @F;$_=join qq{\t},@F;' > $1.tmphead
  #Cut out the header and sort from second sam
  grep -e '^@' $2 | perl -aple '@F=sort @F;$_=join qq{\t},@F;' > $2.tmphead
  diff $1.tmphead  $2.tmphead
  if [ "$?" != "0" ];
  then
    echo "ERROR in "$0": Comparing headers of sam files $1 and $2."
    return 1
  fi
  rm $1.tmphead $2.tmphead
  grep -ve '^@' $1 > $1.tmpreads
  grep -ve '^@' $2 > $2.tmpreads
  diff $1.tmpreads $2.tmpreads
  if [ "$?" != "0" ];
  then
    echo "ERROR in "$0": Comparing reads of sam files $1 and $2."
    return 1
  fi
  rm $1.tmpreads $2.tmpreads
  return 0
}

#Ensure valid format produced
../bin/mmFlagModifier -i ../t/data/mismatch_test.bam -m | bamvalidate
if [ "$?" != "0" ];
then
  echo "ERROR running ../bin/mmFlagModifier -i ../t/data/mismatch_test.bam -m . Invalid output"
  exit 1;
fi

../bin/mmFlagModifier -i ../t/data/mismatch_test.bam -p | bamvalidate
if [ "$?" != "0" ];
then
  echo "ERROR running ../bin/mmFlagModifier -i ../t/data/mismatch_test.bam -p. Invalid output"
  exit 1;
fi

../bin/mmFlagModifier -i ../t/data/mismatch_test.cram -C -m | bamvalidate inputformat=cram
if [ "$?" != "0" ];
then
  echo "ERROR running ../bin/mmFlagModifier -i ../t/data/mismatch_test.bam -C. Invalid output cram compression"
  exit 1;
fi

../bin/mmFlagModifier -i ../t/data/mismatch_test.cram -C -p | bamvalidate inputformat=cram
if [ "$?" != "0" ];
then
  echo "ERROR running ../bin/mmFlagModifier -i ../t/data/mismatch_test.bam -C. Invalid output cram compression"
  exit 1;
fi

../bin/mmFlagModifier -i ../t/data/mismatch_test.bam -m | bamcollate2 inputformat=bam outputformat=sam collate=0 resetaux=0 > ../t/data/mmFlagModifier_test_out.sam;
if [ "$?" != "0" ];
then
  echo "ERROR running ../bin/mmFlagModifier -i ../t/data/mismatch_test.bam -m | bamcollate2 inputformat=bam outputformat=sam collate=0 resetaux=0 > ../t/data/mmFlagModifier_test_out.sam"
  exit 1;
fi

if [ compare_sam '../t/data/mmFlagModifier_test_out.sam' '../t/data/mmFlagModifier_m_expected_out.sam' != "0" ];
then
  echo "ERROR in "$0": Comparing mmFlagModifier to expected result failed."
	echo "------"
	rm ../t/data/mmFlagModifier_test_out.sam
  exit 1
fi

../bin/mmFlagModifier -i ../t/data/mmFlagModifier_p_input.bam -p | bamcollate2 inputformat=bam outputformat=sam collate=0 resetaux=0 > ../t/data/mmFlagModifier_test_out.sam;
if [ "$?" != "0" ];
then
  echo "ERROR running ../bin/mmFlagModifier -i ../t/data/mismatch_test.bam -p | bamcollate2 inputformat=bam outputformat=sam collate=0 resetaux=0 > ../t/data/mmFlagModifier_test_out.sam"
  exit 1;
fi

if [ compare_sam '../t/data/mmFlagModifier_test_out.sam' '../t/data/mismatch_expected_out.sam' != "0" ];
then
  echo "ERROR in "$0": Comparing mmFlagModifier to expected result failed."
	echo "------"
	rm ../t/data/mmFlagModifier_test_out.sam
  exit 1
fi

rm ../t/data/mmFlagModifier_test_out.sam
