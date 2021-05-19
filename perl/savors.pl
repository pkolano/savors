#!/usr/bin/env perl
#
# Copyright (C) 2010-2021 United States Government as represented by the
# Administrator of the National Aeronautics and Space Administration
# (NASA).  All Rights Reserved.
#
# This software is distributed under the NASA Open Source Agreement
# (NOSA), version 1.3.  The NOSA has been approved by the Open Source
# Initiative.  See http://www.opensource.org/licenses/nasa1.3.php
# for the complete NOSA document.
#
# THE SUBJECT SOFTWARE IS PROVIDED "AS IS" WITHOUT ANY WARRANTY OF ANY
# KIND, EITHER EXPRESSED, IMPLIED, OR STATUTORY, INCLUDING, BUT NOT
# LIMITED TO, ANY WARRANTY THAT THE SUBJECT SOFTWARE WILL CONFORM TO
# SPECIFICATIONS, ANY IMPLIED WARRANTIES OF MERCHANTABILITY, FITNESS FOR
# A PARTICULAR PURPOSE, OR FREEDOM FROM INFRINGEMENT, ANY WARRANTY THAT
# THE SUBJECT SOFTWARE WILL BE ERROR FREE, OR ANY WARRANTY THAT
# DOCUMENTATION, IF PROVIDED, WILL CONFORM TO THE SUBJECT SOFTWARE. THIS
# AGREEMENT DOES NOT, IN ANY MANNER, CONSTITUTE AN ENDORSEMENT BY
# GOVERNMENT AGENCY OR ANY PRIOR RECIPIENT OF ANY RESULTS, RESULTING
# DESIGNS, HARDWARE, SOFTWARE PRODUCTS OR ANY OTHER APPLICATIONS RESULTING
# FROM USE OF THE SUBJECT SOFTWARE.  FURTHER, GOVERNMENT AGENCY DISCLAIMS
# ALL WARRANTIES AND LIABILITIES REGARDING THIRD-PARTY SOFTWARE, IF
# PRESENT IN THE ORIGINAL SOFTWARE, AND DISTRIBUTES IT "AS IS".
#
# RECIPIENT AGREES TO WAIVE ANY AND ALL CLAIMS AGAINST THE UNITED STATES
# GOVERNMENT, ITS CONTRACTORS AND SUBCONTRACTORS, AS WELL AS ANY PRIOR
# RECIPIENT.  IF RECIPIENT'S USE OF THE SUBJECT SOFTWARE RESULTS IN ANY
# LIABILITIES, DEMANDS, DAMAGES, EXPENSES OR LOSSES ARISING FROM SUCH USE,
# INCLUDING ANY DAMAGES FROM PRODUCTS BASED ON, OR RESULTING FROM,
# RECIPIENT'S USE OF THE SUBJECT SOFTWARE, RECIPIENT SHALL INDEMNIFY AND
# HOLD HARMLESS THE UNITED STATES GOVERNMENT, ITS CONTRACTORS AND
# SUBCONTRACTORS, AS WELL AS ANY PRIOR RECIPIENT, TO THE EXTENT PERMITTED
# BY LAW.  RECIPIENT'S SOLE REMEDY FOR ANY SUCH MATTER SHALL BE THE
# IMMEDIATE, UNILATERAL TERMINATION OF THIS AGREEMENT.
#

use Savors::FatPack::PAL;

use strict;
use File::Basename;
use Getopt::Long qw(:config bundling no_ignore_case require_order);
use IO::Socket::INET;
use IO::Socket::UNIX;
use List::Util qw(max);
use MIME::Base64;
use POSIX;
use Storable qw(thaw);
use Text::ParseWords;
use Time::HiRes qw(sleep time);
use Tk;
use Tk::ROTextHighlight;
use Tk::TextHighlight;
require Tk::TextHighlight::Savors;

use Savors::Console::Wall;
use Savors::Console::Layout;
use Savors::Console::Region;
use Savors::Console::Window;
use Savors::Debug;

use sigtrap qw(handler quit error-signals normal-signals);

our $VERSION = 2.2;

my $clipboard = "";
my %conf;
my %defs = (
    anon_key => "",
    font_size => 12,
    frame => 0,
    geometry => "1024x640+400+400",
    green => '#859900',
    lib_dir => "/usr/local/lib",
    passive => 0,
    red => '#dc322f',
    smaxx => 1,
    smaxy => 1,
    snap_file => "savors-snap.ps",
    tcp => 0,
    views => "Axis,Chart,Cloud,Graph,Grid,Map,Rain,Tree",
);
my %opts = (
    conf => $ENV{HOME} . "/.savorsrc",
    gconf => $ENV{SAVORS_HOME} . "/etc/savorsrc",
    theight => 0,
    twidth => 0,
);
# second string conversions
my %seconds = (
    s => 1,
    m => 60,
    h => 60 * 60,
    d => 24 * 60 * 60,
    w => 7 * 24 * 60 * 60,
);
my %servers;
my %snaps;
my %windows;

GetOptions(\%opts,
    "command|c=s", "conf=s", "frame", "geometry=s", "help|h:s", "passive",
    "smaxx=f", "smaxy=f", "snap=s", "snap-file=s", "tcp", "vgeometry=s",
) or die "Invalid options\n";
$opts{snap_file} = $opts{'snap-file'} if ($opts{'snap-file'});

my %help = (
    data =>
        "USAGE: env OPT=VAL... (ARGS... |...) |VIEW --opt=val...\n\n" .
        "OPTIONS:                                                EXAMPLES:\n" .
        "             color=EVAL - expression to color by        " .
            "    color=f19\n" .
        "            ctype=CTYPE - method to assign colors by    " .
            "    ctype=hash:ord\n" .
        "             cut=FIELDS - keep matching fields          " .
            "    cut=f1,f3-f5,f7-fL\n" .
        "           data=STRINGS - create parallel data streams  " .
            "    data=host1,host2\n" .
        "             grep=REGEX - keep matching lines           " .
            "    grep='^\d'\n" .
        "           grep_v=REGEX - discard matching lines        " .
            "    grep_v='^\D'\n" .
        "            host=STRING - host to run data server on    " .
            "    host=host1\n" .
        "    label=STRING|FIELDS - default field labels          " .
            "    label=time,f1-fL\n" .
        "       label_grep=REGEX - line containing labels        " .
            "    label_grep='^PID'\n" .
        "          layout=LAYOUT - layout for view directive     " .
            "    layout=2x2\n" .
        "            repeat=REAL - repeat ARGS every interval    " .
            "    repeat=60\n" .
        "            replay=REAL - replay file ARGS[0] at speed  " .
            "    replay=2\n" .
        "       sed=REGEX/STRING - replace matches with string   " .
            "    sed='\\[\\d+\\]/'\n" .
        "            split=REGEX - field separator               " .
            "    split=','\n" .
        "               sync=INT - synchronization group         " .
            "    sync=99\n" .
        "               tee=FILE - write output to file          " .
            "    tee=/tmp/out\n" .
        "             tee_a=FILE - append output to file         " .
            "    tee_a=/tmp/out\n" .
        "            time=FIELDS - fields representing date/time " .
            "    time=f1-f5\n" .
        "        time_grep=REGEX - line containing time/iteration" .
            "    time_grep='^top'\n" .
        "           view=STRINGS - create multi-view windows     " .
            "    view=1-4\n" .
        "",
#TODO #####################################################
#TODO add (... & ...) data cmd form
#TODO #####################################################
    ex =>
        "USAGE: env OPT=VAL... (ARGS... |...) |VIEW --opt=val...\n\n" .
        "EX-COMMANDS                                 EX-BINDINGS:\n" .
        "         :q - quit savors               " .
            "        BackSpace - remove prev char\n" .
        "    :r NAME - read command from name    " .
            "        Control-c - abort ex mode\n" .
        "    :s FILE - save window canvas to file" .
            "           Escape - abort ex mode\n" .
        "    :S FILE - save layout canvas(es) to file" .
            "          Tab - complete :r name\n" .
        "    :w NAME - store command as name     " .
        "",
    view =>
        "USAGE: env OPT=VAL... (ARGS... |...) |VIEW --opt=val...\n\n" .
        "VIEWS:                                EXAMPLES:\n" .
        "",
    bind =>
        "USAGE: env OPT=VAL... (ARGS... |...) |VIEW --opt=val...\n\n" .
        "BINDINGS:\n" .
        "      BackSpace - left        " .
            "    a/A - append cursor/at end  " .
                "    q/Q - un/focus region (X)\n" .
        "      Control-c - abort view  " .
            "    b/B - back word/non-space   " .
                "    r/R - remove window/layout (X)\n" .
        "         Delete - delete char " .
            "    c/C - create window/layout  " .
                "    s/S - horiz/vert split\n" .
        "           Down - step forward" .
            "    d/D - delete word/to end    " .
                "      t - step time forward\n" .
        "         Escape - escape mode " .
            "    e/E - end word/non-space    " .
                "    u/U - undo/redo\n" .
        "           Left - cursor left " .
            "    h/H - cursor/layout left    " .
                "    w/W - next word/non-space\n" .
        "         Return - execute view" .
            "    i/I - insert cursor/at start" .
                "    x/X - delete char/region\n" .
        "          Right - cursor right" .
            "      j - step forward          " .
                "    y/Y - yank line\n" .
        "     Shift-Down - layout down " .
            "      J - layout down           " .
                "    z/Z - pause window/all\n" .
        "     Shift-Left - layout left " .
            "      k - step back (X)         " .
                "      ] - paste\n" .
        "    Shift-Right - layout right" .
            "      K - layout up             " .
                "      0 - line start\n" .
        "       Shift-Up - layout up   " .
            "    l/L - cursor/layout right   " .
                "      \$ - line end\n" .
        "          Space - cursor right" .
            "    n/N - next window/layout    " .
                "      ^ - line non-space start\n" .
        "             Up - step back (X)" .
            "   p/P - prev window/layout    " .
                "      : - ex mode\n" .
        "",
);
foreach (split(/,/, $defs{views})) {
    eval "require Savors::View::$_";
    $help{lc $_} = eval "Savors::View::$_\::help";
    $help{view} .= eval "Savors::View::$_\::help(1)";
}

if (defined $opts{help}) {
    if ($opts{help}) {
        print $help{$opts{help}}, $help{$opts{help}} =~ /\n$/s ? "" : "\n";
        exit;
    }
    my $base = basename($0);
    print "Usage: $base [OPTION]...\n\n";
    print "Options (defaults in brackets):\n";
    print "  -c, --command=CMD    run command line without console\n";
    print "      --conf=FILE      load config from file [$opts{conf}]\n";
    print "      --frame          show frame on view windows\n";
    print "      --geometry=GEOM  geometry of console window [$defs{geometry}]\n";
    print "  -h, --help[=TOPIC]   help with optional topic one of {bind,data,ex,view\n";
    print "                         " . lc($defs{views}) . "}\n";
    print "      --passive        views wait for data connections instead of vice-versa\n";
    print "      --smaxx=REAL     max fraction of screen width to use for views [$defs{smaxx}]\n";
    print "      --smaxy=REAL     max fraction of screen height to use for views [$defs{smaxy}]\n";
    print "      --snap=PERIOD    take layout snapshot every PERIOD amount of time\n";
    print "                         (use suffix {s,m,h,d,w} for {sec,min,hour,day,week})\n";
    print "      --snap-file=FILE save snapshots to FILE\n";
    print "      --tcp            use TCP sockets instead of Unix sockets\n";
    print "      --vgeometry=GEOM geometry of screen area to use for views\n";
    exit;
}

# parse configuration
foreach ($opts{gconf}, $opts{conf}) {
    if (open(FILE, $_)) {
        my $mline;
        while (my $line = <FILE>) {
            # strip whitespace and comments
            $line =~ s/^\s+|\s+$|^\s*#.*//g;
            next if (!$line);
            # support line continuation operator
            $mline .= $line;
            next if ($mline =~ s/\s*\\$/ /);
            if ($mline =~ /^(\S+)\s+(.*)/) {
                $conf{$1} = $2;
            }
            $mline = undef;
        }
        close FILE;
    }
}

foreach my $key (keys %defs) {
    $opts{$key} = (defined $conf{$key} ? $conf{$key} : $defs{$key})
        if (!defined $opts{$key});
}

if ($opts{snap}) {
    if ($opts{snap} =~ /^([1-9]\d*)([smhdw])?$/i) {
        my ($val, $unit) = ($1, $2);
        $unit = "s" if (!defined $unit);
        $opts{snap} = $val * $seconds{lc $unit};
    } else {
        die "Bad snapshot period $opts{snap}\n";
    }
}

if ($opts{frame}) {
    # compute size of title frame
    my $tmp = MainWindow->new(
        -title => "",
    );
    $tmp->geometry("1x1+0+0");
    $tmp->idletasks;
    $opts{twidth} = $tmp->x;
    $opts{theight} = $tmp->y;
    $tmp->destroy;
}

my $wall = Savors::Console::Wall->new($conf{wall}, $conf{displays});
sub layout {return $wall->current};
sub region {return layout->current};
sub window {return region->current};

my ($top, $canvas, $text, $help_text, $ex, $status, $raw, $legend);

if ($opts{command}) {
    if ($opts{command} =~ /^\s*(\w+)\s*$/) {
        my $name = $1;
        my $command = $conf{"save_$name"};
        die "No saved command named $name\n" if (!$command);
        $opts{command} = $command;
    }
    layout->raise;
    layout->focus;
    $top = MainWindow->new(
        -height => 0,
        -width => 0,
    );
    $top->overrideredirect(1);
    $top->resizable(0, 0);
    $top->withdraw;
    $top->OnDestroy(\&quit);
    &bind(undef, 'Return');
    MainLoop;
} else {
    #####################
    #### main window ####
    #####################
    $top = MainWindow->new(
        -title => "Savors Console",
    );
    # disable resizing until window drawn or else window manager may reduce
    $top->resizable(0, 0);
    $top->geometry($opts{geometry});
    $top->OnDestroy(\&quit);

    ################
    #### frame1 ####
    ################
    my $frame1 = $top->Frame(
    )->pack(
        -expand => 1,
        -fill => 'both',
        -side => 'top',
    );

    $canvas = $frame1->Canvas(
        -background => 'black',
        -borderwidth => 1,
    )->pack(
        -expand => 1,
        -fill => 'both',
        -side => 'left',
    );

    my $frame1r = $frame1->Frame(
    )->pack(
        -expand => 1,
        -fill => 'both',
        -side => 'right',
    );
    $text = $frame1r->TextHighlight(
        -background => 'black',
        -font => "courier -$opts{font_size}",
        -foreground => 'white',
        -height => 3,
        -insertbackground => 'white',
        -matchoptions => [-background => "#dc322f", -foreground => 'white'],
        -syntax => "Savors",
    )->pack(
        -expand => 1,
        -fill => 'both',
        -side => 'top',
    );
    $text->focus;

    $help_text = $frame1r->ROTextHighlight(
        -background => 'black',
        -font => "courier -" . ($opts{font_size} - 2),
        -foreground => 'white',
        -height => 15,
        -insertbackground => 'white',
        -syntax => "Savors",
        -wrap => 'none',
    )->pack(
        -expand => 1,
        -fill => 'both',
        -side => 'bottom',
    );
    $help_text->Contents($help{bind});

    ################
    #### frame2 ####
    ################
    my $frame2 = $top->Frame(
    )->pack(
    #    -expand => 1,
        -fill => 'both',
        -side => 'top',
    );

    $ex = $frame2->Text(
        -background => 'black',
        -font => "courier -$opts{font_size}",
        -foreground => 'white',
        -height => 1,
        -insertbackground => 'white',
    )->pack(
        -expand => 1,
        -fill => 'both',
        -side => 'right',
    );

    $status = $frame2->Canvas(
        -background => 'black',
        -borderwidth => 1,
        -height => 16,
    )->pack(
        -expand => 1,
        -fill => 'both',
        -side => 'left',
    );
    $status->createRectangle(180, 1, 244, 16,
        -fill => $defs{green},
        -state => 'hidden',
        -tags => 'insert',
    );
    $status->createText(188, 8,
        -anchor => 'w',
        -fill => 'black',
        -font => 'courier -12',
        -state => 'hidden',
        -tags => 'insert',
        -text => 'insert',
    );
    $status->createRectangle(244, 1, 308, 16,
        -fill => 'yellow',
        -state => 'hidden',
        -tags => 'pause_one',
    );
    $status->createRectangle(244, 1, 308, 16,
        -fill => $defs{red},
        -state => 'hidden',
        -tags => 'pause_all',
    );
    $status->createText(252, 8,
        -anchor => 'w',
        -fill => 'black',
        -font => 'courier -12',
        -state => 'hidden',
        -tags => 'pause',
        -text => 'pause',
    );

    ################
    #### frame3 ####
    ################
    my $frame3 = $top->Frame(
    )->pack(
    #    -expand => 1,
        -fill => 'both',
        -side => 'top',
    );

    $raw = $frame3->Canvas(
        -background => 'black',
        -borderwidth => 1,
        -height => 16,
    )->pack(
        -expand => 1,
        -fill => 'both',
        -side => 'top',
    );

    ################
    #### frame4 ####
    ################
    my $frame4 = $top->Frame(
    )->pack(
        -expand => 1,
        -fill => 'both',
        -side => 'top',
    );

    $legend = $frame4->Canvas(
        -background => 'black',
        -borderwidth => 1,
        -height => 16 * 8,
    )->pack(
        -expand => 1,
        -fill => 'both',
        -side => 'top',
    );

    # update to get size
    $canvas->idletasks;

    $wall->canvas($canvas);
    $wall->text($text);
    layout->raise;
    layout->focus;

    # remove all default text widget bindings
    $top->bind('Tk::Text', $_, '') foreach ($top->bind('Tk::Text'));
    $top->bind('Tk::TextHighlight', $_, '')
        foreach ($top->bind('Tk::TextHighlight'));
    $top->bind('Tk::ROTextHighlight', $_, '')
        foreach ($top->bind('Tk::ROTextHighlight'));

    # add back useful text widget bindings
    $text->bind('<1>', ['Button1', Ev('x'), Ev('y')]);
    $text->bind('<B1-Motion>', 'B1_Motion');
    $text->bind('<B1-Leave>', 'B1_Leave');
    $text->bind('<B1-Enter>', 'CancelRepeat');
    $text->bind('<ButtonRelease-1>', 'CancelRepeat');
    $text->bind('<Control-1>', ['markSet', 'insert', Ev('@')]);
    $text->bind('<Double-1>', 'selectWord');
    $text->bind('<Triple-1>', 'selectLine');
    $text->bind('<Shift-1>', 'adjustSelect');
    $text->bind('<Double-Shift-1>', ['SelectTo', Ev('@'), 'word']);
    $text->bind('<Triple-Shift-1>', ['SelectTo', Ev('@'), 'line']);
    $text->bind('<2>', ['Button2', Ev('x'), Ev('y')]);
    $text->bind('<B2-Motion>', ['Motion2', Ev('x'), Ev('y')]);
    $text->bind('<ButtonRelease-2>', sub {
        my $xy = $text->XEvent->xy;
        $text->ButtonRelease2;
        my $clip = $text->Contents;
        $clip =~ s/\r?\n//g;
        $text->Contents($clip);
        $text->SetCursor($xy);
    });

    # new text widget bindings
    $text->bind('<Control-c>', [\&bind, 'Control-c']);
    $text->bind('<KeyPress>', [\&bind, Ev('K'), Ev('A')]);
    $text->bind('<Return>', [\&bind, 'Return']);
    $text->bind('<Shift-Down>', [\&bind, 'Shift-Down']);
    $text->bind('<Shift-Left>', [\&bind, 'Shift-Left']);
    $text->bind('<Shift-Right>', [\&bind, 'Shift-Right']);
    $text->bind('<Shift-Up>', [\&bind, 'Shift-Up']);
    $ex->bind('<Control-c>', [\&bind_ex, 'Escape']);
    $ex->bind('<FocusOut>', sub {$ex->Contents("")});
    $ex->bind('<KeyPress>', [\&bind_ex, Ev('K'), Ev('A')]);
    $ex->bind('<Tab>', [\&bind_ex, 'Tab']);

    # allow resizing after window drawn
    $top->resizable(1, 1);

    MainLoop;
}

##############
#### bind ####
##############
sub bind {
    my ($keysym, $char) = ($_[1], $_[2]);
    my $window = window();
    my $window0 = "w$window";
    if ($keysym eq 'Return') {
        return if ($window->run);
        escape();
        my @cmds = quotewords('\|', 1,
            $opts{command} ? $opts{command} : $text->Contents);
        return if (scalar(@cmds) < 2);
        my $vcmd0 = pop @cmds;
        $vcmd0 =~ s/^\s+|\s+$//g;
        # command is escaped from here on
        $opts{command} = uri_escape($opts{command}) if ($opts{command});

        my $vlayout;
        my @vvals;
        my $dcmd0 = join(" | ", @cmds);
        $dcmd0 =~ s/^\s+|\s+$//g;
        my @edargs = quotewords('\s+', 1, $dcmd0);
        for (my $i = 0; $i < scalar(@edargs); $i++) {
            my $edarg = $edargs[$i];
            if ($edarg =~ /^layout=(.*)/) {
                $vlayout = $1;
                $vlayout =~ s/^['"]|['"]$|\s+//g;
                splice(@edargs, $i--, 1);
            }
            if ($edarg =~ /^view=(.*)/) {
                my $view = $1;
                @vvals = quotewords('\s*,\s*', 0, $view);
                for (my $j = 0; $j < scalar(@vvals); $j++) {
                    my $range = $vvals[$j];
                    if ($range =~ /^(\d+)-(\d+)$/) {
                        splice(@vvals, $j, 1, $1 .. $2);
                        $j += $2 - $1;
                    }
                }
                splice(@edargs, $i--, 1);
            }
        }
        @vvals = (undef) if (scalar(@vvals) == 0);
        $dcmd0 = join(" ", @edargs);

        my @dcmds = $dcmd0 =~ /^\(([^\)]+)\)/ ? split(/\s*&\s*/, $1) : ($dcmd0);

        for (my $i = 0; $i < scalar(@dcmds); $i++) {
            my $dcmd = $dcmds[$i];
            if ($dcmd =~ /\s+data=(\S+)\s+/) {
                my @dvals = split(/,/, $1);
                my @pdcmds;
                foreach my $range (@dvals) {
                    my @range = split(/-/, $range);
                    push(@range, $range[0]) if (scalar(@range) == 1);
                    foreach my $dval ($range[0] .. $range[1]) {
                        my $pdcmd = $dcmd;
                        $pdcmd =~ s/\s+data=(\S+)\s+/ data=$dval /;
                        $pdcmd =~ s/fD/$dval/g;
                        push(@pdcmds, $pdcmd);
                    }
                }
                splice(@dcmds, $i, 1, @pdcmds);
                $i += scalar(@dvals) - 1;
            }
        }

        my (@cservers, @vcmds);
        for (my $i = 0; $i < scalar(@vvals); $i++) {
            my $vval = $vvals[$i];
            my @vservers;
            foreach my $dcmd (@dcmds) {
                my $vdcmd = $dcmd;
                $vdcmd =~ s/fV/$vval/g;

                my $server;
                foreach (values %servers, @cservers) {
                    if ($_->{cmd} eq $vdcmd) {
                        $server = $_;
                        last;
                    }
                }
                if (!$server) {
                    $server = {};
                    $server->{cmd} = $vdcmd;
                    $server->{data} = [];
                    $server->{host} =
                        $vdcmd =~ /\s+host=(\S+)\s+/ ? $1 : 'localhost';
                    $server->{sync} = $vdcmd =~ /\s+sync=(\d+)\s+/ ? $1 : 1;
                    $server->{pause} = 0;
                    if ($server->{sync}) {
                        foreach (values %servers) {
                            if ($server->{sync} == $_->{sync}) {
                                $server->{pause} = $_->{pause};
                                last;
                            }
                        }
                    }
                    my $uvdcmd = uri_escape($vdcmd);
                    my $tcp = $opts{tcp} ? " --tcp" : "";
                    my $ssh = $server->{host} ne 'localhost' ?
                        "ssh -Aqx $server->{host} " : "";
                    $server->{addr} =
                        qx(${ssh}savors-data$tcp --cmd='$uvdcmd' 2>/dev/null);
                    $server->{addr} = "$server->{host}:$server->{addr}"
                        if ($opts{tcp});
                }
                push(@vservers, $server);
                push(@cservers, $server);
            }

            my $vcmd = $vcmd0;
            $vcmd =~ s/fV/$vval/g;
            my @vargs = quotewords('\s+', 1, $vcmd);
            my $type = shift @vargs;
            unshift(@vargs, "--conf $_=$opts{$_}")
                foreach (qw(lib_dir anon_key));
            unshift(@vargs, "--");
            foreach (qw(smaxx smaxy)) {
                unshift(@vargs, "--$_=" . $opts{$_});
            }
            unshift(@vargs, "--view=$type");
            unshift(@vargs, "--passive") if ($opts{passive});
            unshift(@vargs, "--tcp") if ($opts{tcp});
            unshift(@vargs, "--vgeometry=$opts{vgeometry}")
                if ($opts{vgeometry});
            if ($opts{frame}) {
                unshift(@vargs, "--frame");
                unshift(@vargs, "--theight=$opts{theight}");
                unshift(@vargs, "--twidth=$opts{twidth}");
            }
            unshift(@vargs, "savors-view");
            push(@vcmds, [join(" ", @vargs), \@vservers]);
        }
        $window->run(\@vcmds, $vlayout);
        $window->update;

        foreach my $server (@cservers) {
            if (!defined $server->{socket}) {
                my $sock;
                if ($opts{tcp}) {
                    $sock = IO::Socket::INET->new(
                        Blocking => 0,
                        PeerAddr => $server->{addr},
                        Proto => 'tcp',
                    );
                } else {
                    $sock = IO::Socket::UNIX->new(
                        Peer => $server->{addr},
                    );
                    $sock->blocking(0);
                }
                sleep 0.1 while (!$sock->connected);
                $server->{socket} = $sock;
                $servers{$sock} = $server;
                $top->fileevent($sock, 'readable', [\&readable, $sock]);
                syswrite($sock, "join console\n");
            }
        }
        my $sockets = $window->send;
        foreach (@{$sockets}) {
            $top->fileevent($_, 'readable', [\&readable, $_]);
            $windows{$_} = $window;
        }
        if ($opts{frame} && !$opts{command}) {
            # keep console focus after spawning window
            $top->bind('<FocusOut>', sub {
                $text->focusForce;
                $top->bind('<FocusOut>', undef);
            });
        }
    } elsif ($keysym eq 'Control-c') {
        quit_window($window);
    } elsif ($keysym eq 'Delete') {
        $text->delete('insert');
    } elsif ($keysym eq 'Escape') {
        escape();
    } elsif ($window->insert) {
        if ($char =~ /[[:print:]]/) {
            $text->InsertKeypress($char);
        } elsif ($keysym eq 'BackSpace') {
            $text->Backspace;
        }
        insert_help();
    } elsif ($char eq 'a') {
        $text->SetCursor($text->index('insert+1c'));
        $window->insert(1);
        $status->itemconfigure('insert', -state, 'normal');
        insert_help();
    } elsif ($char eq 'A') {
        $text->SetCursor($text->index('insert lineend'));
        $window->insert(1);
        $status->itemconfigure('insert', -state, 'normal');
        insert_help();
    } elsif ($char =~ /[bB]/) {
        my $re = $char eq 'b' ? '\W\w' : '\s\S';
        my $word = $text->search(-backwards, -regexp, $re,
            'insert-1c', 'insert linestart');
        if ($word) {
            $text->SetCursor($text->index("$word+1c"));
        } else {
            $text->SetCursor($text->index('insert linestart'));
        }
    } elsif ($char eq 'c') {
        region->create;
    } elsif ($char eq 'C') {
        $wall->create;
    } elsif ($char eq 'd') {
        my $end = $text->search(-regexp, '\s\S', 'insert', 'insert lineend');
        if ($end) {
            $text->delete('insert', "$end+1c");
        } else {
            $text->deleteToEndofLine;
        }
    } elsif ($char eq 'D') {
        $text->deleteToEndofLine;
    } elsif ($char =~ /[eE]/) {
        my $re = $char eq 'e' ? '\w(\W|$)' : '\S(\s|$)';
        my $index = $text->search(-regexp, $re, 'insert+1c', 'insert lineend');
        if ($index) {
            $text->SetCursor($text->index($index));
        } else {
            $text->SetCursor($text->index('insert lineend'));
        }
    } elsif ($char eq 'h' || $keysym eq 'BackSpace' || $keysym eq 'Left') {
        $text->SetCursor($text->index('insert-1c'));
    } elsif ($char eq 'H' || $keysym eq 'Shift-Left') {
        layout->left;
        update();
    } elsif ($char eq 'i') {
        $window->insert(1);
        $status->itemconfigure('insert', -state, 'normal');
        insert_help();
    } elsif ($char eq 'I') {
        $text->SetCursor($text->index('insert linestart'));
        $window->insert(1);
        $status->itemconfigure('insert', -state, 'normal');
        insert_help();
    } elsif ($char eq 'j' || $keysym eq 'Down') {
        # advance all paused servers
        step();
    } elsif ($char eq 'J' || $keysym eq 'Shift-Down') {
        layout->down;
        update();
    } elsif ($char eq 'k' || $keysym eq 'Up') {
        #TODO: step backwards
    } elsif ($char eq 'K' || $keysym eq 'Shift-Up') {
        layout->up;
        update();
    } elsif (($char eq 'l' || $keysym eq 'space' || $keysym eq 'Right') &&
            $text->compare('insert', '<', 'insert lineend')) {
        $text->SetCursor($text->index('insert+1c'));
    } elsif ($char eq 'L' || $keysym eq 'Shift-Right') {
        layout->right;
        update();
    } elsif ($char eq 'n') {
        region->next;
    } elsif ($char eq 'N') {
        $wall->next;
    } elsif ($char eq 'p') {
        region->prev;
    } elsif ($char eq 'P') {
        $wall->prev;
    } elsif ($char eq 'q') {
        #TODO: undo region focus
    } elsif ($char eq 'Q') {
        #TODO: focus on region
    } elsif ($char eq 'r') {
        #TODO: remove window
    } elsif ($char eq 'R') {
        #TODO: remove layout
    } elsif ($char =~ /[sS]/) {
        region->split($char eq 'S' ? 0 : 1);
    } elsif ($char eq 't') {
        # advance all paused servers to next time
        step_time();
    } elsif ($char eq 'u') {
        $text->undo;
    } elsif ($char eq 'U') {
        $text->redo;
    } elsif ($char =~ /[wW]/) {
        my $re = $char eq 'w' ? '\W\w' : '\s\S';
        my $index = $text->search(-regexp, $re, 'insert', 'insert lineend');
        if ($index) {
            $text->SetCursor($text->index("$index+1c"));
        } else {
            $text->SetCursor($text->index('insert lineend'));
        }
    } elsif ($char eq 'x') {
        $text->delete('insert');
    } elsif ($char eq 'X') {
        region->remove;
        # may have more window sockets when region expanded to new display
        my $sockets = window->send;
        $top->fileevent($_, 'readable', [\&readable, $_]) foreach (@{$sockets});
        update();
    } elsif ($char =~ /[yY]/) {
        $clipboard = $text->Contents;
        $clipboard =~ s/^\s+|\s*\|\s*$|\s*$//sg;
        $clipboard =~ s/\n.*//sg if ($char eq 'y');
    } elsif ($char eq 'z') {
        pause($window);
    } elsif ($char eq 'Z') {
        my %pause = map {$_->{pause} => 1} values(%servers);
        my %sync = map {$_->{sync} => 1} values(%servers);
        my $pause = $pause{0} ? 1 : 0;
        # (un-)pause data servers
        $_->{pause} = $pause foreach (values %servers);
        if (!$pause) {
            # advance all sync groups
            step($_) foreach (keys %sync);
        }
        update();
    } elsif ($char eq ']') {
        $text->Insert($clipboard);
    } elsif ($char eq ':') {
        $ex->InsertKeypress($char);
        $ex->focus;
        $help_text->Contents($help{ex});
    } elsif ($char eq '0') {
        $text->SetCursor($text->index('insert linestart'));
    } elsif ($char eq '$') {
        $text->SetCursor($text->index('insert lineend'));
    } elsif ($char eq '^') {
        my $index = $text->search(-regexp, '\S', 'insert linestart');
        $index = 'insert lineend' if (!$index); 
        $text->SetCursor($index);
    }
    $window = "w" . window();
    if ($window0 ne $window) {
        $legend->itemconfigure($window0, -state, 'hidden');
        $legend->itemconfigure($window, -state, 'normal');
        update();
    }
}

#################
#### bind_ex ####
#################
sub bind_ex {
    my ($keysym, $char) = ($_[1], $_[2]);
    if ($keysym eq 'Escape') {
        $ex->Contents("");
        $text->focus;
        $help_text->Contents($help{bind});
    } elsif ($char =~ /[[:print:]]/) {
        $ex->InsertKeypress($char);
        insert_help_ex();
    } elsif ($keysym eq 'BackSpace') {
        my $index = $ex->index('insert');
        $index =~ s/\d+\.//;
        $ex->Backspace if ($index > 1);
        if ($index == 1 && !$ex->get('insert', 'insert lineend')) {
            $ex->Contents("");
            $text->focus;
            $help_text->Contents($help{bind});
        } else {
            insert_help_ex();
        }
    } elsif ($keysym eq 'Return') {
        my $cmd = $ex->Contents;
        $cmd =~ s/^:\s*|\s*$//g;
        if ($cmd =~ /^q!?/) {
            quit();
        } elsif ($cmd =~ /^r\s+(\w+)/) {
            my $name = $1;
            my $save = $conf{"save_$name"};
            $text->insert('insert', $save) if ($save);
            $ex->Contents("");
            $text->focus;
        } elsif ($cmd =~ /^s\s+(\S.*)/) {
            my $file = $1;
            my $window = window();
            $window->save($file);
            $ex->Contents("");
            $text->focus;
        } elsif ($cmd =~ /^S\s+(\S.*)/) {
            my $file = $1;
            my $layout = layout();
            $layout->save($file);
            $ex->Contents("");
            $text->focus;
        } elsif ($cmd =~ /^w\s+(\w+)/) {
            my $name = $1;
            my $save = $text->Contents;
            $save =~ s/\r?\n/ /g;
            $save =~ s/^\s*|\s*$//g;
            $conf{"save_$name"} = $save;
            save_conf();
            $ex->Contents("");
            $text->focus;
        }
        $help_text->Contents($help{bind});
    } elsif ($keysym eq 'Tab') {
        my $cmd = $ex->Contents;
        if ($ex->index('insert') == $ex->index('insert lineend') &&
                $cmd =~ /^:r\s+(\w+)/) {
            my $prefix = $1;
            my @saves = grep(/^save_$prefix/, keys %conf);
            @saves = map {s/^save_//; $_} @saves;
            if (scalar(@saves) > 0) {
                my $long = shift @saves;
                for (@saves) {
                    chop $long while (!/^\Q$long/);
                }
                $ex->Contents(":r $long");
                insert_help_ex();
            }
        }
        # prevent focus shifting to next widget
        Tk->break;
    }
}

################
#### escape ####
################
sub escape {
    if (window->insert) {
        $text->SetCursor($text->index('insert-1c'));
        window->insert(0);
        $status->itemconfigure('insert', -state, 'hidden');
        $help_text->Contents($help{bind});
    }
}

#####################
#### insert_help ####
#####################
sub insert_help {
    my $cmd = $text->Contents;
    my $index = $text->index('insert');
    $index =~ s/^\d+\.//;
    my $before = substr($cmd, 0, $index);
    if ($before =~ /\|\s*(axis|chart|cloud|graph|grid|map|rain|tree)/) {
        $help_text->Contents($help{$1});
    } elsif ($before =~ /\|/) {
        $help_text->Contents($help{view});
    } else {
        $help_text->Contents($help{data});
    }
}

########################
#### insert_help_ex ####
########################
sub insert_help_ex {
    my $cmd = $ex->Contents;
    if ($cmd !~ /^:r/) {
        $help_text->Contents($help{ex});
    } else {
        my $prefix = $cmd =~ /^:r\s+(\w+)/ ? $1 : "";
        my $help =
            "USAGE: env OPT=VAL... (ARGS... |...) |VIEW --opt=val...\n\nSAVED VIEWS:\n";
        my @saves = grep(/^save_$prefix/, keys %conf);
        @saves = map {s/^save_//; $_} @saves;
        my $smax = max(map {length} @saves);
        my $cmax = 80 - $smax;
        foreach my $name (sort @saves) {
            $cmd = $conf{"save_$name"};
    #        $cmd = substr($cmd, 0, $cmax) . "..." if (length $cmd > $cmax);
            $help .= " " x (4 + $smax - length($name)) . "$name - $cmd\n";
        }
        $help_text->Contents($help);
    }
}

###############
#### pause ####
###############
sub pause {
    my $window = shift;
        my @servers = values %{$window->server};
        my %pause = map {$_->{pause} => 1} @servers;
        my %sync = map {$_->{sync} => 1} @servers;
        my $pause = $pause{0} ? 1 : 0;
        # (un-)pause window's data servers
        $_->{pause} = $pause foreach (@servers);
        delete $sync{0};
        foreach my $server (@servers) {
            # (un-)pause data servers in same non-zero sync groups
            $server->{pause} = $pause if ($sync{$server->{sync}});
        }
        if (!$pause) {
            # advance all related sync groups
            step($_) foreach (keys %sync);
            foreach my $server (@servers) {
                step($server) if ($server->{sync} == 0);
            }
        }
        update();
}

#################
#### process ####
#################
sub process {
    my $fh = shift;
    my $msg = shift;

    if ($msg =~ /^data\s+(.*)/) {
        my $data = thaw(decode_base64($1));
        my $server = $servers{$fh};
        return if (!$server);
        if ($data->[0] ne 'savors_eof') {
            my $time = $data->[0];
            $time =~ s/:.*//;
            $server->{time} = $time;
        }
        $server->{data}->[0] = $server->{data}->[1];
        $server->{data}->[1] = $data;
        if (!$server->{pause}) {
            # advance oldest server is same sync group
            step($server->{sync});
        }
        update();
    } elsif ($msg =~ /^color\s+(\S+)\s+(.*)/) {
        my ($color, $field) = ($1, $2);
        my %cwindows;
        my $server = $servers{$fh};
        # color data can be sent from both views and servers
        if ($server) {
            foreach my $window (values %windows) {
                my $vservers = $window->server;
                $cwindows{$window} = $window if ($vservers->{$server});
            }
        } else {
            my $window = $windows{$fh};
            $cwindows{$window} = $window;
        }
        foreach my $window (values %cwindows) {
            my $chash = $window->{colors};
            next if ($chash->{$field});
            my $ncolors = scalar(keys %{$chash});
            $chash->{$field} = $color;
            next if ($opts{command});
            my $y_boxes = int($legend->width / 64);
            my $x = $ncolors % $y_boxes;
            my $y = int($ncolors / $y_boxes) % int($legend->height / 16);
            $legend->createRectangle(1 + $x * 64, 1 + $y * 16,
                1 + ($x + 1) * 64, 1 + ($y + 1) * 16,
                -fill => $color,
                -state => $window->{focused} ? 'normal' : 'hidden',
                -tags => "w$window",
            );
            $legend->createText(4 + $x * 64, $y * 16 + 10,
                -anchor => 'w',
                -fill => 'black',
                -font => 'courier -12',
                -state => $window->{focused} ? 'normal' : 'hidden',
                -tags => "w$window",
                -text => substr($field, 0, 8),
            );
        }
    } elsif ($msg =~ /^focus/) {
        return if ($opts{command});
        # a view has gotten the focus
        $text->focusForce;
    } elsif ($msg =~ /^leave(\s+display)?/) {
        my $display = $1;
        # a view/display has died
        if ($display) {
            delete $windows{$fh};
            $top->fileevent($fh, 'readable', '');
        } else {
            my $window = $windows{$fh};
            quit_window($window);
            quit() if ($opts{command});
        }
    } elsif ($msg =~ /^pause/) {
        my $window = $windows{$fh};
        pause($window);
    } elsif ($msg =~ /^save/) {
        my $window = $windows{$fh};
        $window->save($opts{snap_file});
    } elsif ($msg =~ /^server\s+(\S+)/) {
        # passive view needs server connection
        my $addr = $1;
        foreach my $server (values %servers) {
            if ($server->{addr} eq $addr) {
                my $window;
                if ($opts{tcp}) {
                    $window = $fh->peerhost . ":" . $fh->peerport;
                } else {
                    $window = $fh->peerpath;
                }
                syswrite($server->{socket}, "join $window\n");
                last;
            }
        }
    } elsif ($msg =~ /^step_time/) {
        step_time();
    } elsif ($msg =~ /^step/) {
        step();
    }
}

##############
#### quit ####
##############
sub quit {
    $_->send("quit") foreach (values %windows);
    syswrite($_->{socket}, "leave console\n") foreach (values %servers);
    if (!$opts{command}) {
        my $geom = $top->geometry;
        if ($opts{geometry} ne $geom) {
            $conf{geometry} = $geom;
            save_conf();
        }
    }
    _exit(0);
}

#####################
#### quit_window ####
#####################
sub quit_window {
    my $window = shift;
    my $sockets = $window->send;
    my $vservers = $window->server;
    $window->remove;
    foreach (@{$sockets}) {
        delete $windows{$_};
        $top->fileevent($_, 'readable', '');
    }
    $legend->delete("w$window") if (!$opts{command});

    my %step;
    foreach my $server (values %{$vservers}) {
        my $last = 1;
        foreach (values %windows) {
            my $vservers2 = $_->server;
            if ($vservers2->{$server}) {
                $last = 0;
                last;
            }
        }
        if ($last) {
            my $sock = $server->{socket};
            $top->fileevent($sock, 'readable', '');
            syswrite($sock, "leave console\n");
            delete $servers{$sock};
        } else {
            $step{$server->{sync}} = 1 if (!$server->{pause});
        }
    }

    # advance oldest unpaused server in each related sync group
    step($_) foreach(keys %step);
    update();
}

##################
#### readable ####
##################
my $readable_buf;
sub readable {
    my $fh = shift;
    return if (!$fh);
    my ($len, $tmp);
    $readable_buf .= $tmp while ($len = sysread($fh, $tmp, 16384));
    process($fh, $1) while ($readable_buf =~ s/^(.*?)\r?\n//);
}

###################
#### save_conf ####
###################
sub save_conf {
    my $text;
    if (-e $opts{conf}) {
        open(FILE, $opts{conf});
        $text .= $_ while (<FILE>);
        close FILE;
        # save old conf
        rename($opts{conf}, "$opts{conf}~");
    }
    foreach (sort(keys %conf)) {
        if ($text !~ s/^$_\s+.*$/$_ $conf{$_}/m) {
            $text .= "\n" if ($text !~ /\n$/);
            $text .= "$_ $conf{$_}\n";
        }
    }
    open(FILE, '>', $opts{conf});
    print FILE $text;
    close FILE;
}

###################
#### sort_time ####
###################
sub sort_time {
    return 1 if (!defined $a->{time});
    return -1 if (!defined $b->{time});
    return $a->{last} <=> $b->{last} if ($a->{time} == $b->{time});
    return $a->{time} <=> $b->{time};
}

##############
#### step ####
##############
sub step {
    my $group = shift;
    my $time = time;
    if (ref $group) {
        syswrite($group->{socket}, "ready\n");
        $group->{last} = $time;
        return;
    }
    my %step;
    foreach my $server (values %servers) {
        my $sync = $server->{sync};
        $step{$sync} = [] if (!$step{$sync});
        push(@{$step{$sync}}, $server)
            if (!defined $group && $server->{pause} || $sync == $group);
    }
    foreach my $server (@{$step{0}}) {
        # unsynchronized servers in sync group 0 always proceed
        syswrite($server->{socket}, "ready\n");
        $server->{last} = $time;
        $snaps{0} = $server->{time} if (!defined $snaps{0});
        if ($opts{snap} && $server->{time} - $snaps{0} >= $opts{snap}) {
            layout->save($opts{snap_file} . ".s0." . $server->{time} . ".ps");
            $snaps{0} = $server->{time};
        }
    }
    delete $step{0};
    foreach my $key (keys %step) {
        my @order = sort sort_time @{$step{$key}};
        next if ($order[0]->{last} == 1E99);
        if ($order[0]->{data}->[0]->[0] eq 'savors_eof') {
            if ($opts{snap}) {
                # save at eof
                layout->save($opts{snap_file} . ".s$key." . $order[0]->{time} . ".ps");
            }
            $order[0]->{time} = 1E99;
            $order[0]->{last} = 1E99;
        } else {
            $snaps{$key} = $order[0]->{time} if (!defined $snaps{$key});
            if ($opts{snap} && $order[0]->{time} - $snaps{$key} >= $opts{snap}) {
                layout->save($opts{snap_file} . ".s$key." . $order[0]->{time} . ".ps");
                $snaps{$key} = $order[0]->{time};
            }
            $order[0]->{last} = $time;
            syswrite($order[0]->{socket}, "ready\n");
        }
    }
}

###################
#### step_time ####
###################
my $step_time = 0;
sub step_time {
    # prevent multiple instances running simultaneously due to DoOneEvent
    return if ($step_time);
    $step_time = 1;

    my $time0 = 1E99;
    my @step;
    foreach my $server (values %servers) {
        my $sync = $server->{sync};
        if ($server->{pause}) {
            push(@step, $server);
            $time0 = $server->{time} if ($server->{time} < $time0);
        }
    }

    while ($time0 < 1E99) {
        step();
        my $time = 1E99;
        foreach my $server (@step) {
            $time = $server->{time} if ($server->{time} < $time);
        }
        last if ($time > $time0);
        # process Tk events or new server data will never be processed
        DoOneEvent;
    }
    $step_time = 0;
}

################
#### update ####
################
sub update {
    my $vservers = window->server;
    my %pause = map {$_->{pause} => 1} values %{$vservers};
    my $all = $pause{0} || !defined $pause{1} ? 'hidden' : 'normal';
    my $one = $pause{0} && $pause{1} ? 'normal' : 'hidden';
    my $txt = $pause{1} ? 'normal' : 'hidden';
    if (!$opts{command}) {
        $status->itemconfigure('pause_all', -state, $all);
        $status->itemconfigure('pause_one', -state, $one);
        $status->itemconfigure('pause', -state, $txt);
    }

    my %sync = map {$_->{sync} => 1} values %{$vservers};
    delete $sync{0};
    my @group;
    foreach my $server (values %servers) {
        push(@group, $server) if ($sync{$server->{sync}});
    }
    my @order = sort {$b->{last} <=> $a->{last}} @group;
    my $server = $order[0];
    if ($pause{1}) {
        foreach (@order) {
            if ($_->{pause}) {
                $server = $_;
                last;
            }
        }
    }

    my $time = $server->{data}->[0]->[0];
    $time =~ s/:.*//;
    $time = localtime($time) if ($time);

    if (!$opts{command}) {
        $status->delete("time");
        $status->createText(4, 4,
            -anchor => 'nw',
            -fill => 'white',
            -font => 'courier -12',
            -tags => "time",
            -text => $time,
        );

        $raw->delete("l0");
        if ($server->{pause}) {
            my $vars = shift @{$server->{data}->[0]};
            $raw->createText(4, 4,
                -anchor => 'nw',
                #TODO: need to compute color somehow
                #-fill => $color,
                -fill => 'white',
                -font => 'courier -12',
                -tags => "l0",
                -text => join(" ", @{$server->{data}->[0]}),
            );
            unshift(@{$server->{data}->[0]}, $vars);
        }
    }
}

####################
#### uri_escape ####
####################
# return uri-escaped version of given string
sub uri_escape {
    my $text = shift;
    $text =~ s/([^A-Za-z0-9\-\._~\/])/sprintf("%%%02X", ord($1))/eg
        if (defined $text);
    return $text;
}

# This chunk of stuff was generated by App::FatPacker. To find the original
# file's code, look for the end of this BEGIN block or the string 'FATPACK'
BEGIN {
my %fatpacked;

$fatpacked{"Tk/TextHighlight/Savors.pm"} = '#line '.(1+__LINE__).' "'.__FILE__."\"\n".<<'TK_TEXTHIGHLIGHT_SAVORS';
  package Tk::TextHighlight::Savors;
  
  use strict;
  
  use base qw(Tk::TextHighlight::Template);
  
  our $VERSION = 2.2;
  
  # solarized colors
  my $yellow = "#b58900";
  my $orange = "#cb4b16";
  my $red = "#dc322f";
  my $magenta = "#d33682";
  my $violet = "#6c71c4";
  my $blue = "#268bd2";
  my $cyan = "#2aa198";
  my $green = "#859900";
  
  my %directive = map {$_ => 1}
      qw(color ctype cut data grep grep_v host label label_grep layout OPT repeat
         replay sed split sync tee tee_a time time_grep view);
  
  my %option = map {$_ => 1}
      qw(attr cdefault color count ctype dash date face fields fields2 file
         font grep hex label label2 legend lines max max2 min min2 ngram no-tags
         opt period show size splits swap tags timeout title type type2 xfields
         yfields);
  
  my %view = map {$_ => 1}
      qw(axis chart cloud env graph grid map rain tree VIEW);
  
  sub new {
      my ($proto, $rules) = @_;
      my $class = ref($proto) || $proto;
      if (!defined($rules)) {
          $rules = [
              ['Text'],
              ['Directive', -foreground => $blue],
              ['Field',  -foreground => $violet],
              ['Operator', -foreground => $yellow],
              ['Option', -foreground => $cyan],
              ['String1', -foreground => $red],
              ['String2', -foreground => $red],
              ['Variable',  -foreground => $magenta],
              ['View', -foreground => $green],
          ];
      }
      my $self = $class->SUPER::new($rules);
      bless($self, $class);
      $self->callbacks({
          'Directive' => \&other,
          'Field' => \&other,
          'Operator' => \&other,
          'Option' => \&other,
          'String1' => \&string1,
          'String2' => \&string2,
          'Text' => \&text,
          'Variable' => \&other,
          'View' => \&other,
      });
      $self->stackPush('Text');
      return $self;
  }
  
  sub other {
      my ($self, $text) = @_;
      return $self->parserError($text);
  }
  
  sub string1 {
      my ($self, $text) = @_;
      if ($text =~ s/^(f(L|\d+))(?=\W)//o) {
          $self->snippetParse($1, 'Field');
      } elsif ($text =~ s/^(')//o) {
          $self->snippetParse($1);
          $self->stackPull;
      } elsif ($text =~ s/^([^\w\s])//o) {
          $self->snippetParse($1);
      } elsif ($text =~ s/^([\w\s]+)//o) {
          $self->snippetParse($1);
      } else {
          return $self->parserError($text);
      }
      return $text;
  }
  
  sub string2 {
      my ($self, $text) = @_;
      if ($text =~ s/^(f(L|\d+))(?=\W)//o) {
          $self->snippetParse($1, 'Field');
      } elsif ($text =~ s/^(")//o) {
          $self->snippetParse($1);
          $self->stackPull;
      } elsif ($text =~ s/^([^\w\s])//o) {
          $self->snippetParse($1);
      } elsif ($text =~ s/^([\w\s]+)//o) {
          $self->snippetParse($1);
      } else {
          return $self->parserError($text);
      }
      return $text;
  }
  
  sub text {
      my ($self, $text) = @_;
      if ($text =~ s/^(\s+)//o) {
          $self->snippetParse($1);
      } elsif ($text =~ s/^(')//o) {
          $self->stackPush('String1');
          $self->snippetParse($1);
      } elsif ($text =~ s/^(")//o) {
          $self->stackPush('String2');
          $self->snippetParse($1);
      } elsif ($text =~ s/^(f(L|\d+))(?=\W)//o) {
          $self->snippetParse($1, 'Field');
      } elsif ($text =~ s/^(--)(\w+)(-\w+)?//o) {
          $self->snippetParse($1, 'Operator');
          my $type = $option{"$2$3"} ? 'Option' : undef;
          $self->snippetParse($2, $type);
          if (defined $3) {
              my $s = substr($3, 1);
              $self->snippetParse("-", 'Operator');
              $self->snippetParse($s, $type);
          }
      } elsif ($text =~ s/^([^\w\s])//o) {
          $self->snippetParse($1, 'Operator');
      } elsif ($text =~ s/^(\w*)(f[DV])//o) {
          $self->snippetParse($1) if ($1);
          $self->snippetParse($2, 'Variable');
      } elsif ($text =~ s/^(\w+)//) {
          my $s = $1;
          if ($directive{$s} && $text =~ /^(\=)/) {
              $self->snippetParse($s, 'Directive');
          } elsif ($view{$s} && $text =~ /^\s/) {
              $self->snippetParse($s, 'View');
          } else {
              $self->snippetParse($s);
          }
      } else {
          # should not reach here
          return $self->parserError($text);
      }
      return $text;
  }
  
  # override snippetParse to fix bug in Tk::TextHighlight::Template v0.3
  sub snippetParse {
      my $hlt = shift;
      my $snip = shift;
      my $attr = shift;
      unless (defined($snip)) { $snip = $hlt->snippet }
      unless (defined($attr)) { $attr = $hlt->stackTop }
      my $out = $hlt->{'out'};
      # below was just $snip in original, which fails for string "0"
      if (length($snip)) {
          push(@$out, length($snip), $attr);
          $hlt->snippet('');
      }
  }

  1;
  
TK_TEXTHIGHLIGHT_SAVORS

s/^  //mg for values %fatpacked;

my $class = 'FatPacked::'.(0+\%fatpacked);
no strict 'refs';
*{"${class}::files"} = sub { keys %{$_[0]} };

if ($] < 5.008) {
  *{"${class}::INC"} = sub {
     if (my $fat = $_[0]{$_[1]}) {
       return sub {
         return 0 unless length $fat;
         $fat =~ s/^([^\n]*\n?)//;
         $_ = $1;
         return 1;
       };
     }
     return;
  };
}

else {
  *{"${class}::INC"} = sub {
    if (my $fat = $_[0]{$_[1]}) {
      open my $fh, '<', \$fat
        or die "FatPacker error loading $_[1] (could be a perl installation issue?)";
      return $fh;
    }
    return;
  };
}

unshift @INC, bless \%fatpacked, $class;
  } # END OF FATPACK CODE

