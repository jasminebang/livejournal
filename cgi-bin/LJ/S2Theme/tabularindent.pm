package LJ::S2Theme::tabularindent;
use strict;

use base qw(LJ::S2Theme);

sub cats { qw( clean cool ) }
sub designer { "Scott Freeman" }

sub display_option_props {
    my $self = shift;
    my @props = qw( counter_code );
    return $self->_append_props("display_option_props", @props);
}

sub text_props {
    my $self = shift;
    my @props = qw( main_fgcolor link_color vlink_color alink_color );
    return $self->_append_props("text_props", @props);
}

sub header_bar_props {
    my $self = shift;
    my @props = qw( headerbar_bgcolor headerbar_fgcolor );
    return $self->_append_props("header_bar_props", @props);
}

sub caption_bar_props {
    my $self = shift;
    my @props = qw( captionbar_mainbox_bgcolor captionbar_mainbox_fgcolor captionbar_userpicbox_color );
    return $self->_append_props("caption_bar_props", @props);
}

sub entry_props {
    my $self = shift;
    my @props = qw( border_color_entries date_format time_format );
    return $self->_append_props("entry_props", @props);
}

sub comment_props {
    my $self = shift;
    my @props = qw(
        comment_bar_one_bgcolor comment_bar_two_fgcolor comment_bar_two_bgcolor comment_bar_one_fgcolor comment_bar_screened_bgcolor
        comment_bar_screened_fgcolor text_post_comment text_read_comments text_post_comment_friends text_read_comments_friends
        text_left_comments text_btwn_comments text_right_comments datetime_comments_format
    );
    return $self->_append_props("comment_props", @props);
}


### Themes ###
1;
