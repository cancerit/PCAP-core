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

#VERSION=1.10.0
VERSION=$(shell perl -I../lib -MPCAP -e 'print PCAP->VERSION;')

#Compiler
CC = gcc -O3 -DVERSION='"$(VERSION)"' -g

#CC = gcc -O3 -DVERSION='"$(VERSION)"' -g

#compiler flags
# -g adds debug info to the executable file
# -Wall turns on most warnings from compiler
CFLAGS = -Wall


HTSLOC?=$(HTSLIB)

HTSTMP?=./htslib_tmp
DEFLATETMP?=./deflate_tmp
prefix=?/usr/local/

#Define locations of header files
OPTINC?= -I$(HTSLOC)/ -I/install_tmp/deflate_tmp/
INCLUDES= -I./ $(OPTINC) -rdynamic

CAT_INCLUDES+= -I$(prefix)/include
CAT_LFLAGS+= -L$(prefix)/lib

# define library paths in addition to /usr/lib
#   if I wanted to include libraries not in /usr/lib I'd specify
#   their path using -Lpath, something like:
LFLAGS?= -L$(HTSTMP) -L$(DEFLATETMP)

# define any libraries to link into executable:
#   if I want to link in libraries (libx.so or libx.a) I use the -llibname
#   option, something like (this will link in libmylib.so and libm.so:
LIBS =-lhts -lpthread -lz -lm -ldl -llzma -lbz2 -ldeflate

# define the C source files
SRCS = ./bam_access.c ./bam_stats_output.c ./bam_stats_calcs.c
#Define test sources
TEST_SRC=$(wildcard ./c_tests/*_tests.c)
TESTS=$(patsubst %.c,%,$(TEST_SRC))

# define the C object files
#
# This uses Suffix Replacement within a macro:
#   $(name:string1=string2)
#         For each word in 'name' replace 'string1' with 'string2'
# Below we are replacing the suffix .c of all words in the macro SRCS
# with the .o suffix
#
OBJS = $(SRCS:.c=.o)

MD := mkdir

#Build target executable
BAM_STATS_TARGET=../bin/bam_stats
SQ_TARGET=../bin/reheadSQ
BAM_DIFF=../bin/diff_bams
MISMATCHQC=../bin/mismatchQc
MMMODIFIER=../bin/mmFlagModifier

#
# The following part of the makefile is generic; it can be used to
# build any executable just by changing the definitions above and by
# deleting dependencies appended to the file from 'make depend'
#

.PHONY: depend clean test make_htslib_tmp remove_htslib_tmp pre

.NOTPARALLEL: test

all: clean pre make_htslib_tmp $(BAM_STATS_TARGET) $(BAM2BG_TARGET) $(BAM2BW_TARGET) $(BAM_DIFF) $(MISMATCHQC) $(MMMODIFIER) test remove_htslib_tmp $(CAT_TARGET) $(SQ_TARGET)
	@echo  bam_stats and reheadSQ compiled.

$(BAM_STATS_TARGET): $(OBJS)
	$(CC) $(CFLAGS) $(INCLUDES) $(CAT_INCLUDES) -o $(BAM_STATS_TARGET) $(OBJS) $(LFLAGS) $(CAT_LFLAGS) $(LIBS) ./bam_stats.c

$(SQ_TARGET):
	$(CC) $(CFLAGS) ./reheadSQ.c -o $(SQ_TARGET)

$(BAM_DIFF):
	$(CC) $(CFLAGS) $(INCLUDES) $(CAT_INCLUDES) -o $(BAM_DIFF) $(OBJS) $(LFLAGS) $(CAT_LFLAGS) $(LIBS) ./diff_bams.c

$(MISMATCHQC):
	$(CC) $(CFLAGS) $(INCLUDES) $(CAT_INCLUDES) -o $(MISMATCHQC) $(OBJS) $(LFLAGS) $(CAT_LFLAGS) $(LIBS) ./mismatchQc.c

$(MMMODIFIER):
	$(CC) $(CFLAGS) $(INCLUDES) $(CAT_INCLUDES) -o $(MMMODIFIER) $(OBJS) $(LFLAGS) $(CAT_LFLAGS) $(LIBS) ./mmFlagModifier.c


#Unit Tests
test: $(BAM_STATS_TARGET)
test: CFLAGS += $(INCLUDES) $(CAT_INCLUDES) $(OBJS) $(LFLAGS) $(CAT_LFLAGS) $(LIBS)
test: $(TESTS)
	sh ./c_tests/runtests.sh

#Unit tests with coverage
coverage: CFLAGS += --coverage
coverage: test

make_htslib_tmp:
	$(MD) $(HTSTMP)
	#Do some magic to ensure we compile BAM_STATS with the static libhts.a rather than libhts.so
	ln -s $(HTSLOC)/libhts.a $(HTSTMP)/libhts.a

remove_htslib_tmp:
	@echo remove tmp hts location
	-rm -rf $(HTSTMP)

copyscript:
	cp ./scripts/* ./bin/
	chmod a+x $(MISMATCHQC) $(MMMODIFIER) $(BAM_STATS_TARGET) $(CAT_TARGET) $(SQ_TARGET) $(BAM2BW_TARGET) $(BAM2BG_TARGET) $(BAM_DIFF)

valgrind:
	VALGRIND="valgrind --log-file=/tmp/valgrind-%p.log" $(MAKE)


# this is a suffix replacement rule for building .o's from .c's
# it uses automatic variables $<: the name of the prerequisite of
# the rule(a .c file) and $@: the name of the target of the rule (a .o file)
# (see the gnu make manual section about automatic variables)
.c.o:
	$(CC) $(CFLAGS) $(INCLUDES) $(CAT_INCLUDES) -c $<  -o $@

clean:
	@echo clean
	$(RM) ./*.o *~ $(BAM_STATS_TARGET) $(MISMATCHQC) $(MMMODIFIER) $(SQ_TARGET) $(BAM_DIFF) ./tests/tests_log $(TESTS) ./*.gcda ./*.gcov ./*.gcno *.gcda *.gcov *.gcno ./tests/*.gcda ./tests/*.gcov ./tests/*.gcno
	-rm -rf $(HTSTMP)

depend: $(SRCS)
	makedepend $(INCLUDES) $^

# DO NOT DELETE THIS LINE -- make depend needs it
