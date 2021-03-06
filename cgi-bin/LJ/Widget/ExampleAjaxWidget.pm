package LJ::Widget::ExampleAjaxWidget;

use strict;
use base qw(LJ::Widget);
use Carp qw(croak);

sub ajax { 1 }
#sub need_res { qw( stc/widgets/examplepostwidget.css ) }

sub render_body {
    my $class = shift;
    my %opts = @_;

    my $ret;
    my $submitted = $opts{submitted} ? 1 : 0;

    $ret .= "This widget does an AJAX POST.<br />";
    $ret .= 'Render it with: <code><br>my $widget = LJ::Widget::ExampleAjaxWidget->new;';
    $ret .= '<br>$headextra .= $widget->wrapped_js;<br>$body .= $widget->render();</code>';
    $ret .= $class->start_form( id => "ajax_form" );
    $ret .= "<p>Type in a word: " . $class->html_text( name => "text", size => 10 ) . " ";
    $ret .= $class->html_submit( button => "Click me!" ) . "</p>";
    $ret .= $class->end_form;

    if ($submitted) {
        $ret .= "Submitted!";
    }

    return $ret;
}

sub handle_post {
    my $class = shift;
    my $post = shift;
    my %opts = @_;

    if ($post->{text}) {
        warn "You entered: $post->{text}\n";
    }

    return;
}

sub js {
    q [
        initWidget: function () {
            var self = this;

            DOM.addEventListener($("ajax_form"), "submit", function (evt) { self.warnWord(evt, $("ajax_form")) });
        },
        warnWord: function (evt, form) {
            var given_text = form["Widget[ExampleAjaxWidget]_text"].value + "";

            this.doPostAndUpdateContent({
                text: given_text,
                submitted: 1
            });

            Event.stop(evt);
        },
        onRefresh: function (data) {
            this.initWidget();
        }
    ];
}

1;
