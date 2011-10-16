package Monitoring::Config::Object::Host;

use strict;
use warnings;
use Moose;
extends 'Monitoring::Config::Object::Parent';

=head1 NAME

Monitoring::Config::Object::Host - Host Object Configuration

=head1 DESCRIPTION

Defaults for host objects

=cut

##########################################################

$Monitoring::Config::Object::Host::Defaults = {
    'name'                            => { type => 'STRING', cat => 'Extended' },
    'use'                             => { type => 'LIST', link => 'host', cat => 'Basic' },
    'register'                        => { type => 'BOOL', cat => 'Extended' },

    'host_name'                       => { type => 'STRING', cat => 'Basic' },
    'alias'                           => { type => 'STRING', cat => 'Basic' },
    'display_name'                    => { type => 'STRING', cat => 'Extended' },
    'address'                         => { type => 'STRING', cat => 'Basic' },
    'parents'                         => { type => 'LIST', 'link' => 'host', cat => 'Basic' },
    'hostgroups'                      => { type => 'LIST', 'link' => 'hostgroup', cat => 'Basic' },
    'check_command'                   => { type => 'COMMAND', 'link' => 'command', cat => 'Checks' },
    'initial_state'                   => { type => 'CHOOSE', values => ['o','d','u'], keys => [ 'Up', 'Down', 'Unreachable' ], cat => 'Extended' },
    'max_check_attempts'              => { type => 'INT', cat => 'Checks' },
    'check_interval'                  => { type => 'INT', cat => 'Checks' },
    'retry_interval'                  => { type => 'INT', cat => 'Checks' },
    'active_checks_enabled'           => { type => 'BOOL', cat => 'Checks' },
    'passive_checks_enabled'          => { type => 'BOOL', cat => 'Checks' },
    'check_period'                    => { type => 'STRING', 'link' => 'timeperiod', cat => 'Checks' },
    'obsess_over_host'                => { type => 'BOOL' },
    'check_freshness'                 => { type => 'BOOL' },
    'freshness_threshold'             => { type => 'INT' },
    'event_handler'                   => { type => 'LIST', 'link' => 'command', cat => 'Eventhandler' },
    'event_handler_enabled'           => { type => 'BOOL', cat => 'Eventhandler' },
    'low_flap_threshold'              => { type => 'INT', cat => 'Flapping' },
    'high_flap_threshold'             => { type => 'INT', cat => 'Flapping'  },
    'flap_detection_enabled'          => { type => 'BOOL', cat => 'Flapping'  },
    'flap_detection_options'          => { type => 'ENUM', values => ['o','d','u'], keys => [ 'Up', 'Down', 'Unreachable' ], cat => 'Flapping'  },
    'process_perf_data'               => { type => 'BOOL', cat => 'Extended' },
    'retain_status_information'       => { type => 'BOOL' },
    'retain_nonstatus_information'    => { type => 'BOOL' },
    'contacts'                        => { type => 'LIST', 'link' => 'contact', cat => 'Contacts' },
    'contact_groups'                  => { type => 'LIST', 'link' => 'contactgroup', cat => 'Contacts' },
    'notification_interval'           => { type => 'INT', cat => 'Notifications' },
    'first_notification_delay'        => { type => 'INT', cat => 'Notifications' },
    'notification_period'             => { type => 'STRING', 'link' => 'timeperiod', cat => 'Notifications' },
    'notification_options'            => { type => 'ENUM', values => ['d','u','r','f','s','n'], keys => [ 'Down', 'Unreachable', 'Recovery', 'Flapping', 'Downtime', 'None' ], cat => 'Notifications' },
    'notifications_enabled'           => { type => 'BOOL', cat => 'Notifications' },
    'stalking_options'                => { type => 'ENUM', values => ['o','d','u'], keys => [ 'Up', 'Down', 'Unreachable' ] },
    'notes'                           => { type => 'STRING', cat => 'Ext Info' },
    'notes_url'                       => { type => 'STRING', cat => 'Ext Info' },
    'action_url'                      => { type => 'STRING', cat => 'Ext Info' },
    'icon_image'                      => { type => 'STRING', link => 'icon', cat => 'Ext Info' },
    'icon_image_alt'                  => { type => 'STRING', cat => 'Ext Info' },
    'vrml_image'                      => { type => 'STRING', cat => 'Map' },
    'statusmap_image'                 => { type => 'STRING', cat => 'Map' },
    '2d_coords'                       => { type => 'STRING', cat => 'Map' },
    '3d_coords'                       => { type => 'STRING', cat => 'Map' },

    # aliased attributes
    'normal_check_interval'           => { type => 'ALIAS', 'name' => 'check_interval' },
    'retry_check_interval'            => { type => 'ALIAS', 'name' => 'retry_interval' },
    'host_groups'                     => { type => 'ALIAS', 'name' => 'hostgroups' },
    'gd2_image'                       => { type => 'ALIAS', 'name' => 'statusmap_image' },
    'checks_enabled'                  => { type => 'ALIAS', 'name' => 'active_checks_enabled' },

    # deprecated attributes
    'parallelize_check'               => { type => 'DEPRECATED' },
    'failure_prediction_enabled'      => { type => 'DEPRECATED' },
};

##########################################################

=head1 METHODS

=head2 new

return new object

=cut
sub new {
    my $class = shift || __PACKAGE__;
    my $self = {
        'type'        => 'host',
        'primary_key' => 'host_name',
        'default'     => $Monitoring::Config::Object::Host::Defaults,
    };
    bless $self, $class;
    return $self;
}


##########################################################

=head2 parse

parse the object config

=cut
sub parse {
    my $self = shift;
    return $self->SUPER::parse($self->{'default'});
}


=head1 AUTHOR

Sven Nierlein, 2011, <nierlein@cpan.org>

=head1 LICENSE

This library is free software, you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
