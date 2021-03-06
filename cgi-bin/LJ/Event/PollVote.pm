package LJ::Event::PollVote;
use strict;
use base 'LJ::Event';
use Class::Autouse qw(LJ::Poll);
use Carp qw(croak);

# we need to specify 'owner' here, because subscriptions are tied
# to the *poster*, not the journal, and we want to fire to the right
# person. we could divine this information from the poll itself,
# but it quickly becomes complicated.
sub new {
    my ($class, $owner, $voter, $poll) = @_;
    croak "No poll owner" unless $owner;
    croak "No poll!" unless $poll;
    croak "No voter!" unless $voter && LJ::isu($voter);

    return $class->SUPER::new($owner, $voter->userid, $poll->id);
}

sub matches_filter {
    my $self = shift;

    # don't notify voters of their own answers
    return $self->voter->equals($self->event_journal) ? 0 : 1;
}

## some utility methods
sub voter {
    my $self = shift;
    return LJ::load_userid($self->arg1);
}

sub poll {
    my $self = shift;
    return LJ::Poll->new($self->arg2);
}

sub entry {
    my $self = shift;
    return $self->poll->entry;
}

sub pollname {
    my $self = shift;
    my $poll = $self->poll;
    my $name = $poll->name;

    return sprintf("Poll #%d", $poll->id) unless $name;

    LJ::Poll->clean_poll(\$name);
    return sprintf("Poll #%d (\"%s\")", $poll->id, $name);
}

## notification methods

sub as_string {
    my ($self, $u) = @_;
    my $lang = ($u && $u->prop('browselang')) || $LJ::DEFAULT_LANG;

# [[voter]] has voted in [[pollname]] at [[entry_url]]
    return LJ::Lang::get_text($lang, 'notification.sms.pollvote', undef, {
        voter     => $self->voter->display_username(1), 
        pollname  => $self->pollname, 
        entry_url => $self->entry->url
    });    
}

sub as_html {
    my $self = shift;
    my $voter = $self->voter;
    my $poll = $self->poll;

    return sprintf("%s has voted in a deleted poll", $voter->ljuser_display)
        unless $poll && $poll->valid;

    my $entry = $self->entry;
    return sprintf("%s has voted <a href='%s'>in %s</a>",
                   $voter->ljuser_display, $entry->url, $self->pollname);
}

sub tmpl_params {
    my ($self, $u) = @_;
    my $voter = $self->voter;
    my $poll = $self->poll;

    my $lang = $u->prop('browselang') || $LJ::DEFAULT_LANG;

    return {
        body    => LJ::Lang::get_text($lang, 'esn.pollvote.deleted.params.body', undef, {user => $voter->ljuser_display}),
        subject => LJ::Lang::get_text($lang, 'esn.pollvote.deleted.params.subject'),
    } unless $poll && $poll->valid;

    my $entry     = $self->entry;
    my $entry_url = $entry->url;
    my $poll_url  = $poll->url;

    return {
        body    => LJ::Lang::get_text($lang, 'esn.pollvote.params.body', undef, 
        { 
            user     => $voter->ljuser_display, 
            url      => $entry->url, 
            pollname => $self->pollname,
        }),
        subject => LJ::Lang::get_text($lang, 'esn.pollvote.params.subject'),
        actions => [{
            action_url => $entry_url,
            action     => LJ::Lang::get_text($lang, 'esn.pollvote.actions.discuss.results'),
        },{
            action_url => $poll_url,
            action     => LJ::Lang::get_text($lang, 'esn.pollvote.actions.poll.status'),
        }],
    }
}

sub as_html_actions {
    my $self = shift;

    my $entry_url = $self->entry->url;
    my $poll_url = $self->poll->url;
    my $ret = "<div class='actions'>";
    $ret .= " <a href='$poll_url'>View poll status</a>";
    $ret .= " <a href='$entry_url'>Discuss results</a>";
    $ret .= "</div>";

    return $ret;
}

my @_ml_strings = (
    'esn.poll_vote.email_text', #Hi [[user]],
                                #
                                #[[voter]] has replied to [[pollname]].
                                #
                                #You can:
                                #
    'esn.poll_vote.subject',    #[[user]] voted in a poll!
    'esn.poll_vote.alert',      #[[user]] voted in a poll!
    'esn.view_poll_status',     #[[openlink]]View the poll's status[[closelink]]
    'esn.discuss_poll'          #[[openlink]]Discuss the poll[[closelink]]
);

sub as_alert {
    my $self = shift;
    my $u = shift;
    return
        LJ::Lang::get_text($u->prop('browselang'), 'esn.poll_vote.alert', undef,
            {
                user        => $self->voter->ljuser_display(),
                openlink    => '<a href="' . $self->entry->url . '">',
                closelink   => '</a>',
            });
}

sub as_email_subject {
    my $self = shift;
    my $u    = shift;
    return LJ::Lang::get_text($u->prop('browselang'), 'esn.poll_vote.subject', undef, { user => $self->voter->display_username } );
}

sub _as_email {
    my ($self, $u, $is_html) = @_;

    my $vars = {
        user     => $is_html ? ($u->ljuser_display) : ($u->display_username),
        voter    => $is_html ? ($self->voter->ljuser_display) : ($self->voter->display_username),
        pollname => $self->pollname,
    };

    my $lang     = $u->prop('browselang');

    # Precache text lines
    LJ::Lang::get_text_multi($lang, undef, \@_ml_strings);

    return LJ::Lang::get_text($lang, 'esn.poll_vote.email_text', undef, $vars) .
        $self->format_options($is_html, $lang, $vars,
        {
            'esn.view_poll_status'  => [ 1, $self->poll->url ],
            'esn.discuss_poll'      => [ 2, $self->entry->url ],
        }
    );
}

sub as_email_string {
    my ($self, $u) = @_;
    return _as_email($self, $u, 0);
}


sub as_email_html {
    my ($self, $u) = @_;
    return _as_email($self, $u, 1);
}

sub content {
    my ($self, $target) = @_;

    return $self->as_html_actions;
}

sub subscription_as_html {
    my ($class, $subscr) = @_;

    my $pollid = $subscr->arg1;

    return $pollid ?
        LJ::Lang::ml('event.poll_vote.id') : # "Someone votes in poll #$pollid";
        LJ::Lang::ml('event.poll_vote.me');  # "Someone votes in a poll I posted" unless $pollid;
}

sub available_for_user  {
    my ($self, $u) = @_;

    return 0 if $self->userid != $u->id;

    return $u->get_cap("track_pollvotes") ? 1 : 0;
}

sub is_subscription_visible_to  {
    my ($self, $u) = @_;

    return 1;
}

sub is_tracking { 0 }

sub as_push {
    my $self = shift;
    my $u    = shift;
    my $lang = shift;

    return LJ::Lang::get_text($lang, "esn.push.notification.pollvote", 1, {
        user    => $self->voter->user,
        journal => $u->user,
    })
}

sub as_push_payload {
    my $self = shift;
    
    return { 't'  => 6,
             'j'  => $self->entry->poster->user,
             'p'  => $self->entry->ditemid,
             'pl' => $self->arg2,
           };
}

1;
