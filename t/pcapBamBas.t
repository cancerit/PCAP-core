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

use strict;
use Test::More;
use Test::Fatal;
use File::Spec;
use Try::Tiny qw(try catch finally);
use Const::Fast qw(const);

const my $MODULE => 'PCAP::Bam::Bas';
const my $RG_1 => 1;
const my $EXP_MEDIAN => '462.000';
const my $RG_ORDER => [qw(1 2 3 4 5 6)];

use FindBin qw($Bin);
my $test_data = "$Bin/data";

my $bas = File::Spec->catfile($test_data, 'test.bam.bas');
my $empty_bas = File::Spec->catfile($test_data, 'empty.bam.bas');

subtest 'Initialisation checks' => sub {
  use_ok($MODULE);
  my $obj = new_ok($MODULE => [$bas]);

  like(exception { $MODULE->new; }, qr/No bas file defined/, 'Expected error, no file provided');
  like(exception { $MODULE->new('fake'); }, qr/\*\.bas file: .* does not exist/, q{Expected error, file doesn't exist});
  like(exception { $MODULE->new($empty_bas); }, qr/\*\.bas file: .* is empty/, q{Expected error, file empty});
  like(exception { $obj->bas_keys(1); }, qr/bas_keys should only be initialised once/, q{Expected error, value passed to pre-initialised function});
};

subtest 'Access checks' => sub {
  my $obj = new_ok($MODULE => [$bas]);
  is($obj->get($RG_1, 'median_insert_size'), $EXP_MEDIAN, 'Get expected value with correct key');
  is($obj->get($RG_1, 'wibble'), undef, 'Get undef with unknown key');
  my @rgs = $obj->read_groups;
  is_deeply(\@rgs, $RG_ORDER, 'Readgroups returned sorted');
  like(exception { $obj->get(99, 'wibble'); }, qr/Readgroup '.*' does not exist/, 'Expected error, unkown RG');
};

done_testing();
