# class for passing around LiveJournal errors/warnings, both user-caused
# and system-caused

package LJ::Error;
use strict;
use Carp qw(croak);

# helper function, aliased from LJ::errobj, but here so croak bypasses
# it, since it has to be in the same package or in an @ISA package
# from the caller
#
# Two ways to call:
#
# As a shortcut for constructing a new error object:
#   - LJ::errobj("Userpic::TooManyWords", %opts)
#   - LJ::errobj("BogusParams");
# this is short for LJ::Error::Userpic::TooManyWords->new(%opts)
# but also sets up @ISA on LJ::Error::Userpic::TooManyWords-
#
# As a way to get an LJ::Error instance after an eval
# that died:
#   eval { LJ::scary(); }
#   if (my $err = LJ::errobj()) {  # or you can pass in errobj($@)
#      ....
#   }
#
# returns undef if $@ is undef,
# returns LJ::Error object otherwise.  specific instance is:
#
#      LJ::Error::DieString   -- for deaths with die "Error message!";
#          $ljerr->die_string -- to get the string
#      LJ::Error::DieObject   -- for deaths w/ Exception.pm/etc
#          $ljerr->die_object -- to get the object
#      LJ::Error::*           -- if $@ isa LJ::Error, returns $@ unmodified
#      LJ::Error::Database::Failure -- if given a $dbh/$u after a failure,
#                                      will get the errstr/errmsg
#
sub errobj {
    # constructing a new LJ::Error instance.  either with a classname
    # and args, or just a classname (no whitespace, must have one capital letter)
    if (@_ > 0 && (@_ > 1 || ($_[0] !~ /\s/ && $_[0] =~ /[A-Z]/ && $_[0] !~ /[^:\w]/))) {
        my ($classtail, @ctor_args) = @_;
        my $class = "LJ::Error::$classtail";
        my $makeit = sub { $class->new(@ctor_args); };
        my $val = eval { $makeit->(); };
        if ($@ =~ /^Can\'t locate object method "new" via package "(LJ::Error::\S+?)"/) {
            my $class = $1;
            my $code = "\@${class}::ISA = ('LJ::Error'); 1;";
            eval $code or die "Failed to set ISA: [$@] for code: [$code]\n";
        }
        return $val || $makeit->();
    }

    # if no parameters, act like errobj($@)
    $_[0] = $@ unless @_;

    my $ref = ref $_[0];

    # wrapping a database (or database-like) handle
    if (LJ::isdb($_[0]) || $ref eq "LJ::User") {
        return errobj("Database::Failure", db => $_[0]);
    }

    # wrapping return of an error object
    return errobj("DieString", message => $_[0]) unless $ref;

    # wrapping an LJ::Error object, returning it unchanged
    return $_[0] if $ref =~ /^LJ::Error/;  # should use ->isa, but then have to catch it on HASH, etc

    # else it's a reference, but not one of ours, so we wrap it
    return errobj("DieObject", object => $_[0]);
}

# don't override this!
sub new {
    my $class = shift;
    my %opts  = @_;

    my ($line, $file);
    my $self = {
        _line => $line,
        _file => $file,
    };

    foreach my $f ($class->fields) {
        croak("Missing field in $class ctor: '$f'")
            unless exists $opts{$f};
        $self->{$f} = delete $opts{$f};
    }
    foreach my $f ($class->opt_fields) {
        $self->{$f} = delete $opts{$f};
    }

    if (%opts) {
        croak("Unknown fields in $class ctor: " . join(", ", keys %opts));
    }

    return bless $self, $class;
}

# don't override.
sub field {
    my ($self, $field) = @_;
    croak("Invalid field for object " . ref $self) unless
        exists $self->{$field};
    return $self->{$field};
}

# don't override.
sub throw {
    my $self = shift;
    die $self;
}

# throws self, if $LJ::THROW_ERRORS is dynamically set w/ local,
# else returns undef (by default), or the value passed to it
sub cond_throw {
    my $self = shift;
    my $ret_value = shift;
    $self->throw if $LJ::THROW_ERRORS;
    return defined $ret_value ? $ret_value : undef;
}

# override this: whether it was user-defined.  should return 0 or 1.
sub user_caused { undef }

# override this: return list of required fields
sub fields { (); }

# override this: return list of optional fields
sub opt_fields { (); }

# you may override this
sub as_html {
    my $self = shift;
    return LJ::ehtml($self->as_string);
}

# override this
sub as_string {
    my $self = shift;

    # FIXME: show line/file/function, show some fields?  maybe?  that are simple values?
}

# automatic type returned when something dies with just a string
package LJ::Error::DieString;
sub fields { qw(message) }
sub die_string { return $_[0]->field('message'); }

# automatic type returned when something dies with a reference, but not
# an LJ::Error
package LJ::Error::DieObject;
sub fields { qw(object) }
sub die_object { return $_[0]->field('object'); }


1;
