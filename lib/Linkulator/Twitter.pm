package Linkulator::Twitter;
use Moose;
use namespace::autoclean;
# ABSTRACT: scrape linkulator urls and turn them into tweets

use LWP::UserAgent;
use Net::Twitter;
use String::Truncate 'elide';
use WWW::Shorten 'VGd';
use XML::RAI;

use Linkulator::Twitter::Link;

has feed_url => (
    is      => 'ro',
    isa     => 'Str',
    default => 'http://offtopic.akrasiac.org/?feed=sfw',
);

has twitter_user => (
    is      => 'ro',
    isa     => 'Str',
    default => 'crawl_offtopic',
);

has twitter_access_token => (
    is        => 'ro',
    isa       => 'Str',
    predicate => 'has_twitter_access_token',
);

has twitter_access_token_secret => (
    is        => 'ro',
    isa       => 'Str',
    predicate => 'has_twitter_access_token_secret',
);

has links => (
    traits  => ['Array'],
    isa     => 'ArrayRef[Linkulator::Twitter::Link]',
    default => sub { [] },
    handles => {
        links    => 'elements',
        add_link => 'push',
    },
);

has twitter_consumer_key => (
    is      => 'ro',
    isa     => 'Str',
    default => '6mW3vek1Edty1NGJe7yPFg',
);

has twitter_consumer_secret => (
    is      => 'ro',
    isa     => 'Str',
    default => 'OzQuhNQ4HlO2eQw9tdo8R4QDLYqORwSEIzkF6ZBCAY',
);

has ua => (
    is      => 'ro',
    isa     => 'LWP::UserAgent',
    default => sub { LWP::UserAgent->new },
);

has twitter => (
    is      => 'ro',
    isa     => 'Net::Twitter',
    lazy    => 1,
    default => sub {
        my $self = shift;
        Net::Twitter->new(
            traits          => ['API::REST', 'OAuth'],
            consumer_key    => $self->twitter_consumer_key,
            consumer_secret => $self->twitter_consumer_secret,
            ($self->has_twitter_access_token
                ? (access_token => $self->twitter_access_token)
                : ()),
            ($self->has_twitter_access_token_secret
                ? (access_token_secret => $self->twitter_access_token_secret)
                : ()),
        );
    },
);

sub authenticate_twitter {
    my $self = shift;
    my ($pin) = @_;

    return if $self->twitter->authorized;

    return $self->twitter->get_authorization_url
        if !defined $pin;

    my ($token, $secret, $id, $user) = $self->twitter->request_access_token(
        verifier => $pin,
    );
    die "Authenticated the wrong user: $user (should be " . $self->twitter_user . ')'
        unless $self->twitter_user eq $user;

    return ($token, $secret);
}

sub update {
    my $self = shift;

    my $res = $self->ua->get($self->feed_url);
    die "couldn't get " . $self->feed_url . " : " . $res->status_line
        unless $res->is_success;

    my $rss = $self->_munge_xml($res->content);

    my $feed = XML::RAI->parse_string($rss);
    die "got no items!" unless $feed->item_count;

    for my $item (@{ $feed->items }) {
        my ($link_num) = ($item->identifier =~ /(\d+)$/);
        my $uri = $item->link;
        $uri =~ s/^\s+|\s+$//g;
        my $desc = $item->title;
        $desc =~ s/^\s+|\s+$//g;
        $self->add_link(
            Linkulator::Twitter::Link->new(
                id   => $link_num,
                uri  => $uri,
                desc => $desc,
            )
        );
    }
}

sub tweet {
    my $self = shift;
    my ($link) = @_;

    die "not a link"
        unless blessed($link) && $link->isa('Linkulator::Twitter::Link');

    my $uri = makeashorterlink($link->uri);
    my $desc = elide($link->desc, 140 - length($uri) - 1, { at_space => 1 });

    $self->twitter->update("$desc $uri");
}

# the feed produces invalid xml - the <link> and <guid> tags don't escape
# ampersands in urls, and the xml parser chokes on this. need to fix it up
# here.
sub _munge_xml {
    my $self = shift;
    my ($xml) = @_;

    $xml =~ s#<(link|guid)(.*)>([^<]*)</\1>#
        my ($tag, $attrs, $text) = ($1, $2, $3);
        $text =~ s+&+&amp;+g;
        "<${tag}${attrs}>$text</$tag>"
    #eg;

    return $xml;
}

__PACKAGE__->meta->make_immutable;

1;
