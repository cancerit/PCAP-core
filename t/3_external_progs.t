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

# this is a catch all to ensure all modules do compile
# added as lots of 'use' functionality is dynamic in pipeline
# and need to be sure that all modules compile.
# simple 'perl -c' is unlikely to work on head scripts any more.

use strict;
use Test::More;
use File::Which qw(which);
use List::Util qw(first);
use Const::Fast qw(const);
use Capture::Tiny qw(capture);
use Data::Dumper;
use version 0.77;

const my @REQUIRED_PROGRAMS => qw(bamcollate2 bammarkduplicates2 bamsort bwa samtools);
const my $BIOBAMBAM2_VERSION => '2.0.86';
const my $BWA_VERSION => '0.7.12';
const my $SAMTOOLS_VERSION => '1.7';

# can't put regex in const
my %EXPECTED_VERSION = (
                        'bamcollate2'       => {
                              'get'   => q{ --version},
                              'match' => qr/This is biobambam2 version ([[:digit:]\.]+)\./,
                              'version'       => version->parse($BIOBAMBAM2_VERSION),
                              'out' => 'stderr',
                            },
                        'bammarkduplicates2' => {
                              'get'   => q{ --version},
                              'match' => qr/This is biobambam2 version ([[:digit:]\.]+)\./,
                              'version'       => version->parse($BIOBAMBAM2_VERSION),
                              'out' => 'stderr',
                            },
                        'bamsort'           => {
                              'get'   => q{ --version},
                              'match' => qr/This is biobambam2 version ([[:digit:]\.]+)\./,
                              'version'       => version->parse($BIOBAMBAM2_VERSION),
                              'out' => 'stderr',
                            },
                        'bwa'           => {
                              'get'   => q{},
                              'match' => qr/Version: ([[:digit:]\.]+[[:alpha:]]?)/, # we don't care about the revision number
                              'version'       => version->parse($BWA_VERSION),
                              'out' => 'stderr',
                            },
                        'samtools'           => {
                              'get'   => q{ --version},
                              'match' => qr/samtools ([[:digit:]\.]+)/,
                              'version' => version->parse($SAMTOOLS_VERSION),
                              'out' => 'stdout',
                            },
                        );

subtest 'External programs exist on PATH' => sub {
  for my $prog(@REQUIRED_PROGRAMS) {
    my $path = which($prog);
    isnt($path, q{}, "$prog found at $path");
  }
};

subtest 'External programs have expected version' => sub {
  for my $prog(@REQUIRED_PROGRAMS) {
    my $path = which($prog);
    my $details = $EXPECTED_VERSION{$prog};
    my $command = $path.$details->{'get'};
    my ($stdout, $stderr, $exit) = capture{ system($command); };
    my $stream = $stderr;
    if($details->{'out'} eq 'stdout') {
      $stream = $stdout;
    }

    my $reg = $details->{'match'};
    my ($version) = $stream =~ /$reg/m;
    version->parse($version);

    ok(version->parse($version) >= $details->{'version'}, sprintf 'Expect minimum version of %s for %s, got %s', $details->{'version'}, $prog, $version);
  }
};

done_testing();
