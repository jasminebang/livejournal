package LJ::NotificationMethod;
use strict;
use Carp qw/ croak /;

use Class::Autouse qw (LJ::Typemap
                       LJ::NotificationMethod::Email
                       LJ::NotificationMethod::SMS
                       LJ::NotificationMethod::SMSru
                       LJ::NotificationMethod::Inbox
                       LJ::NotificationMethod::IM
                       LJ::NotificationMethod::DebugLog
                       LJ::NotificationMethod::Alerts
                       LJ::NotificationMethod::Push
                       LJ::NotificationMethod::Web
                       );

# this mofo is basically just an interface
# Mischa's contribution:  "straight up"
sub new    { croak "can't instantiate base LJ::NotificationMethod" }
sub notify { croak "can't call notification on LJ::NotificationMethod base class" }
sub title  { croak "can't call title on LJ::NotificationMethod base class" }

sub can_digest { 0 }

# subclasses have to override
sub configured          { 0 }  # system-wide configuration
sub configured_for_user { my ($class, $u) = @_; return 0; }

# override where applicable
sub disabled_url { undef }
sub url { undef }
sub help_url { undef }
sub is_subtype_enabled { 1 }

# run a hook to see if a user can receive these kinds of notifications
sub available_for_user  {
    my ($class, $u) = @_;

    my $available = LJ::run_hook('notificationmethod_available_for_user', $class, $u);

    return defined $available ? $available : 1;
}

sub new_from_subscription {
    my ($class, $subscription) = @_;

    my $sub_class = $class->class($subscription->ntypeid)
        or return undef;

    return $sub_class->new_from_subscription($subscription);
}

# this should return a unique identifier for this notification method
# so that we don't send more than one of the same notification
# override this if implementing extra properties
# instance method
sub unique {
    my $self = shift;

    croak "Unique is an instance method" unless ref $self;

    return $self->class;
}

# get the typemap for the notifytype classes (class/instance method)
sub typemap {
    return LJ::Typemap->new(
        table       => 'notifytypelist',
        classfield  => 'class',
        idfield     => 'ntypeid',
    );
}

# returns the class name, given an ntypid
sub class {
    my ($class, $typeid) = @_;
    my $tm = $class->typemap
        or return undef;

    $typeid ||= $class->ntypeid;

    croak "Invalid typeid" unless $typeid;

    return $tm->typeid_to_class($typeid);
}

# returns the notifytypeid for this site.
# don't override this in subclasses.
sub ntypeid {
    my ($class_self) = @_;
    my $class = ref $class_self ? ref $class_self : $class_self;

    my $tm = $class->typemap
        or return undef;

    return $tm->class_to_typeid($class);
}

# Class method
# Returns ntypeid given an event name
sub method_to_ntypeid {
    my ($class, $meth_name) = @_;

    $meth_name = "LJ::NotificationMethod::$meth_name" unless $meth_name =~ /^LJ::NotificationMethod::/;
    return eval { $meth_name->ntypeid };
}

# this returns a list of all possible notification method classes
# class method
*all_classes = \&all_available_methods;
sub all_available_methods {
    my $class = shift;
    croak "all_classes is a class method" unless $class;

    return grep {
        ! $LJ::DISABLED{$_} &&
        $_->configured
    } @LJ::NOTIFY_TYPES;
}

# indicates that remote can use this one; may be overriden in subclasses
sub remote_eligible { 1 }

1;
