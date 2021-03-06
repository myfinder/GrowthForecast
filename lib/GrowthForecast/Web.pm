package GrowthForecast::Web;

use strict;
use warnings;
use utf8;
use Kossy;
use Time::Piece;
use GrowthForecast::Data;
use GrowthForecast::RRD;

sub data {
    my $self = shift;
    $self->{__data} ||= GrowthForecast::Data->new($self->root_dir);
    $self->{__data};
}

sub rrd {
    my $self = shift;
    $self->{__rrd} ||= GrowthForecast::RRD->new($self->root_dir);
    $self->{__rrd};
}

get '/' => sub {
    my ( $self, $c )  = @_;
    my $services = $self->data->get_services();
    my @services;
    for my $service ( @$services ) {
        my $sections = $self->data->get_sections($service);
        push @services , {
            name => $service,
            sections => $sections,
        };
    }
    $c->render('index.tx', { services => \@services });
};

get '/docs' => sub {
    my ( $self, $c )  = @_;
    $c->render('docs.tx',{});
};

get '/list/:service_name/:section_name' => sub {
    my ( $self, $c )  = @_;
    my $rows = $self->data->get_graphs(
        $c->args->{service_name}, $c->args->{section_name}
    );
    $c->halt(404) unless scalar @$rows;
    $c->render('list.tx',{ graphs => $rows });
};

get '/graph/:service_name/:section_name/:graph_name' => sub {
    my ( $self, $c )  = @_;
    my $result = $c->req->validator([
        'span' => {
            default => 'd',
            rule => [
                [['CHOICE',qw/y m w d c/],'invalid span'],
            ],
        },
        'from' => {
            default => localtime(time-86400*8)->strftime('%Y/%m/%d %T'),
            rule => [
                [sub{ HTTP::Date::str2time($_[1]) }, 'invalid From datetime'],
            ],
        },
        'to' => {
            default => localtime()->strftime('%Y/%m/%d %T'),
            rule => [
                [sub{ HTTP::Date::str2time($_[1]) }, 'invalid To datetime'],
            ],
        }
    ]);

    my $row = $self->data->get(
        $c->args->{service_name}, $c->args->{section_name}, $c->args->{graph_name},
    );
    $c->halt(404) unless $row;

    my $img = $self->rrd->graph(
        $result->valid('span'), $result->valid('from'),
        $result->valid('to'),  $row
    );

    $c->res->content_type('image/png');
    $c->res->body($img);
    return $c->res;
};

get '/api/:service_name/:section_name/:graph_name' => sub {
    my ( $self, $c )  = @_;
    my $row = $self->data->get(
        $c->args->{service_name}, $c->args->{section_name}, $c->args->{graph_name},
    );
    $c->halt(404) unless $row;
    $c->render_json($row);
};

post '/api/:service_name/:section_name/:graph_name' => sub {
    my ( $self, $c )  = @_;
    my $result = $c->req->validator([
        'number' => {
            rule => [
                ['NOT_NULL','number is null'],
                ['INT','number is not null']
            ],
        },
        'description' => {
            default => '',
            rule => [],
        },
        'mode' => {
            default => 'gauge',
            rule => [
                [['CHOICE',qw/count gauge/],'count or gauge']
            ],
        }
    ]);

    if ( $result->has_error ) {
        my $res = $c->render_json({
            error => 1,
            messages => $result->messages
        });
        $res->status(400);
        return $res;
    }

    my $row = $self->data->update(
        $c->args->{service_name}, $c->args->{section_name}, $c->args->{graph_name},
        $result->valid('number'), $result->valid('description'), $result->valid('mode')
    );
    $c->render_json({ error => 0, data => $row });
};

1;

