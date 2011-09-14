package Linkulator::Twitter::Link;
use Moose;
use namespace::autoclean;

has id => (
    is       => 'ro',
    isa      => 'Int',
    required => 1,
);

has uri => (
    is       => 'ro',
    isa      => 'Str',
    required => 1,
);

has desc => (
    is       => 'ro',
    isa      => 'Str',
    required => 1,
);

__PACKAGE__->meta->make_immutable;

1;
