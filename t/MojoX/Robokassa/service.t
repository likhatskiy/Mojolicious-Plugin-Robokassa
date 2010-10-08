#!/usr/bin/env perl

use strict;
use warnings;

use lib qw(lib);
use utf8;

use Test::More tests => 10;
use Data::Dumper;

use_ok("MojoX::Robokassa::Service");

my $s = MojoX::Robokassa::Service->new;

$s->conf({
	mrh_login       => 'demo',
	mrh_pass1       => 'Morbid11',
	mrh_pass2       => 'Morbid11',
});

ok ref $s->op_state(1) eq 'HASH';