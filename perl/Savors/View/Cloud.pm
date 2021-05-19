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

package Savors::View::Cloud;

use strict;
use File::Spec;
use IPC::Open2;
use MIME::Base64;
use Tk;
use Tk::PNG;

use base qw(Savors::View);

our $VERSION = 2.2;

#############
#### new ####
#############
sub new {
    my $proto = shift;
    my $class = ref $proto || $proto;
    #TODO: implement show
    my $self = $class->SUPER::new(@_, "count=s,font=s,ngram=i,show=s");
    return undef if (!defined $self);
    bless($self, $class);

    $self->{dopts}->{count} = 1;
    $self->{dopts}->{ngram} = 1;
    $self->{dopts}->{period} = 1;

    $self->{count_eval} = $self->eval($self->getopt('count'));
    # taken from Lingua::StopWords::EN
    $self->{swords} = {map {$_ => 1} qw(
		a about above after again against all am an and any are aren't as at be
		because been before being below between both but by can't cannot could
		couldn't did didn't do does doesn't doing don't down during each few for
		from further had hadn't has hasn't have haven't having he he'd he'll
		he's her here here's hers herself him himself his how how's i i'd i'll
		i'm i've if in into is isn't it it's its itself let's me more most
		mustn't my myself no nor not of off on once only or other ought our ours
		ourselves out over own same shan't she she'd she'll she's should
		shouldn't so some such than that that's the their theirs them themselves
		then there there's these they they'd they'll they're they've this those
		through to too under until up very was wasn't we we'd we'll we're we've
		were weren't what what's when when's where where's which while who who's
		whom why why's with won't would wouldn't you you'd you'll you're you've
		your yours yourself yourselves
    )};
    $self->{words} = {};

    return $self;
}

##############
#### bbox ####
##############
sub bbox {
    my $self = shift;
    $self->init;
    $self->view;
}

##############
#### help ####
##############
sub help {
    my $brief = shift;
    if ($brief) {
        "    cloud - word cloud              " .
            "    cloud --color=f12 --fields=f2,f12 --ngram=2 --period=10\n";
    } else {
        "USAGE: env OPT=VAL... (ARGS... |...) |cloud --opt=val...\n\n" .
        "OPTIONS:                                          EXAMPLES:\n" .
        "       --color=EVAL - expression to color by       " .
            "    --color=f12\n" .
        "       --count=EVAL - expression to increment by   " .
            "    --count='f13+f14'\n" .
        "      --ctype=CTYPE - method to assign colors by   " .
            "    --ctype=hash:ord\n" .
        "     --fields=EVALS - expressions denoting words   " .
            "    --fields=f2,f12\n" .
        "        --font=PATH - path to alternate font       " .
            "    --font=/usr/share/fonts/truetype/Vera.ttf\n" .
        "    --legend[=SIZE] - show color legend           \n" .
        "                        [REAL width or INT pixels]" .
            "     --legend=0.2\n" .
        "    --legend-pt=INT - legend font point size       " .
            "    --legend-pt=12\n" .
        "        --ngram=INT - length of word sequences     " .
            "    --ngram=2\n" .
        "      --period=REAL - time between updates         " .
            "    --period=15\n" .
        "     --title=STRING - title of view                " .
            "    --title=\"CPU Usage\"\n" .
        "";
    }
}

##############
#### init ####
##############
sub init {
    my $self = shift;
    my $oldx = $self->{width};
    $self->SUPER::init;

    if (!defined $self->{canvas}) {
        $self->{canvas} = $self->{top}->Canvas(
            -background => 'black',
        )->pack(
            -expand => 1,
            -fill => 'both',
        );
        $self->{photo} = $self->{top}->Photo;
        $self->{canvas}->createImage(1, 1,
            -anchor => 'nw',
            -image => $self->{photo},
        );

        $self->{dopts}->{font} = File::Spec->catfile($self->{conf}->{lib_dir},
            "DejaVuSansCondensed.ttf");
    } else {
        $self->{canvas}->move('legend', $self->{width} - $oldx, 0);
    }
    $self->title if ($self->getopt('title'));
}

##############
#### play ####
##############
sub play {
    my $self = shift;
    my $data = shift;
    my $raised = shift;

    if ($data->[0] eq 'savors_eof') {
        $self->view if ($raised);
        return;
    }
    my $time = int($self->time($data));
    if ($time >= $self->{time} + $self->getopt('period')) {
        $self->view if ($raised && $self->{time} > 0);
        $self->{time} = $time;
        $self->{words} = {};
    }

    my $cfield = $self->color_field($data);
    $self->{words}->{$cfield} = {} if (!$self->{words}->{$cfield});

    my @words = map {eval} @{$self->{field_evals}};
    @words = map {s/^\s*(?!\/)[[:punct:]]*\s*|\s*[[:punct:]]*(?<!\/)\s*$//g; $_} @words;
    @words = grep {!$self->{swords}->{lc $_}} @words;

    my $n = $self->getopt('ngram');
    for (my $i = 0; $i < scalar(@words); $i += $n) {
        my $ngram = join(" ", @words[$i..$i + $n - 1]);
        $self->{words}->{$cfield}->{$ngram} += eval $self->{count_eval};
    }
}

##############
#### view ####
##############
sub view {
    my $self = shift;
    return if (!scalar(keys %{$self->{words}}));

#TODO: show visual error when not installed
    my ($in, $out);
    my $pid = open2($in, $out, File::Spec->catfile($self->{conf}->{lib_dir},
        "cloud", "wordcloud.py"), $self->{width}, $self->{height},
        $self->getopt('font'));

    while (my ($cfield, $words) = each %{$self->{words}}) {
        my $color = substr($self->color(undef, $cfield), 1);
        while (my ($word, $count) = each %{$words}) {
            print $out "$count,$color,$word\n";
        }
    }

    close $out;
    my $image;
    $image .= $_ while (<$in>);
    close $in;
    waitpid($pid, 0);

    $self->{photo}->blank;
    $self->{photo}->put(encode_base64($image));
    $self->{canvas}->idletasks;
}

1;

