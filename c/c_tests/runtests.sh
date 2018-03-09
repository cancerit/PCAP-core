##########LICENCE##########
# PCAP - NGS reference implementations and helper code for the ICGC/TCGA Pan-Cancer Analysis Project
# Copyright (C) 2014-2018 ICGC PanCancer Project
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

echo "Running unit tests:"

for i in c_tests/*_tests
do
	if test -f $i
	then
		if $VALGRIND ./$i 2>> c_tests/tests_log
		then
			echo $i PASS
		else
			echo "ERROR in test $i: here's tests/tests_log"
			echo "------"
			tail c_tests/tests_log
			exit 1
		fi
	fi
done

echo "Running script tests:"

for j in c_tests/test_*.sh
do
  if ./$j 2>> c_tests/tests_log
   then echo $j PASS
  else
    echo "ERROR in "$j": here's c_tests/tests_log"
    echo "------"
    tail c_tests/tests_log
    exit 1
  fi
done
echo ""
