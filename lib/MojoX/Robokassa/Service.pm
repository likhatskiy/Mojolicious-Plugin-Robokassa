package MojoX::Robokassa::Service;

use strict;
use warnings;

use base 'Mojo::Base';
use utf8;

use Mojo::Client;
use Mojo::ByteStream 'b';
use Data::Dumper;

__PACKAGE__->attr(url => sub { +{
	rates           => 'https://merchant.roboxchange.com/WebService/Service.asmx/GetRates',
	op_state        => 'https://merchant.roboxchange.com/WebService/Service.asmx/OpState',
	currencies      => 'https://merchant.roboxchange.com/WebService/Service.asmx/GetCurrencies',
	payment_methods => 'https://merchant.roboxchange.com/WebService/Service.asmx/GetPaymentMethods',
} });

__PACKAGE__->attr(edesc => sub { +{
	1    => 'неверная цифровая подпись запроса',
	2    => 'информация о магазине с таким MerchantLogin не найдена или магазин не активирован',
	3    => 'информация об операции с таким InvoiceID не найдена',
	1000 => 'внутренняя ошибка сервиса',
} });

__PACKAGE__->attr(op_state_desc => sub { +{
	5   => 'только инициирована, деньги не получены',
	10  => 'деньги не были получены, операция отменена',
	50  => 'деньги от пользователя получены, производится зачисление денег на счет магазина',
	60  => 'деньги после получения были возвращены пользователю',
	80  => 'исполнение операции приостановлено',
	100 => 'операция завершена успешно',
} });

__PACKAGE__->attr(conf   => sub { +{} });
__PACKAGE__->attr(client => sub { Mojo::Client->new });

sub op_state {
	my ($self, $invoice_iD) = @_;
	my $conf = $self->conf;
	
	warn 'Config is empty!'   and return unless %$conf;
	warn 'InvoiceID is null!' and return unless $invoice_iD;
	
	my $res = $self->client->post_form(
		$self->url->{'op_state'},
		{
			MerchantLogin => $conf->{mrh_login},
			InvoiceID     => $invoice_iD,
			Signature     => $self->signature($conf->{'mrh_login'}, $invoice_iD, $conf->{'mrh_pass2'})
		}
	)->success;
	
	return unless $res;
	$res = $res->dom;
	#~ use Mojo::DOM;
	#~ my $res = Mojo::DOM->new->parse(b('
#~ <?xml version="1.0" encoding="utf-8"?>
#~ <OperationStateResponse xmlns:xsd="http://www.w3.org/2001/XMLSchema" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns="http://merchant.roboxchange.com/WebService/">
  #~ <Result>
    #~ <Code>0</Code>
  #~ </Result>
  #~ <State>
    #~ <Code>100</Code>
    #~ <RequestDate>2010-10-05T23:45:53.936341+04:00</RequestDate>
    #~ <StateDate>2010-09-02T06:42:39.193+04:00</StateDate>
  #~ </State>
  #~ <Info>
    #~ <IncCurrLabel>WMRM</IncCurrLabel>
    #~ <IncSum>0.090000</IncSum>
    #~ <IncAccount>WMID: 278396172364 WMP: R529688644158</IncAccount>
    #~ <PaymentMethod>
      #~ <Code>EMoney</Code>
      #~ <Description>Электронными деньгами</Description>
    #~ </PaymentMethod>
    #~ <OutCurrLabel>BNR</OutCurrLabel>
    #~ <OutSum>0.090000</OutSum>
  #~ </Info>
#~ </OperationStateResponse>')->encode('utf-8')->to_string);
	my $data = $self->parse( $res->at('operationstateresponse') );
	
	if ($data->{'result'}->{'code'}) {
		warn $self->edesc->{ $data->{'result'}->{'code'} } and return;
	}
	
	$data->{state}->{$_} = join ' ', ISO_8601($data->{state}->{$_}) for qw/statedate requestdate/;
	
	return $data;
}

sub signature {
	shift;
	
	uc b(join ':', @_)->md5_sum;
}

sub parse {
	my $self = shift;
	
	return {
		map {
			$_->name => $_->text || $_->text eq '0'
			? $_->text
			: $self->parse($_)
		}
		@{ shift->children }
	};
}

sub ISO_8601 { join ' ', +shift =~ /^(\d+-\d+-\d+)T(\d+:\d+:\d+)/ }

1;