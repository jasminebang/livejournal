#!/usr/bin/perl
#

package Apache::BML;

use strict;
use Apache::Constants qw(:common REDIRECT);
use Apache::File ();
use CGI;
use Data::Dumper;

my $config;     # loaded once
my $cur_req;    # current request hash
my $ML_GETTER;  # normally undef
my %HOOK;
my %langs;      # iso639-2 2-letter lang code -> BML lang code
my (%FileModTime, %FileBlockData, %FileBlockFlags);

sub handler
{
    my $r = shift;
    my $file = $r->filename;

    unless (-e $r->finfo) {
        $r->log_error("File does not exist: $file");
        return NOT_FOUND;
    }

    unless (-r _) {
        $r->log_error("File permissions deny access: $file");
        return FORBIDDEN;
    }
    
    unless ($config) {
        my $conf_file = $r->server_root_relative($r->dir_config("BMLConfig"));
        unless (-e $conf_file) {
            $r->log_error("Couldn't open BMLConf file: $conf_file");
            return FORBIDDEN;
        }
        my $ret = load_config($r, $conf_file);
        return $ret unless $ret == OK;
    }
   
    my $modtime = (stat _)[9];

    my $fh;
    unless ($fh = Apache::File->new($file)) {
        $r->log_error("Couldn't open $file for reading: $!");
        return SERVER_ERROR;
    }

    # create new request
    my $req = $cur_req = {
        'r' => $r,
        'BlockStack' => [""],
    };

    ### read the data to mangle
    my $bmlsource = "";
    while (<$fh>) { $bmlsource .= $_; }
    $fh->close();

    # setup env
    my $uri = $r->uri;
    foreach my $dir (sort { $config->{$a}->{'_size'} <=>
                            $config->{$b}->{'_size'} } keys %$config)
    {
        next unless $uri =~ /^$dir/;
        foreach (keys %{$config->{$dir}}) {
            $req->{'env'}->{$_} = $config->{$dir}->{$_};
        }
    }

    my %GETVARS;
    my $query_string = BML::get_query_string();
    split_vars(\$query_string, \%GETVARS);

    my $ideal_scheme = "";
    if ($ENV{'HTTP_USER_AGENT'} =~ /^Lynx\//) {
        $ideal_scheme = "lynx";
    }

    $req->{'scheme'} = $req->{'env'}->{'ForceScheme'} || 
        $BMLClient::COOKIE{'BMLschemepref'} || 
        $GETVARS{'usescheme'} || 
        $ideal_scheme ||
        $req->{'env'}->{'DefaultScheme'};

    if ($req->{'env'}->{'VarInitScript'}) {
        my $err;
        foreach my $is (split(/\s*,\s*/, $req->{'env'}->{'VarInitScript'})) {
            last unless load_look_from_initscript($req, $is, \$err);
        }
        if ($err) {
            print "Content-type: text/html\n\n";
            print "<b>Error loading VarInitScript:</b><br />\n$err";
            return 0;
        }
    }
    
    if ($HOOK{'startup'}) {
        eval {
            $HOOK{'startup'}->();
        };
        if ($@) {
            print "Content-type: text/html\n\n";
            print "<b>Error running startup hook:</b><br />\n$@";
            return 0;
        }
    }
    
    load_look($req, "", "global");
    load_look($req, $req->{'scheme'}, "generic");
    
    note_mod_time($req, $modtime);

    ## begin the multi-lang stuff
    delete $GETVARS{'uselang'} unless $GETVARS{'uselang'} =~ /^\w{2,10}$/;
    $req->{'lang'} = $GETVARS{'uselang'};
    if (! $req->{'lang'} && $BMLClient::COOKIE{'langpref'} =~ m!^(\w{2,10})/(\d+)$!) {
        $req->{'lang'} = $1;
        # make sure the document says it was changed at least as new as when
        # the user last set their current language, else their browser might
        # show a cached (wrong language) version.
        note_mod_time($req, $2);
    }

    # time to guess!
    unless ($req->{'lang'})
    {
        my %lang_weight = ();
        my @langs = split(/\s*,\s*/, lc($ENV{'HTTP_ACCEPT_LANGUAGE'}));
        my $winner_weight = 0.0;
        foreach (@langs)
        {
            # do something smarter in future.  for now, ditch country code:
            s/-\w+//;
            
            if (/(.+);q=(.+)/) {
                $lang_weight{$1} = $2;
            } else {
                $lang_weight{$_} = 1.0;
            }
            if ($lang_weight{$_} > $winner_weight && defined $langs{$_}) {
                $winner_weight = $lang_weight{$_};
                $req->{'lang'} = $langs{$_};
            }
        }
    }
    $req->{'lang'} ||= $req->{'env'}->{'DefaultLanguage'} || "en";

    # TODO: tie this
    %BMLCodeBlock::FORM = ();
    
    # print on the HTTP header
    my $html;
    bml_decode($req, \$bmlsource, \$html, { DO_CODE => $req->{'env'}->{'AllowCode'} });

    # insert all client (per-user, cookie-set) variables
    if ($req->{'env'}->{'UseBmlSession'}) {
        $html =~ s/%%c\!(\w+)%%/BML::ehtml(BMLClient::get_var($1))/eg;
    }

    my $rootlang = substr($req->{'lang'}, 0, 2);
    unless ($req->{'env'}->{'NoHeaders'}) {
        $r->header_out("Content-Language", $rootlang);
    }

    my $modtime = modified_time($req);
    my $notmod = 0;

    my $content_type = $req->{'content_type'} ||
        $req->{'env'}->{'DefaultContentType'} ||
        "text/html";

    unless ($req->{'env'}->{'NoHeaders'}) 
    {
        if ($ENV{'HTTP_IF_MODIFIED_SINCE'} &&
            ! $req->{'env'}->{'NoCache'} &&
            $ENV{'HTTP_IF_MODIFIED_SINCE'} eq $modtime) 
        {
            print "Status: 304 Not Modified\n";
            $notmod = 1;
        }

        $r->header_out("Content-type", $content_type);
        
        $r->header_out("Cache-Control", "no-cache")
            if $req->{'env'}->{'NoCache'};
        $r->header_out("Last-Modified", modified_time($req))
            if $req->{'env'}->{'Static'};
        $r->header_out("Cache-Control", "private, proxy-revalidate");
        $r->header_out("ETag", Digest::MD5::md5_hex($html));
        $r->send_http_header();
    }
    
    $r->print($html) unless $req->{'env'}->{'NoContent'};
    return OK;
}

sub load_config
{
    my $r = shift;
    my $conf_file = shift;

    my ($currentpath, $var, $val);

    my $cfg = Apache::File->new($conf_file);
    unless ($cfg) {
        $r->log_error("Couldn't open BML config ($conf_file) for reading: $!");
        return SERVER_ERROR;
    }

    $config = {};
    while (my $line = <$cfg>)
    {
        chomp $line;
        next if $line =~ /^\#/;
        if (($var, $val) = ($line =~ /^(\w+):?\s*(.*)/))
        {
            if ($var eq "Location") {
                $currentpath = $val;
            } else {
                # expand environment variables
                $val =~ s/\$(\w+)/$ENV{$1}/g;
                $config->{$currentpath}->{$var} = $val;
            }
        }
    }
    $cfg->close;

    grep { $config->{$_}->{'_size'} = length($_);  } keys %$config;
    
    return OK;
}

sub reset_codeblock
{
    no strict;
    local $^W = 0;
    my $package = "main::BMLCodeBlock::";
    *stab = *{"main::"};
    while ($package =~ /(\w+?::)/g)
    {
        *stab = ${stab}{$1};
    }
    while (my ($key,$val) = each(%stab))
    {
        return if $DB::signal;
        deleteglob ($key, $val);
    }
}

sub deleteglob
{
    no strict;
    return if $DB::signal;
    my ($key, $val, $all) = @_;
    local(*entry) = $val;
    my $fileno;
    if ($key !~ /^_</ and defined $entry)
    {
        undef $entry;
    }
    if ($key !~ /^_</ and defined @entry)
    {
        undef @entry;
    }
    if ($key ne "main::" && $key ne "DB::" && defined %entry
        && $key !~ /::$/
        && $key !~ /^_</ && !($package eq "dumpvar" and $key eq "stab"))
    {
        undef %entry;
    }
    if (defined ($fileno = fileno(*entry))) {
        # do nothing to filehandles?
    }
    if ($all) {
        if (defined &entry) {
                # do nothing to subs?
        }
    }
}

# $type - "THINGER" in the case of (=THINGER Whatever THINGER=)
# $data - "Whatever" in the case of (=THINGER Whatever THINGER=)
# $option_ref - hash ref to %BMLEnv
sub bml_block
{
    my ($req, $type, $data) = @_;
    my $option_ref = $req->{'env'};
    my $realtype = $type;
    my $previous_block = $req->{'BlockStack'}->[-1];

    if (defined $req->{'blockdata'}->{"$type/FOLLOW_${previous_block}"}) {
        $realtype = "$type/FOLLOW_${previous_block}";
    }
    
    my $blockflags = $req->{'blockflags'}->{$realtype};

    # trim off space from both sides of text data
    $data =~ s/^\s+//;
    $data =~ s/\s+$//;
    
    # executable perl code blocks
    if ($type eq "_CODE")
    {
        return inline_error("_CODE block failed to execute by permission settings")
            unless $option_ref->{'DO_CODE'};

        my $ret = (eval("{\n package BMLCodeBlock; \n $data\n }\n"))[0];
        if ($@) { return "<B>[Error: $@]</B>"; }
    
        my $newhtml;
        bml_decode($req, \$ret, \$newhtml, {});  # no opts on purpose: _CODE can't return _CODE
        return $newhtml;
    }

    # load in the properties defined in the data
    my %element = ();
    my @elements = ();
    if ($blockflags =~ /F/ || $type eq "_INFO" || $type eq "_INCLUDE")
    {
        load_elements(\%element, $data, { 'declorder' => \@elements });
    } 
    elsif ($blockflags =~ /P/)
    {
        my @itm = split(/\s*\|\s*/, $data);
        my $ct = 0;
        foreach (@itm) {
            $ct++;
            $element{"DATA$ct"} = $_;
            push @elements, "DATA$ct";
        }
    }
    else
    {
        # single argument block (goes into DATA element)
        $element{'DATA'} = $data;
        push @elements, 'DATA';
    }
    
    # multi-linguality stuff
    if ($type eq "_ML")
    {
        my ($code, $args);
        my $args_present = 0;
        if ($data =~ /^(.+?)(\?(.*))?$/) {
            ($code, $args) = ($1, $3);
            $args_present = !!$2;
        }
        $code = "$ENV{'PATH_INFO'}$code"
            if $code =~ /^\./;

        return "[ml_getter not defined]" unless $ML_GETTER;
        return $ML_GETTER->($req->{'lang'}, $code);
    }
        
    # an _INFO block contains special internal information, like which
    # look files to include
    if ($type eq "_INFO")
    {
        foreach (split(/\s*\,\s*/, trim($element{'INCLUDE'}))) {
            load_look($req, $req->{'scheme'}, $_);
        }
        if ($element{'NOCACHE'}) { $req->{'env'}->{'NoCache'} = 1; }
        if ($element{'STATIC'}) { $req->{'env'}->{'Static'} = 1; }
        if ($element{'NOHEADERS'}) { $req->{'env'}->{'NoHeaders'} = 1; }
        if ($element{'NOCONTENT'}) { $req->{'env'}->{'NoContent'} = 1; }
#        if ($element{'NOFORMREAD'}) { $FORM_READ = 1; } # don't step on CGI.pm, if used
        if ($element{'LOCALBLOCKS'} && $req->{'env'}->{'AllowCode'}) {
            my (%localblock, %localflags);
            load_elements(\%localblock, $element{'LOCALBLOCKS'});
            # look for template types
            foreach my $k (keys %localblock) {
                if ($localblock{$k} =~ s/^\{([A-Za-z]+)\}//) {
                    $localflags{$k} = $1;
                }
            }
            my @expandconstants;
            foreach my $k (keys %localblock) {
                $req->{'blockdata'}->{$k} = $localblock{$k};
                $req->{'blockflags'}->{$k} = $localflags{$k};
                if ($localflags{$k} =~ /s/) { push @expandconstants, $k; }
            }
            foreach my $k (@expandconstants) {
                $req->{'blockdata'}->{$k} =~ s/\(=([A-Z0-9\_]+?)=\)/$req->{'blockdata'}->{$1}/g;
            }
        }
        return "";
    }
    
    if ($type eq "_INCLUDE") 
    {
        my $code = 0;
        $code = 1 if ($element{'CODE'});
        foreach my $sec (qw(CODE BML)) {
            next unless $element{$sec};
            if ($req->{'IncludeStack'} && ! $req->{'IncludeStack'}->[-1]->{$sec}) {
                return inline_error("Sub-include can't turn on $sec if parent include's $sec was off");
            }
        }
        unless ($element{'FILE'} =~ /^[a-zA-Z0-9-_\.]{1,255}$/) {
            return inline_error("Invalid characters in include file name: $element{'FILE'} (code=$code)");
        }

        if ($req->{'IncludeOpen'}->{$element{'FILE'}}++) {
            return inline_error("Recursion detected in includes");
        }
        push @{$req->{'IncludeStack'}}, \%element;
        my $isource = "";
        my $file = $req->{'env'}->{'IncludePath'} . "/" . $element{'FILE'};
        open (INCFILE, $file) || return inline_error("Could not open include file.");
        while (<INCFILE>) { 
            $isource .= $_;
        }
        close INCFILE;
        
        if ($element{'BML'}) {
            my $newhtml;
            bml_decode($req, \$isource, \$newhtml, { DO_CODE => $code });
            $isource = $newhtml;
        } 
        $req->{'IncludeOpen'}->{$element{'FILE'}}--;
        pop @{$req->{'IncludeStack'}};
        return $isource;
    }
    
    if ($type eq "_COMMENT" || $type eq "_C") {
        return "";
    }

    if ($type eq "_EH") {
        return BML::ehtml($element{'DATA'});
    }
    
    if ($type eq "_EB") {
        return BML::ebml($element{'DATA'});
    }
    
    if ($type eq "_EU") {
        return BML::eurl($element{'DATA'});
    }
    
    if ($type eq "_EA") {
        return BML::eall($element{'DATA'});
    }
    
    if ($type =~ /^_/) {
        return inline_error("Unknown core element '$type'");
    }
        
    $req->{'BlockStack'}->[-1] = $type;
        
    # traditional BML Block decoding ... properties of data get inserted
    # into the look definition; then get BMLitized again
    return inline_error("Undefined custom element '$type'")
        unless defined $req->{'blockdata'}->{$realtype};

    my $preparsed = ($blockflags =~ /p/);
        
    if ($preparsed) {
        ## does block request pre-parsing of elements?
        ## this is required for blocks with _CODE and AllowCode set to 0
        foreach my $k (@elements) {
            my $decoded;
            bml_decode($req, \$element{$k}, \$decoded, $option_ref);
            $element{$k} = $decoded;
        }
    }
    
    my $expanded = parsein($req->{'blockdata'}->{$realtype}, \%element);
    
    if ($blockflags =~ /S/) {  # static (don't expand)
        return $expanded;
    } else {
        my $out;
        push @{$req->{'BlockStack'}}, "";
        my $opts = { %{$option_ref} };
        if ($preparsed) {
            $opts->{'DO_CODE'} = $req->{'env'}->{'AllowTemplateCode'};
        }
        bml_decode($req, \$expanded, \$out, $opts);
        pop @{$req->{'BlockStack'}};
        return $out;
    }
}

######## bml_decode
#
# turns BML source into expanded HTML source
#
#   $inref    scalar reference to BML source.  $$inref gets destroyed.
#   $outref   scalar reference to where output is appended.
#   $opts     security flags

sub bml_decode
{
    my ($req, $inref, $outref, $opts) = @_;

    my $block = "";    # what (=BLOCK ... BLOCK=) are we in?
    my $data = "";          # what is (=BLOCK inside BLOCK=) the current block.
    my $depth = 0;     # how many blocks we are deep of the *SAME* type.

  EAT:
    while ($$inref ne "" && ! $req->{'stop_flag'})
    {
        # currently not in a BML tag... looking for one!
        if ($block eq "") {
            if ($$inref =~ s/^(.*?)\(=([A-Z0-9\_]+)\b//s) {
                $$outref .= $1;
                $block = $2;
                $depth = 1;
                next EAT;
            }
            
            # no BML left? append it all and be done.
            $$outref .= $$inref;
            $$inref = "";
            last EAT;
        }
        
        # now we're in a FOO tag: (=FOO
        # things to look out for:
        #   * Increasing depth:
        #      - some text, then another opening (=FOO, increading our depth
        #          (=FOO bla blah (=FOO
        #   * Decreasing depth: (if depth==0, then we're done)
        #      - immediately closing the tag, empty tag
        #          (=FOO=)
        #      - closing the tag (if depth == 0, then we're done)
        #          (=FOO blah blah FOO=)
        
        if ($$inref =~ s/^=\)//) {
            $depth--;
        } elsif ($$inref =~ s/^(.+?)((?:\(=$block\b )|(?:\b$block=\)))//s) {
            $data .= $1;
            if ($2 eq "(=$block") {
                $data .= $2;
                $depth++;
            } elsif ($2 eq "$block=)") {
                $depth--;
                if ($depth) { $data .= $2; }
            }
        } else {
            $$outref .= inline_error("BML block '$block' has no close");
            return;
        }

        # handle finished blocks
        if ($depth == 0) {

            $$outref .= bml_block($req, $block, $data);    
            $data = "";
            $block = "";
        }
    }
}

sub split_vars
{
    my ($dataref, $hashref) = @_;
    
    # Split the name-value pairs
    my $pair;
    my @pairs = split(/&/, $$dataref);
    my ($name, $value);
    foreach $pair (@pairs)
    {
        ($name, $value) = split(/=/, $pair);
        $value =~ tr/+/ /;
        $value =~ s/%([a-fA-F0-9][a-fA-F0-9])/pack("C", hex($1))/eg;
        $name =~ tr/+/ /;
        $name =~ s/%([a-fA-F0-9][a-fA-F0-9])/pack("C", hex($1))/eg;
        $hashref->{$name} .= defined $hashref->{$name} ? "\0$value" : $value;
    }

}

# takes a scalar with %%FIELDS%% mixed in and replaces
# them with their correct values from an anonymous hash, given
# by the second argument to this call
sub parsein
{
    my ($data, $hashref) = @_;
    $data =~ s/%%(\w+)%%/$hashref->{$1}/eg;
    return $data;
}

sub inline_error
{
    return "[Error: <B>@_</B>]";
}

# returns lower-cased, trimmed string
sub trim
{
    my $a = $_[0];
    $a =~ s/^\s+//;
    $a =~ s/\s+$//;
    return $a;
}

sub load_look_from_initscript
{
    my ($req, $file, $errref) = @_;
    my $dummy;
    $errref ||= \$dummy;
    unless (-e $file) {
        $$errref = "Can't find VarInitScript: $file";
        return 0;
    }

    my $modtime;
    if ($req->{'env'}->{'CacheUntilHUP'} && $FileModTime{$file}) {
        $modtime = $FileModTime{$file};
    } else {
        $modtime = (stat($file))[9];
    }
    return 0 unless -e $modtime;

    note_mod_time($req, $modtime);
    if ($modtime > $FileModTime{$file})
    {
        my $init;
        open (IS, $file);
        while (<IS>) {
            $init .= $_;
        }
        close IS;

        $req->{'varinit_file'} = $file;
        eval($init);
        if ($@) {
            $$errref = $@;
            return 0;
        }

        $FileModTime{$file} = $modtime;
    } 
    
    my @expandconstants;
    foreach my $k (keys %{$FileBlockData{$file}}) {
        $req->{'blockdata'}->{$k} = $FileBlockData{$file}->{$k};
        $req->{'blockflags'}->{$k} = $FileBlockFlags{$file}->{$k};
        if ($req->{'blockflags'}->{$k} =~ /s/) { push @expandconstants, $k; }
    }
    foreach my $k (@expandconstants) {
        $req->{'blockdata'}->{$k} =~ s/\(=([A-Z0-9\_]+?)=\)/$req->{'blockdata'}->{$1}/g;
    }
    
    return 1;
}

# given the name of a look file, loads definitions into %look
sub load_look
{
    my ($req, $scheme, $file) = @_;
    return 0 if $scheme =~ /[^a-zA-Z0-9_\-]/;
    return 0 if $file =~ /[^a-zA-Z0-9_\-]/;
    
    my $root = $req->{'env'}->{'LookRoot'};
    $file = $scheme ? "$root/$scheme/$file.look" : "$root/$file.look";
    
    my $modtime;
    if ($req->{'env'}->{'CacheUntilHUP'} && $FileModTime{$file}) {
        $modtime = $FileModTime{$file};
    } else {
        $modtime = (stat($file))[9];
    }
    return 0 unless $modtime;

    note_mod_time($req, $modtime);
    if ($modtime > $FileModTime{$file}) 
    {
        my $look;
        open (LOOK, $file);
        while (<LOOK>) {
            $look .= $_;
        }
        close LOOK;
            
        $FileBlockData{$file} = {};
        load_elements($FileBlockData{$file}, $look);  
        $FileModTime{$file} = $modtime;

        # look for template types
        foreach my $k (keys %{$FileBlockData{$file}}) {
            if ($FileBlockData{$file}->{$k} =~ s/^\{([A-Za-z]+)\}//) {
                $FileBlockFlags{$file}->{$k} = $1;
            }
        }
    } 
    
    my @expandconstants;
    foreach my $k (keys %{$FileBlockData{$file}}) {
        $req->{'blockdata'}->{$k} = $FileBlockData{$file}->{$k};
        $req->{'blockflags'}->{$k} = $FileBlockFlags{$file}->{$k};
        if ($FileBlockFlags{$file}->{$k} =~ /s/) { 
            push @expandconstants, $k; 
        }
    }
    foreach my $k (@expandconstants) {
        $req->{'blockdata'}->{$k} =~ s/\(=([A-Z0-9\_]+?)=\)/$req->{'blockdata'}->{$1}/g;
    }
    
    return 1;
}

# given a block of data, loads elements found into 
sub load_elements
{
    my ($hashref, $data, $opts) = @_;
    my $ol = $opts->{'declorder'};
    my @data = split(/\n/, $data);
    my $curitem = "";
    my $depth;
    
    foreach (@data)
    {
        $_ .= "\n";
        if ($curitem eq "" && /^([A-Z0-9\_\/]+)=>(.*)/)
        {
            $hashref->{$1} = $2;
            push @$ol, $1;
        }
        elsif (/^([A-Z0-9\_\/]+)<=\s*$/)
        {
            if ($curitem eq "")
            {
                $curitem = $1;
                $depth = 1;
                $hashref->{$curitem} = "";
                push @$ol, $curitem;
            }
            else
            {
                if ($curitem eq $1)
                {
                    $depth++;
                }
                $hashref->{$curitem} .= $_;
            }
        }
        elsif ($curitem && /^<=$curitem\s*$/)
        {
            $depth--;
            if ($depth == 0)
            {
                $curitem = "";
            } 
            else
            {
                $hashref->{$curitem} .= $_;
            }
        }
        else
        {
            $hashref->{$curitem} .= $_ if $curitem;
        }
    }
}

# given a file, checks it's modification time and sees if it's
# newer than anything else that compiles into what is the document
sub note_file_mod_time
{
    my ($req, $file) = @_;
    note_mod_time($req, (stat($file))[9]);
}

sub note_mod_time
{
    my ($req, $mod_time) = @_;
    if ($mod_time > $req->{'most_recent_mod'}) { 
        $req->{'most_recent_mod'} = $mod_time; 
    }
}

# formatting
sub modified_time
{
    my $req = shift;
    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = gmtime($req->{'most_recent_mod'});
    my @day = qw{Sun Mon Tue Wed Thu Fri Sat};
    my @month = qw{Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec};
    
    if ($year < 1900) { $year += 1900; }
    
    return sprintf("$day[$wday], %02d $month[$mon] $year %02d:%02d:%02d GMT",
                   $mday, $hour, $min, $sec);
}


package BML;

sub do_later
{
    my $subref = shift;
    return 0 unless ref $subref eq "CODE";
    $Apache::BML::cur_req->{'r'}->register_cleanup($subref);
    return 1;
}

sub register_block
{
    my ($type, $flags, $def) = @_;
    $type = uc($type);

    my $file = $Apache::BML::cur_req->{'varinit_file'};
    $Apache::BML::FileBlockData->{$type} = $def;
    $Apache::BML::FileBlockFlags->{$type} = $flags;
    return 1;
}

sub register_hook
{
    my ($name, $code) = @_;
    $Apache::BML::HOOK{$name} = $code;
}

sub register_ml_getter
{
    my $getter = shift;
    $Apache::BML::ML_GETTER = $getter;
}

sub get_query_string
{
    my $q = $ENV{'QUERY_STRING'} || $ENV{'REDIRECT_QUERY_STRING'};
    if ($q eq "" && $ENV{'REQUEST_URI'} =~ /\?(.+)/) {
        $q = $1;
    }
    return $q;
}

sub http_response
{
    my ($code, $msg) = @_;
    finish_suppress_all();
    # FIXME: pretty lame.  be smart about code & their names & whether or not to send
    # msg or not.
    print "Status: $code\nContent-type: text/html\n\n$msg";
}

sub finish_suppress_all
{
    finish();
    suppress_headers();
    suppress_content();
}

sub suppress_headers
{
    $Apache::BML::cur_req->{'env'}->{'NoHeaders'} = 1;
}

sub suppress_content
{
    $Apache::BML::cur_req->{'env'}->{'NoContent'} = 1;
}

sub finish
{
    $Apache::BML::cur_req->{'env'}->{'stop_flag'} = 1;
}

sub set_content_type
{
    $Apache::BML::cur_req->{'content_type'} = $_[0] if $_[0];
}

sub set_default_content_type
{
    $Apache::BML::cur_req->{'env'}->{'DefaultContentType'} = $_[0];
}

sub eall
{
    return ebml(ehtml($_[0]));
}


# escape html
sub ehtml
{
    my $a = $_[0];
    $a =~ s/\&/&amp;/g;
    $a =~ s/\"/&quot;/g;
    $a =~ s/\'/&\#39;/g;
    $a =~ s/</&lt;/g;
    $a =~ s/>/&gt;/g;
    return $a;	
}

sub ebml
{
    my $a = $_[0];
    $a =~ s/\(=/\(&#0061;/g;
    $a =~ s/=\)/&#0061;\)/g;
    return $a;
}

sub get_language
{
    return $Apache::BML::cur_req->{'lang'};
}

sub get_language_default
{
    return $Apache::BML::cur_req->{'env'}->{'DefaultLanguage'} || "en";
}

sub set_language
{
    $Apache::BML::cur_req->{'lang'} = $_[0];
}

# multi-lang string
sub ml
{
    my ($code, $vars) = @_;
    return "[ml_getter not defined]" unless $Apache::BML::ML_GETTER;
    my $data = $Apache::BML::ML_GETTER->($Apache::BML::cur_req->{'lang'}, $code);
    return $data unless $vars;
    $data =~ s/\[\[(.+?)\]\]/$vars->{$1}/g;
    return $data;
}

sub eurl
{
    my $a = $_[0];
    $a =~ s/([^a-zA-Z0-9_\-.\/\\\: ])/uc sprintf("%%%02x",ord($1))/eg;
    $a =~ tr/ /+/;
    return $a;
}

sub durl
{
    my ($a) = @_;
    $a =~ tr/+/ /;
    $a =~ s/%([a-fA-F0-9][a-fA-F0-9])/pack("C", hex($1))/eg;
    return $a;
}

sub randlist
{
    my @rlist = @_;
    my $size = scalar(@rlist);
    
    my $i;
    for ($i=0; $i<$size; $i++)
    {
        unshift @rlist, splice(@rlist, $i+int(rand()*($size-$i)), 1);
    }
    return @rlist;
}

sub page_newurl
{
    my $page = $_[0];
    my @pair = ();
    foreach (sort grep { $_ ne "page" } keys %BMLCodeBlock::FORM)
    {
        push @pair, (eurl($_) . "=" . eurl($BMLCodeBlock::FORM{$_}));
    }
    push @pair, "page=$page";
    return ($ENV{'PATH_INFO'} . "?" . join("&", @pair));
}

sub paging
{
    my ($listref, $page, $pagesize) = @_;
    $page = 1 unless ($page && $page==int($page));
    my %self;
    
    $self{'itemcount'} = scalar(@{$listref});
    
    $self{'page'} = $page;
    
    $self{'pages'} = $self{'itemcount'} / $pagesize;
    $self{'pages'} = $self{'pages'}==int($self{'pages'}) ? $self{'pages'} : (int($self{'pages'})+1);
    
    $self{'itemfirst'} = $pagesize * ($page-1) + 1;
    $self{'itemlast'} = $self{'pages'}==$page ? $self{'itemcount'} : ($pagesize * $page);
    
    $self{'items'} = [ @{$listref}[($self{'itemfirst'}-1)..($self{'itemlast'}-1)] ];
    
    unless ($page==1) { $self{'backlink'} = "<A HREF=\"" . page_newurl($page-1) . "\">&lt;&lt;&lt;</A>"; }
    unless ($page==$self{'pages'}) { $self{'nextlink'} = "<A HREF=\"" . page_newurl($page+1) . "\">&gt;&gt;&gt;</A>"; }
    
    return %self;
}


1;
