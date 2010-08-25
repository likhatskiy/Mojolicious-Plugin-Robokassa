package Mojolicious::Plugin::Robokassa;

use strict;
use warnings;

use base 'Mojolicious::Plugin';

our $VERSION = '0.1';

use Mojo::ByteStream 'b';
use Data::Dumper;

use constant DEV          => $ENV{'ROBOKASSA_DEV'  } || 0;
use constant DEBUG        => $ENV{'ROBOKASSA_DEBUG'} || 0;
use constant API_URL      => 'https://merchant.roboxchange.com/Index.aspx?';
use constant API_TEST_URL => 'http://test.robokassa.ru/Index.aspx?';

__PACKAGE__->attr('conf' => sub { +{} });

sub register {
	my ($self, $app, $conf)  = @_;
	
	$app->log->error("Config should be a HASH ref!") and return unless ref $conf eq 'HASH';
	$app->log->error("Config is empty!") and return unless %$conf;
	
	$app->log->error("Necessary params are undefined.") and return if grep {!$conf->{$_}} qw/mrh_login mrh_pass1 mrh_pass2/;
	
	$conf->{'culture'} ||= 'ru';
	
	$self->conf($conf);
	
	$app->renderer
		->add_helper('robopay', sub {
			my $c = $_[0];
			my $res = eval { $self->pay(@_) };
			return $@ ? $self->_error($c, $@) : $res;
		})
		->add_helper('roboresult', sub {
			my $c = $_[0];
			my $res = eval { $self->result(@_) };
			return $@ ? $self->_error($c, $@) : $res;
		})
		->add_helper('roboverify', sub {
			my $c = $_[0];
			my $res = eval { $self->verify(@_) };
			return $@ ? $self->_error($c, $@) : $res;
		});
}

sub pay {
	my ($self, $c, %p) = @_;
	my $conf = $self->conf;
	
	my $sum = $p{'OutSum'} || $c->param('OutSum') || 0;
	
	return $c->redirect_to(
		(DEV ? API_TEST_URL : API_URL) . join( '&',
			'MrchLogin='      . $conf->{'mrh_login'},
			'IncCurrLabel='   . ($p{'IncCurrLabel'} || $c->param('IncCurrLabel') || ''),
			'Culture='        . $conf->{'culture'},
			
			'OutSum='         . $sum,
			'InvId='          . $p{'InvId'  } || 0,
			'Email='          . $p{'Email'  } || '',
			'Desc='           . b( $p{'Desc'} || '' )->url_escape,
			(map { "$_\=$p{$_}" } grep {/^Shp_/} keys %p),
			
			'SignatureValue=' . uc b(join ':',
				$conf->{'mrh_login'}, $sum, $p{'InvId'}, $conf->{'mrh_pass1'},
				map { "$_\=$p{$_}" } grep {/^Shp_/} keys %p,
			)->md5_sum,
		)
	);
}

sub result {
	my ($self, $c, $hook) = @_;
	
	my $params = $c->req->params->to_hash;
	DEBUG && $self->_debug($c, Dumper $params);
	
	!$self->_error($c, 'bad sign : '.Dumper($params)) and return $c->render_text('Error: bad sign') unless $self->_verify_signature($c, 2);
	return $c->render_text('OK' . $c->param('InvId')) if !$hook || $hook->($c);
	
	$c->render_text('Error: result_hook error');
}

sub verify {
	my ($self, $c) = @_;
	DEBUG && $self->_debug($c, Dumper $c->req->params->to_hash);
	
	return 1 if $self->_verify_signature($c) and not grep {!$c->param($_)} qw/OutSum InvId/;
	$c->app->log->error("Bad signature or not enough params");
}

sub _verify_signature {
	my ($self, $c, $pass_type) = @_;
	
	$pass_type ||= 1;
	
	uc b(join ':',
		$c->param('OutSum'), $c->param('InvId'), $self->conf->{'mrh_pass' . $pass_type},
		map { $_."=".$c->param($_) } grep {/^Shp_/} keys %{ $c->req->params->to_hash || {} },
	)->md5_sum eq uc $c->param('SignatureValue');
}

sub _debug {
	my ($self, $c, $error) = @_;
	$c->app->log->debug("ROBOKASSA DEBUG: $error");
}

sub _error {
	my ($self, $c, $error) = @_;
	
	$c->app->log->error("ROBOKASSA ERROR: $error");
	
	return;
}

1;
