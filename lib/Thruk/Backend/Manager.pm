package Thruk::Backend::Manager;

use strict;
use warnings;
use Carp;
use Digest::MD5 qw(md5_hex);
use Data::Page;
use Data::Dumper;
use Scalar::Util qw/ looks_like_number /;
use Encode;
use Thruk::Utils;

our $AUTOLOAD;

=head1 NAME

Thruk::Backend::Manager - Manager of backend connections

=head1 DESCRIPTION

Manager of backend connections

=head1 METHODS

=cut

##########################################################
# use static list instead of slow module find
$Thruk::Backend::Manager::Provider = [
          'Thruk::Backend::Provider::Livestatus'
];

##########################################################

=head2 new

create new manager

=cut

sub new {
    my( $class ) = @_;
    my $self = {
        'initialized'         => 0,
        'stats'               => undef,
        'log'                 => undef,
        'config'              => undef,
        'state_hosts'         => {},
        'local_hosts'         => {},
        'backends'            => [],
    };
    bless $self, $class;
    return $self;
}

##########################################################

=head2 init

initialize this model

=cut

sub init {
    my( $self, %options ) = @_;

    return if $self->{'initialized'} == 1;

    for my $opt_key ( keys %options ) {
        if( exists $self->{$opt_key} ) {
            $self->{$opt_key} = $options{$opt_key};
        }
        else {
            croak("unknown option: $opt_key");
        }
    }

    return unless defined $self->{'config'}->{'Thruk::Backend'};
    return unless defined $self->{'config'}->{'Thruk::Backend'}->{'peer'};

    $self->_initialise_backends( $self->{'config'}->{'Thruk::Backend'}->{'peer'} );

    # check if we initialized at least one backend
    return if scalar @{ $self->{'backends'} } == 0;

    for my $peer (@{$self->get_peers()}) {
        $peer->{'local'} = 1;
        if($peer->{'addr'} =~ m/^(.*):/mx) {
            $self->{'state_hosts'}->{$peer->{'key'}} = $1;
        } else {
            $self->{'local_hosts'}->{$peer->{'key'}} = 1;
        }
    }

    $self->{'initialized'} = 1;

    return 1;
}

##########################################################

=head2 disable_hidden_backends

  disable_hidden_backends()

returns list of hidden backends

=cut

sub disable_hidden_backends {
    my $self               = shift;
    my $disabled_backends  = shift || {};
    for my $peer (@{$self->get_peers()}) {
        if(defined $peer->{'hidden'} and $peer->{'hidden'} == 1) {
            $disabled_backends->{$peer->{'key'}} = 2;
        }
    }
    return $disabled_backends;
}

##########################################################

=head2 get_peers

  get_peers()

returns all configured peers

=cut

sub get_peers {
    my $self  = shift;
    my @peers = @{ $self->{'backends'} };
    return \@peers;
}

##########################################################

=head2 get_peer_by_key

  get_peer_by_key()

returns all peer by key

=cut

sub get_peer_by_key {
    my $self = shift;
    my $key  = shift;
    for my $peer ( @{ $self->get_peers() } ) {
        return $peer if $peer->{'key'} eq $key;
    }
    return;
}

##########################################################

=head2 peer_key

  peer_key()

returns all peer keys

=cut

sub peer_key {
    my $self = shift;
    my @keys;
    for my $peer ( @{ $self->get_peers() } ) {
        push @keys, $peer->{'key'};
    }
    return \@keys;
}

##########################################################

=head2 disable_backend

  disable_backend(<key>)

disable backend by key

=cut

sub disable_backend {
    my $self = shift;
    my $key  = shift;

    my $peer = $self->get_peer_by_key($key);
    if( defined $peer ) {
        $peer->{'enabled'} = 0;
    }
    return;
}

##########################################################

=head2 enable_backend

  enable_backend(<key>)

ensable backend by key

=cut

sub enable_backend {
    my $self = shift;
    my $key  = shift;

    my $peer = $self->get_peer_by_key($key);
    if( defined $peer ) {
        $peer->{'enabled'} = 1;
    }
    return;
}

##########################################################

=head2 disable_backends

  disable_backends(<keys_hash>)

disabled backend by key hash

=cut

sub disable_backends {
    my $self = shift;
    my $keys = shift;

    if( defined $keys ) {
        for my $key ( keys %{$keys} ) {
            if( $keys->{$key} == 2 or $keys->{$key} == 3 ) {
                $self->disable_backend($key);
            }
        }
    }
    else {
        for my $peer ( @{ $self->get_peers() } ) {
            $peer->{'enabled'} = 0;
        }
    }
    return;
}

##########################################################

=head2 enable_backends

  enable_backends(<keys>)

enables all backends

=cut

sub enable_backends {
    my $self = shift;
    my $keys = shift;

    if( defined $keys ) {
        for my $key ( keys %{$keys} ) {
            $self->enable_backend($key);
        }
    }
    else {
        for my $peer ( @{ $self->get_peers() } ) {
            $peer->{'enabled'} = 1;
        }
    }
    return;
}

########################################

=head2 get_contactgroups_by_contact

  get_contactgroups_by_contact

returns a list of contactgroups by contact

=cut

sub get_contactgroups_by_contact {
    my( $self, $c, $username ) = @_;

    my $cache       = $c->cache;
    my $cached_data = $cache->get($username);
    if( defined $cached_data->{'contactgroups'} ) {
        return $cached_data->{'contactgroups'};
    }

    my $data = $self->_do_on_peers( "get_contactgroups_by_contact", [ $username ]);
    my $contactgroups = {};
    for my $group (@{$data}) {
        $contactgroups->{$group->{'name'}} = 1;
    }

    $cached_data->{'contactgroups'} = $contactgroups;
    $c->cache->set( $username, $cached_data );
    return $contactgroups;
}

########################################

=head2 expand_command

  expand_command

expand a command line with host/service data

=cut

sub expand_command {
    my( $self, %data ) = @_;
    croak("no host")    unless defined $data{'host'};
    my $host     = $data{'host'};
    my $service  = $data{'service'};
    my $command  = $data{'command'};

    my $command_name = $host->{'check_command'};
    if(defined $service) {
        $command_name = $service->{'check_command'};
    }
    my($name, @com_args) = split(/!/mx, $command_name, 255);

    # it is possible to define hosts without a command
    if(!defined $name or $name =~ m/^\s*$/mx) {
        my $return = {
            'line'          => 'no command defined',
            'line_expanded' => '',
        };
        return $return;
    }

    # get command data
    my $expanded;
    if(defined $command) {
        $expanded = $command->{'line'};
    } else {
        my $commands = $self->get_commands( filter => [ { 'name' => $name } ] );
        $expanded = $commands->[0]->{'line'};
    }

    # arguments
    my $x = 1;
    for my $arg (@com_args) {
        $expanded =~ s/\$ARG$x\$/$arg/gmx;
        $x++;
    }

    $expanded = $self->_replace_macros({string => $expanded, host => $host, service => $service});

    # does it still contain macros?
    my $note = "";
    if($expanded =~ m/\$[\w:]+\$/mx) {
        $note = "could not expand all macros!";
    }

    my $return = {
        'line'          => $command_name,
        'line_expanded' => $expanded,
        'note'          => $note,
    };
    return $return;
}

########################################

=head2 set_backend_state_from_local_connections

  set_backend_state_from_local_connections

enables/disables remote backends based on a state from local instances

=cut

sub set_backend_state_from_local_connections {
    my( $self, $disabled ) = @_;

    $self->{'stats'}->profile( begin => "set_backend_state_from_local_connections() " ) if defined $self->{'stats'};

    return unless scalar keys %{$self->{'local_hosts'}} >= 1;
    return unless scalar keys %{$self->{'state_hosts'}} >= 1;

    my $options = [
        'backend', [ keys %{$self->{'local_hosts'}} ],
        'columns', [qw/address name alias state/],
    ];

    my @filter;
    for my $host (values %{$self->{'state_hosts'}}) {
        push @filter, { '-or' => [ { name    => { '=' => $host } },
                                   { alias   => { '=' => $host } },
                                   { address => { '=' => $host } },
                      ]};
    }
    push @{$options}, 'filter', [ Thruk::Utils::combine_filter( '-or', \@filter ) ];
    eval {
        my $data = $self->_do_on_peers( "get_hosts", $options );
        for my $host (@{$data}) {
            # find matching key
            my $key;
            for my $state_key (keys %{$self->{'state_hosts'}}) {
                my $name = $self->{'state_hosts'}->{$state_key};
                $key = $state_key if $host->{'name'}    eq $name;
                $key = $state_key if $host->{'address'} eq $name;
                $key = $state_key if $host->{'alias'}   eq $name;
            }
            next unless defined $key;
            my $peer = $self->get_peer_by_key($key);
            next if $disabled->{$key};

            if($host->{'state'} == 0) {
                $self->{'log'}->debug($key." -> enabled by local state check");
                $peer->{'enabled'}  = 1 unless $peer->{'enabled'} == 2;
                $peer->{'runnning'} = 1;
            } else {
                $self->{'log'}->debug($key." -> disabled by local state check");
                $self->disable_backend($key);
                $peer->{'runnning'} = 0;
            }
        }
    };
    if($@) {
        $self->{'log'}->error("failed setting states by local check: ".$@);
    }

    $self->{'stats'}->profile( end => "set_backend_state_from_local_connections() " ) if defined $self->{'stats'};

    return;
}

########################################

=head2 _replace_macros

  _replace_macros

returns a result for a sub called on all peers

=cut

sub _replace_macros {
    my( $self, $args ) = @_;

    my $string  = $args->{'string'};
    my $host    = $args->{'host'};
    my $service = $args->{'service'};

    # user macros...
    my $user_macros = $self->_get_user_macros($host->{'peer_key'});
    if(defined $user_macros) {
        for my $x (1..32) {
            $string =~ s/\$USER$x\$/$user_macros->{'$USER'.$x.'$'}/gmx if defined $user_macros->{'$USER'.$x.'$'};
        }
    }

    # host macros
    $string = $self->_replace_host_macros($string, $host);

    # service macros
    if(defined $service) {
        $string = $self->_replace_service_macros($string, $service);
    }

    return($string);
}

########################################

=head2 _replace_host_macros

  _replace_host_macros

returns a string with replaced host macros

=cut

sub _replace_host_macros {
    my( $self, $string, $host ) = @_;

    # normal host macros
    my $hostmacros = {
        'HOSTADDRESS'   => $host->{'address'},
        'HOSTNAME'      => $host->{'name'},
        'HOSTALIAS'     => $host->{'alias'},
        'HOSTSTATEID'   => $host->{'state'},
        'HOSTSTATE'     => $self->{'config'}->{'nagios'}->{'host_state_by_number'}->{$host->{'state'}},
        'HOSTLATENCY'   => $host->{'latency'},
        'HOSTOUTPUT'    => $host->{'plugin_output'},
        'HOSTPERFDATA'  => $host->{'perf_data'},
        'HOSTATTEMPT'   => $host->{'current_attempt'},
    };
    for my $key (keys %{$hostmacros}) {
        $string =~ s/\$$key\$/$hostmacros->{$key}/gmx;
    }

    # host user macros
    my $x = 0;
    for my $key (@{$host->{'custom_variable_names'}}) {
        $string =~ s/\$_HOST$key\$/$host->{'custom_variable_values'}->[$x]/gmx;
        $x++;
    }

    return $string;
}

########################################

=head2 _replace_service_macros

  _replace_service_macros

returns a string with replaced service macros

=cut

sub _replace_service_macros {
    my( $self, $string, $service ) = @_;

    # normal host macros
    my $servicemacros = {
        'SERVICEDESC'      => $service->{'description'},
        'SERVICESTATEID'   => $service->{'state'},
        'SERVICESTATE'     => $self->{'config'}->{'nagios'}->{'service_state_by_number'}->{$service->{'state'}},
        'SERVICELATENCY'   => $service->{'latency'},
        'SERVICEOUTPUT'    => $service->{'plugin_output'},
        'SERVICEPERFDATA'  => $service->{'perf_data'},
        'SERVICEATTEMPT'   => $service->{'current_attempt'},
    };
    for my $key (keys %{$servicemacros}) {
        $string =~ s/\$$key\$/$servicemacros->{$key}/gmx;
    }

    # service user macros...
    my $x = 0;
    for my $key (@{$service->{'custom_variable_names'}}) {
        $string =~ s/\$_SERVICE$key\$/$service->{'custom_variable_values'}->[$x]/gmx;
        $x++;
    }

    return $string;
}
########################################

=head2 _do_on_peers

  _do_on_peers

returns a result for a sub called on all peers

=cut

sub _do_on_peers {
    my( $self, $function, $arg ) = @_;

    # do we have to send the query to all backends or just a few?
    my(%arg, $backends);
    if(     ( $function =~ m/^get_/mx or $function eq 'send_command')
        and ref $arg eq 'ARRAY'
        and scalar @{$arg} % 2 == 0 )
    {
        %arg = @{$arg};

        if( $arg{'backend'} ) {
            if(ref $arg{'backend'} eq 'ARRAY') {
                for my $b (@{$arg{'backend'}}) {
                    $backends->{$b} = 1;
                }
            } else {
                $backends->{$arg{'backend'}} = 1;
            }
        }
    }

    # send query to selected backends
    my( $result, $type, $size );
    my $totalsize = 0;
    my $selected_backends = 0;
    for my $peer ( @{ $self->get_peers() } )
    {
        if(defined $backends) {
            next unless defined $backends->{$peer->{'key'}};
        }
        next unless $peer->{'enabled'} == 1;

        $self->{'stats'}->profile( begin => "_do_on_peers() - " . $peer->{'name'} ) if defined $self->{'stats'};
        $selected_backends++;
        eval {
            my( $data, $typ, $size ) = $peer->{'class'}->$function( @{$arg} );
            if(defined $data and !defined $size) {
                if(ref $data eq 'ARRAY') {
                    $size = scalar @{$data};
                }
                elsif(ref $data eq 'HASH') {
                    $size = scalar keys %{$data};
                }
            }
            $size = 0 unless defined $size;
            $type = $typ if defined $typ;
            $totalsize += $size;
            $result->{ $peer->{'key'} } = $data;
        };
        $self->{'stats'}->profile( end => "_do_on_peers() - " . $peer->{'name'} ) if defined $self->{'stats'};
    }
    if(!defined $result and $selected_backends != 0) {
        #confess("Error in _do_on_peers: ".$@."called as ".Dumper($function)."with args: ".Dumper($arg));
        die($@);
    }
    $type = '' unless defined $type;

    # howto merge the answers?
    my $data;
    if( lc $type eq 'uniq' ) {
        $data = $self->_merge_answer( $result, $type );
        my %seen = ();
        my @uniq = sort( grep { !$seen{$_}++ } @{$data} );
        $data = \@uniq;
    }
    elsif ( lc $type eq 'stats' ) {
        $data = $self->_merge_stats_answer($result);
    }
    elsif ( lc $type eq 'sum' ) {
        $data = $self->_sum_answer($result);
    }
    elsif ( $function eq 'get_hostgroups' ) {
        $data = $self->_merge_hostgroup_answer($result);
    }
    elsif ( $function eq 'get_servicegroups' ) {
        $data = $self->_merge_servicegroup_answer($result);
    }
    else {
        $data = $self->_merge_answer( $result, $type );
    }


    # additional data processing, paging, sorting and limiting
    if(scalar keys %arg > 0) {
        if( $arg{'remove_duplicates'} ) {
            $data = $self->_remove_duplicates($data);
            $totalsize = scalar @{$data};
        }

        if( $arg{'sort'} ) {
            $data = $self->_sort( $data, $arg{'sort'} );
        }

        if( $arg{'limit'} ) {
            $data = $self->_limit( $data, $arg{'limit'} );
        }

        if( $arg{'pager'} ) {
            $data = $self->_page_data( $arg{'pager'}, $data, undef, $totalsize );
        }
    }

    # set some defaults if no backends where selected
    if($function eq "get_performance_stats" and ref $data eq 'ARRAY') {
        $data = {};
        for my $type (qw{hosts services}) {
            for my $key (qw{_active_sum _active_1_sum _active_5_sum _active_15_sum _active_60_sum _active_all_sum
                            _passive_sum _passive_1_sum _passive_5_sum _passive_15_sum _passive_60_sum _passive_all_sum
                            _execution_time_sum _latency_sum _active_state_change_sum _execution_time_min _latency_min _active_state_change_min _execution_time_max _latency_max
                            _active_state_change_max _passive_state_change_sum _passive_state_change_min _passive_state_change_max
                            _execution_time_avg _latency_avg }) {
                $data->{$type.$key} = 0;
            }
        }
    }
    if($function eq "get_service_stats" and ref $data eq 'ARRAY') {
        $data = {};
        for my $key (qw{
                        total total_active total_passive pending pending_and_disabled pending_and_scheduled ok ok_and_disabled ok_and_scheduled
                        warning warning_and_disabled warning_and_scheduled warning_and_ack warning_on_down_host warning_and_unhandled critical
                        critical_and_disabled critical_and_scheduled critical_and_ack critical_on_down_host critical_and_unhandled
                        unknown unknown_and_disabled unknown_and_scheduled unknown_and_ack unknown_on_down_host unknown_and_unhandled
                        flapping flapping_disabled notifications_disabled eventhandler_disabled active_checks_disabled passive_checks_disabled
                     }) {
            $data->{$key} = 0;
        }
    }
    if($function eq "get_host_stats" and ref $data eq 'ARRAY') {
        $data = {};
        for my $key (qw{
                        total total_active total_passive pending pending_and_disabled pending_and_scheduled up up_and_disabled up_and_scheduled
                        down down_and_ack down_and_scheduled down_and_disabled down_and_unhandled unreachable unreachable_and_ack unreachable_and_scheduled
                        unreachable_and_disabled unreachable_and_unhandled flapping flapping_disabled notifications_disabled eventhandler_disabled active_checks_disabled passive_checks_disabled outages
                     }) {
            $data->{$key} = 0;
        }
    }

    return $data;
}

########################################

=head2 _remove_duplicates

  _remove_duplicates($data)

removes duplicate entries from a array of hashes

=cut

sub _remove_duplicates {
    my $self = shift;
    my $data = shift;

    $self->{'stats'}->profile( begin => "Utils::remove_duplicates()" ) if defined $self->{'stats'};

    # calculate md5 sums
    my $uniq = {};
    for my $dat ( @{$data} ) {
        my $peer_key = $dat->{'peer_key'};
        delete $dat->{'peer_key'};
        my $peer_name = $dat->{'peer_name'};
        delete $dat->{'peer_name'};
        my $peer_addr = $dat->{'peer_addr'};
        delete $dat->{'peer_addr'};
        my $md5 = md5_hex( encode_utf8( join( ';', values %{$dat} ) ) );
        if( !defined $uniq->{$md5} ) {
            $dat->{'peer_key'}  = $peer_key;
            $dat->{'peer_name'} = $peer_name;
            $dat->{'peer_addr'} = $peer_addr;

            $uniq->{$md5} = {
                'data'      => $dat,
                'peer_key'  => [$peer_key],
                'peer_name' => [$peer_name],
                'peer_addr' => [$peer_addr],
            };
        }
        else {
            push @{ $uniq->{$md5}->{'peer_key'} },  $peer_key;
            push @{ $uniq->{$md5}->{'peer_name'} }, $peer_name;
            push @{ $uniq->{$md5}->{'peer_addr'} }, $peer_addr;
        }
    }

    my $return = [];
    for my $data ( values %{$uniq} ) {
        $data->{'data'}->{'backend'} = {
            'peer_key'  => $data->{'peer_key'},
            'peer_name' => $data->{'peer_name'},
            'peer_addr' => $data->{'peer_addr'},
        };
        push @{$return}, $data->{'data'};

    }

    $self->{'stats'}->profile( end => "Utils::remove_duplicates()" ) if defined $self->{'stats'};
    return ($return);
}

########################################

=head2 _page_data

  _page_data($c, $data, [$result_size], [$total_size])

adds paged data set to the template stash.
Data will be available as 'data'
The pager itself as 'pager'

=cut

sub _page_data {
    my $self                = shift;
    my $c                   = shift;
    my $data                = shift || [];
    return $data unless defined $c;
    my $default_result_size = shift || $c->stash->{'default_page_size'};
    my $totalsize           = shift;

    # set some defaults
    $c->stash->{'pager'} = "";
    $c->stash->{'data'}  = $data;

    # page only in html mode
    my $view_mode = $c->{'request'}->{'parameters'}->{'view_mode'} || 'html';
    return $data unless $view_mode eq 'html';

    # we dont use paging at all?
    return 1 unless $c->stash->{'use_pager'};

    my $entries = $c->{'request'}->{'parameters'}->{'entries'} || $default_result_size;
    return 1 unless defined $entries;
    $c->stash->{'entries_per_page'} = $entries;

    my $pager = new Data::Page;
    if(defined $totalsize) {
        $pager->total_entries( $totalsize );
    } else {
        $pager->total_entries( scalar @{$data} );
    }
    if( $entries eq 'all' ) { $entries = $pager->total_entries; }
    my $pages = 0;
    if( $entries > 0 ) {
        $pages = POSIX::ceil( $pager->total_entries / $entries );
    }
    else {
        $c->stash->{'data'} = $data;
        return $data;
    }

    my $page = 1;
    # current page set by get parameter
    if(defined $c->{'request'}->{'parameters'}->{'page'}) {
        $page = $c->{'request'}->{'parameters'}->{'page'};
    }
    # current page set by jump anchor
    elsif(defined $c->{'request'}->{'parameters'}->{'jump'}) {
        my $nr = 0;
        my $jump = $c->{'request'}->{'parameters'}->{'jump'};
        if(exists $data->[0]->{'description'}) {
            for my $row (@{$data}) {
                $nr++;
                if(defined $row->{'host_name'} and defined $row->{'description'} and $row->{'host_name'}."_".$row->{'description'} eq $jump) {
                    $page = POSIX::ceil($nr / $entries);
                    last;
                }
            }
        }
        elsif(exists $data->[0]->{'name'}) {
            for my $row (@{$data}) {
                $nr++;
                if(defined $row->{'name'} and $row->{'name'} eq $jump) {
                    $page = POSIX::ceil($nr / $entries);
                    last;
                }
            }
        }
    }

    # last/first/prev or next button pressed?
    if(   exists $c->{'request'}->{'parameters'}->{'next'}
       or exists $c->{'request'}->{'parameters'}->{'next.x'} ) {
        $page++;
    }
    elsif (   exists $c->{'request'}->{'parameters'}->{'previous'}
           or exists $c->{'request'}->{'parameters'}->{'previous.x'} ) {
        $page-- if $page > 1;
    }
    elsif (    exists $c->{'request'}->{'parameters'}->{'first'}
            or exists $c->{'request'}->{'parameters'}->{'first.x'} ) {
        $page = 1;
    }
    elsif (    exists $c->{'request'}->{'parameters'}->{'last'}
            or exists $c->{'request'}->{'parameters'}->{'last.x'} ) {
        $page = $pages;
    }

    if( $page < 0 )      { $page = 1; }
    if( $page > $pages ) { $page = $pages; }

    $c->stash->{'current_page'} = $page;

    if( $entries eq 'all' ) {
        $c->stash->{'data'} = $data;
    }
    else {
        $pager->entries_per_page($entries);
        $pager->current_page($page);
        my @data = $pager->splice($data);
        $c->stash->{'data'} = \@data;
    }

    $c->stash->{'pager'} = $pager;
    $c->stash->{'pages'} = $pages;

    # set some variables to avoid undef values in templates
    $c->stash->{'pager_previous_page'} = $pager->previous_page() || 0;
    $c->stash->{'pager_next_page'}     = $pager->next_page()     || 0;

    return $data;
}
##########################################################

=head2 AUTOLOAD

  AUTOLOAD()

redirects sub calls to out backends

=cut

sub AUTOLOAD {
    my $self = shift;
    my $name = $AUTOLOAD;
    my $type = ref($self) or confess "$self is not an object, called as (" . $name . ")";
    $name =~ s/.*://mx;    # strip fully-qualified portion
    return $self->_do_on_peers( $name, \@_ );
}

##########################################################

=head2 DESTROY

  DESTROY()

destroy this

=cut

sub DESTROY {
}

##########################################################
sub _initialise_backends {
    my $self   = shift;
    my $config = shift;

    confess "no backend config" unless defined $config;

    # did we get a single peer or a list of peers?
    my @peer_configs;
    if( ref $config eq 'HASH' ) {
        push @peer_configs, $config;
    }
    elsif ( ref $config eq 'ARRAY' ) {
        @peer_configs = @{$config};
    }
    else {
        confess "invalid backend config, must be hash or an array of hashes";
    }

    # initialize peers
    for my $peer_conf (@peer_configs) {
        my $peer = $self->_initialise_peer( $peer_conf, $Thruk::Backend::Manager::Provider );
        push @{ $self->{'backends'} }, $peer if defined $peer;
    }

    return;
}

##########################################################
sub _initialise_peer {
    my $self     = shift;
    my $config   = shift;
    my $provider = shift;

    confess "missing name in peer configuration" unless defined $config->{'name'};
    confess "missing type in peer configuration" unless defined $config->{'type'};

    my @provider = grep { $_ =~ m/::$config->{'type'}$/mxi } @{$provider};
    confess "unknown type in peer configuration" unless scalar @provider > 0;
    my $class = $provider[0];

    my $require = $class;
    $require =~ s/::/\//gmx;
    require $require . ".pm";
    $class->import;
    $config->{'options'}->{'name'} = $config->{'name'} unless defined $config->{'options'}->{'name'};

    # disable keepalive for now, it does not work and causes lots of problems
    $config->{'options'}->{'keepalive'} = 0 if defined $config->{'options'}->{'keepalive'};

    my $peer = {
        'name'          => $config->{'name'},
        'type'          => $config->{'type'},
        'hidden'        => $config->{'hidden'},
        'groups'        => $config->{'groups'},
        'resource_file' => $config->{'options'}->{'resource_file'},
        'enabled'       => 1,
        'class'         => $class->new( $config->{'options'}, $self->{'config'}, $self->{'log'} ),
        'configtool'    => $config->{'configtool'} || {},
    };
    # shorten backend id
    $peer->{'key'} = substr(md5_hex($peer->{'class'}->peer_addr." ".$peer->{'class'}->peer_name), 0, 5);
    $peer->{'class'}->{'live'}->{'backend_obj'}->{'key'} = $peer->{'key'};
    $peer->{'addr'} = $peer->{'class'}->peer_addr();
    if(Thruk->debug) {
        $peer->{'class'}->set_verbose(1);
    }

    return $peer;
}

##########################################################
sub _merge_answer {
    my $self   = shift;
    my $data   = shift;
    my $type   = shift;
    my $return = [];
    if( defined $type and lc $type eq 'hash' ) {
        $return = {};
    }

    $self->{'stats'}->profile( begin => "_merge_answer()" ) if defined $self->{'stats'};

    # iterate over original peers to retain order
    for my $peer ( @{ $self->get_peers() } ) {
        my $key = $peer->{'key'};
        next if !defined $data->{$key};

        if( ref $data->{$key} eq 'ARRAY' ) {
            $return = [] unless defined $return;
            $return = [ @{$return}, @{ $data->{$key} } ];
        }
        elsif ( ref $data->{$key} eq 'HASH' ) {
            $return = {} unless defined $return;
            $return = { %{$return}, %{ $data->{$key} } };
        }
        else {
            push @{$return}, $data->{$key};
        }
    }

    $self->{'stats'}->profile( end => "_merge_answer()" ) if defined $self->{'stats'};

    return ($return);
}

##########################################################
# merge hostgroups and merge 'members' of matching groups
sub _merge_hostgroup_answer {
    my $self   = shift;
    my $data   = shift;
    my $groups = {};

    $self->{'stats'}->profile( begin => "_merge_hostgroup_answer()" ) if defined $self->{'stats'};

    for my $peer ( @{ $self->get_peers() } ) {
        my $key = $peer->{'key'};
        next if !defined $data->{$key};

        confess("not an array ref") if ref $data->{$key} ne 'ARRAY';

        for my $row ( @{ $data->{$key} } ) {
            if( !defined $groups->{ $row->{'name'} } ) {
                $groups->{ $row->{'name'} } = $row;
                $groups->{ $row->{'name'} }->{'members'} = [ @{ $row->{'members'} } ];
            }
            else {
                $groups->{ $row->{'name'} }->{'members'} = [ @{ $groups->{ $row->{'name'} }->{'members'} }, @{ $row->{'members'} } ];
            }

            if( !defined $groups->{ $row->{'name'} }->{'backends_hash'} ) { $groups->{ $row->{'name'} }->{'backends_hash'} = {} }
            $groups->{ $row->{'name'} }->{'backends_hash'}->{ $row->{'peer_name'} } = 1;
        }
    }

    # set backends used
    for my $group ( values %{$groups} ) {
        $group->{'backend'} = [];
        @{ $group->{'backend'} } = sort keys %{ $group->{'backends_hash'} };
        delete $group->{'backends_hash'};
    }
    my @return = values %{$groups};

    $self->{'stats'}->profile( end => "_merge_hostgroup_answer()" ) if defined $self->{'stats'};

    return ( \@return );
}

##########################################################
# merge servicegroups and merge 'members' of matching groups
sub _merge_servicegroup_answer {
    my $self   = shift;
    my $data   = shift;
    my $groups = {};

    $self->{'stats'}->profile( begin => "_merge_servicegroup_answer()" ) if defined $self->{'stats'};
    for my $peer ( @{ $self->get_peers() } ) {
        my $key = $peer->{'key'};
        next if !defined $data->{$key};

        confess("not an array ref") if ref $data->{$key} ne 'ARRAY';

        for my $row ( @{ $data->{$key} } ) {
            if( !defined $groups->{ $row->{'name'} } ) {
                $groups->{ $row->{'name'} } = $row;
                $groups->{ $row->{'name'} }->{'members'} = [ @{ $row->{'members'} } ];
            }
            else {
                $groups->{ $row->{'name'} }->{'members'} = [ @{ $groups->{ $row->{'name'} }->{'members'} }, @{ $row->{'members'} } ];
            }
            if( !defined $groups->{ $row->{'name'} }->{'backends_hash'} ) { $groups->{ $row->{'name'} }->{'backends_hash'} = {} }
            $groups->{ $row->{'name'} }->{'backends_hash'}->{ $row->{'peer_name'} } = 1;
        }
    }

    # set backends used
    for my $group ( values %{$groups} ) {
        $group->{'backend'} = [];
        @{ $group->{'backend'} } = sort keys %{ $group->{'backends_hash'} };
        delete $group->{'backends_hash'};
    }

    my @return = values %{$groups};

    $self->{'stats'}->profile( end => "_merge_servicegroup_answer()" ) if defined $self->{'stats'};

    return ( \@return );
}

##########################################################
sub _merge_stats_answer {
    my $self = shift;
    my $data = shift;
    my $return;

    $self->{'stats'}->profile( begin => "_merge_stats_answer()" ) if defined $self->{'stats'};

    for my $peername ( keys %{$data} ) {
        if( ref $data->{$peername} eq 'HASH' ) {
            for my $key ( keys %{ $data->{$peername} } ) {
                if( !defined $return->{$key} ) {
                    $return->{$key} = $data->{$peername}->{$key};
                }
                elsif ( looks_like_number( $data->{$peername}->{$key} ) ) {
                    if( $key =~ m/_sum$/mx ) {
                        $return->{$key} += $data->{$peername}->{$key};
                    }
                    elsif ( $key =~ m/_min$/mx ) {
                        $return->{$key} = $data->{$peername}->{$key} if $return->{$key} > $data->{$peername}->{$key};
                    }
                    elsif ( $key =~ m/_max$/mx ) {
                        $return->{$key} = $data->{$peername}->{$key} if $return->{$key} < $data->{$peername}->{$key};
                    }
                }
            }
        }
    }

    # percentages and averages?
    for my $key ( keys %{$return} ) {
        if( $key =~ m/^(.*)_(\d+|all)_sum$/mx ) {
            my $pkey = $1 . '_sum';
            my $nkey = $1 . '_' . $2 . '_perc';
            if( exists $return->{$pkey} and $return->{$pkey} > 0 ) {
                $return->{$nkey} = $return->{$key} / $return->{$pkey} * 100;
            }
            else {
                $return->{$nkey} = 0;
            }
        }

        # active averages
        for my $akey (
            qw/execution_time_sum
            latency_sum
            active_state_change_sum/
            )
        {
            if( $key =~ m/(hosts|services)_$akey/mx ) {
                my $type = $1;
                my $nkey = $type . '_' . $akey;
                $nkey =~ s/_sum$/_avg/mx;
                $return->{$nkey} = 0;
                if( $return->{$key} > 0 and $return->{ $type . '_active_sum' } > 0 ) {
                    $return->{$nkey} = $return->{$key} / $return->{ $type . '_active_sum' };
                }
            }
        }

        # passive averages
        for my $akey (qw/passive_state_change_sum/) {
            if( $key =~ m/(hosts|services)_$akey/mx ) {
                my $type = $1;
                my $nkey = $type . '_' . $akey;
                $nkey =~ s/_sum$/_avg/mx;
                $return->{$nkey} = 0;
                if( $return->{$key} > 0 ) {
                    $return->{$nkey} = $return->{$key} / $return->{ $type . '_passive_sum' };
                }
            }
        }
    }

    $self->{'stats'}->profile( end => "_merge_stats_answer()" ) if defined $self->{'stats'};

    return $return;
}

##########################################################
sub _sum_answer {
    my $self = shift;
    my $data = shift;
    my $return;

    $self->{'stats'}->profile( begin => "_sum_answer()" ) if defined $self->{'stats'};

    for my $peername ( keys %{$data} ) {
        if( ref $data->{$peername} eq 'HASH' ) {
            for my $key ( keys %{ $data->{$peername} } ) {
                if( !defined $return->{$key} ) {
                    $return->{$key} = $data->{$peername}->{$key};
                }
                elsif ( looks_like_number( $data->{$peername}->{$key} ) ) {
                    $return->{$key} += $data->{$peername}->{$key};
                }
            }
        }
        else {
            confess( "not a hash, got: " . ref( $data->{$peername} ) );
        }
    }

    $self->{'stats'}->profile( end => "_sum_answer()" ) if defined $self->{'stats'};

    return $return;
}

########################################

=head2 _sort

  _sort($data, $sortby)

sort a array of hashes by hash keys

  sortby can be a scalar

  $sortby = 'name'

  sortby can be an array

  $sortby = [ 'name', 'description' ]

  sortby can be an hash

  $sortby = { 'DESC' => [ 'name', 'description' ] }

=cut

sub _sort {
    my $self   = shift;
    my $data   = shift;
    my $sortby = shift;
    my( @sorted, $key, $order );

    $key = $sortby;
    if( ref $sortby eq 'HASH' ) {
        if(defined $sortby->{'ASC'} and defined $sortby->{'DESC'}) {
            confess('unusual sort config:\n'.Dumper($sortby));
        }
        for my $ord (qw/ASC DESC/) {
            if( defined $sortby->{$ord} ) {
                $key   = $sortby->{$ord};
                $order = $ord;
                last;
            }
        }
    }

    if( !defined $key ) { confess('missing options in sort()'); }

    $self->{'stats'}->profile( begin => "_sort()" ) if defined $self->{'stats'};

    $order = "ASC" if !defined $order;

    return \@sorted if !defined $data;
    return \@sorted if scalar @{$data} == 0;

    my @keys;
    if( ref($key) eq 'ARRAY' ) {
        @keys = @{$key};
    }
    else {
        @keys = ($key);
    }

    my @compares;
    for my $key (@keys) {

        # sort numeric
        if( defined $data->[0]->{$key} and $data->[0]->{$key} =~ m/^\d+$/xm ) {
            push @compares, '$a->{' . $key . '} <=> $b->{' . $key . '}';
        }

        # sort alphanumeric
        else {
            push @compares, '$a->{' . $key . '} cmp $b->{' . $key . '}';
        }
    }
    my $sortstring = join( ' || ', @compares );

    ## no critic
    no warnings;    # sorting by undef values generates lots of errors
    if( uc $order eq 'ASC' ) {
        eval '@sorted = sort { ' . $sortstring . ' } @{$data};';
    }
    else {
        eval '@sorted = reverse sort { ' . $sortstring . ' } @{$data};';
    }
    use warnings;
    ## use critic

    $self->{'stats'}->profile( end => "_sort()" ) if defined $self->{'stats'};

    return ( \@sorted );
}

########################################

=head2 _limit

  _limit($data, $limit)

returns data limited by limit

=cut

sub _limit {
    my $self  = shift;
    my $data  = shift;
    my $limit = shift;

    return $data unless defined $limit and $limit > 0;

    if( scalar @{$data} > $limit ) {
        @{$data} = @{$data}[ 0 .. $limit ];
        return $data;
    }

    return ($data);
}


########################################

=head2 _get_user_macros

  _get_user_macros($peer_key)

returns the USER1-32 macros from a resource file

=cut

sub _get_user_macros {
    my $self     = shift;
    my $peer_key = shift;
    if(defined $peer_key) {
        my $backend = $self->get_peer_by_key($peer_key);
        if(defined $backend->{'resource_file'}) {
            return $self->_read_resource_file($backend->{'resource_file'});
        }
    }
    return $self->_read_resource_file($self->{'config'}->{'resource_file'});
}


########################################

=head2 _read_resource_file

  _read_resource_file($file)

returns a hash with all USER1-32 macros

=cut

sub _read_resource_file {
    my $self   = shift;
    my $file   = shift;
    return unless defined $file;
    return unless -f $file;
    my %macros = Config::General::ParseConfig($file);
    for my $key (keys %macros) {
        if(ref $macros{$key} eq 'ARRAY') {
            $macros{$key} = $macros{$key}[$#{$macros{$key}}];
        }
    }
    return \%macros;
}


=head1 AUTHOR

Sven Nierlein, 2010, <nierlein@cpan.org>

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
