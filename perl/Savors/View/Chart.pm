#
# Copyright (C) 2010 United States Government as represented by the
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

package Savors::View::Chart;

use strict;
use MIME::Base64;
use POSIX;
use Tie::IxHash;
use Tk;
use Tk::JPEG;

use base qw(Savors::View);

our $VERSION = 0.21;

#############
#### new ####
#############
sub new {
    my $proto = shift;
    my $class = ref $proto || $proto;
    my $self = $class->SUPER::new(@_,
        "date=s,fields2=s,label2=s,lines=i,splits=i,type2=s");
    return undef if (!defined $self);
    bless($self, $class);

    $self->{counts} = {};
    $self->{counts2} = {};
    tie(%{$self->{counts}}, 'Tie::IxHash');
    tie(%{$self->{counts2}}, 'Tie::IxHash');
    $self->{counts}->{time} = [];
    $self->{count_index} = 0;
    $self->{dopts}->{date} = "%T";
    $self->{dopts}->{period} = 1;
    $self->{dopts}->{splits} = 5;
    $self->{dopts}->{type} = "mountain";
    $self->{dopts}->{type2} = "line";
    $self->{time} = 0;

    $self->{types} = [$self->getopt('type'), $self->getopt('type2')];
    foreach (@{$self->{types}}) {
        $_ = ucfirst(lc($_));
        s/Line/Lines/;
        s/[bB]ar/Bars/;
        s/[pP]oint/Points/;
    }

    $self->{field_evals2} = $self->evals($self->getopt('fields2'), 'fields0_2');
    $self->{dopts}->{color} = undef
        if (scalar(@{$self->{fields0}}) + ($self->{fields0_2} ?
            scalar(@{$self->{fields0_2}}) : 0 ) > 1);
    $self->{color_eval} = $self->eval($self->getopt('color'));
    $self->{module} = "Chart::";
    $self->{module} .= $self->{field_evals2} ? "Composite" : $self->{types}->[0];
    eval "require $self->{module}";

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

###############
#### color ####
###############
# return color of given data based on given field or --color otherwise
sub color {
    my $self = shift;
    my $data = shift;
    my $field = shift;

    my $cfield0 = $self->color_field($data);
    my %cnew;
    my $color;
    foreach my $fields0 (qw(fields0 fields0_2)) {
        next if (!defined $self->{$fields0});
        my @cfields = defined $field ? ($field) : @{$self->{$fields0}};
        foreach my $cfield (@cfields) {
            my $ckey = $cfield;
            if ($cfield0 && !defined $field &&
                    scalar(@{$self->{$fields0}}) == 1) {
                $ckey = $cfield0;
            } elsif (!defined $field) {
                $ckey = $self->label($ckey);
                $ckey = "$cfield0:$ckey" if ($cfield0);
            }
            $color = $self->{colors}->{$ckey};
            if (!defined $color) {
                $color = $self->SUPER::color($data, $ckey);
                $cnew{$ckey} = $color;
            }
        }
    }
    return %cnew if (wantarray);
    return $color;
}

##############
#### help ####
##############
sub help {
    my $brief = shift;
    if ($brief) {
        "    chart - various charts          " .
            "    chart --color=f2 --fields=f3 --type=bar --label=cpu\n";
    } else {
        "USAGE: env OPT=VAL... (ARGS... |...) |chart ...\n\n" .
        "TYPES: bar,direction,errorbar,horizontalbar,line,linepoint," .
        "mountain,pareto,pie,point,split,stackedbar\n\n" .
        "OPTIONS:                                           EXAMPLES:\n" .
        "       --color=EVAL - expression to color by       " .
            "    --color='q(host).fD'\n" .
        "      --ctype=CTYPE - method to assign colors by   " .
            "    --ctype=hash:ord\n" .
        "      --date=STRING - strftime format for time axis" .
            "    --date='%m/%d %T\n" .
        "     --fields=EVALS - expresssions to plot         " .
            "    --fields=f22+f23\n" .
        "    --fields2=EVALS - secondary expressions to plot" .
            "    --fields2=f4-f10\n" .
        "     --label=STRING - label of y axis              " .
            "    --label=Bytes/Sec\n" .
        "    --label2=STRING - label of secondary y axis    " .
            "    --label2=Calls\n" .
        "           --legend - show color legend            " .
            "    --legend\n" .
        "        --lines=INT - number of time lines to show " .
            "    --lines=60\n" .
        "         --max=INTS - max value of each field      " .
            "    --max=100,10,50\n" .
        "         --min=INTS - min value of each field      " .
            "    --min=50,0,10\n" .
        "      --period=REAL - time between updates         " .
            "    --period=15\n" .
        "       --splits=INT - number of splits to plot     " .
            "    --splits=10\n" .
        "     --title=STRING - title of view                " .
            "    --title=\"CPU Usage\"\n" .
        "        --type=TYPE - type of chart                " .
            "    --type=stackedbar\n" .
        "       --type2=TYPE - type of secondary chart      " .
            "    --type2=line\n" .
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
    } else {
        $self->{canvas}->move('legend', $self->{width} - $oldx, 0);
    }
    $self->title if ($self->getopt('title'));

    $self->{lines} = $self->getopt('lines');
    my $ticks = int($self->{width} / 20);
    $ticks /= (scalar(keys %{$self->{counts}}) + 10) / 2
        if ($self->getopt('type') =~ /(?:^|l)bar/i);
    $self->{lines} = $ticks if (!$self->{lines});
    $self->{skip} = int($self->{lines} / $ticks) if ($self->{lines} > $ticks);
    $self->{lines} *= $self->getopt('splits')
        if ($self->getopt('type') eq 'split');
    my $space = length(strftime($self->getopt('date'), localtime)) - 12;
    $self->{space} = $space > 0 ? 1 + 2 * $space : 1;
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
        $self->{counts}->{time}->[$self->{count_index}] = $time;
        $self->{count_index}++;
        $self->view if ($raised && $self->{time} > 0);
        $self->{time} = $time;
        my $splice = $self->{count_index} - $self->{lines};
        $self->{count_index} = $self->{lines} if ($splice > 0);
        foreach my $counts (qw(counts counts2)) {
            foreach (keys(%{$self->{$counts}})) {
                splice(@{$self->{$counts}->{$_}}, 0, $splice) if ($splice > 0);
                $self->{$counts}->{$_}->[$self->{count_index}] = 0;
            }
        }
    }

    my $cfield0 = $self->color_field($data);
    foreach my $fields0 (qw(fields0 fields0_2)) {
        next if (!defined $self->{$fields0});
        my ($counts, $field_evals) = qw(counts field_evals);
        if ($fields0 =~ /2$/) {
            $counts .= "2";
            $field_evals .= "2";
        }
        my $i = 0;
        foreach my $cfield (@{$self->{$fields0}}) {
            my $ckey = $cfield;
            if ($cfield0 && scalar(@{$self->{$fields0}}) == 1) {
                $ckey = $cfield0;
            } else {
                $ckey = $self->label($ckey);
                $ckey = "$cfield0:$ckey" if ($cfield0);
            }
            if (!exists $self->{$counts}->{$ckey}) {
                my $color = $self->color($data, $ckey);
                $color = substr($color, 1);
                my @colors = split(/(..)/, $color);
                @colors = grep(/./, @colors);
                @colors = map(hex, @colors);
                $self->{"color_$fields0"}->{$ckey} = \@colors;
                $self->{$counts}->{$ckey} = [];
                push(@{$self->{$counts}->{$ckey}}, 0) for (1..$self->{count_index});
            }

            $self->{$counts}->{$ckey}->[$self->{count_index}] +=
                eval $self->{$field_evals}->[$i];
            $i++;
        }
    }
}

##############
#### view ####
##############
sub view {
    my $self = shift;
    return if (scalar(keys %{$self->{counts}}) < 2);
    my $chart = $self->{module}->new($self->{width}, $self->{height});
    my @keys = keys(%{$self->{counts}});
    # time is first so remove it
    shift @keys;
    my %datasets;
    foreach (0 .. scalar(@keys) - 1) {
        $datasets{"dataset$_"} = $self->{color_fields0}->{$keys[$_]};
    }
    if ($self->getopt('type') =~ /pie/i) {
        $chart->add_dataset(@keys);
        $chart->add_dataset(map {$self->{counts}->{$_}->[-1]} @keys);
    } else {
        $chart->add_dataset(@{$self->{counts}->{time}});
        $chart->add_dataset(@{$self->{counts}->{$_}}) foreach (@keys);
        if (defined $self->{fields0_2}) {
            my @keys2 = keys(%{$self->{counts2}});
            $chart->add_dataset(@{$self->{counts2}->{$_}}) foreach (@keys2);
            foreach (scalar(@keys) .. scalar(@keys) + scalar(@keys2) - 1) {
                $datasets{"dataset$_"} = $self->{color_fields0_2}->
                    {$keys2[$_ - scalar(@keys)]};
            }
            my $composite = [
                # numbering starts at 1 instead of 0
                [$self->{types}->[0], [1..scalar(@keys)]],
                [$self->{types}->[1],
                    [scalar(@keys) + 1 .. scalar(@keys) + scalar(@keys2)]]
            ];
            $chart->set('composite_info' => $composite);
            my $ylabel2 = $self->getopt('label2');
            $ylabel2 = join(",", map {$self->label($_)} @{$self->{fields0_2}})
                if (!$ylabel2);
            $chart->set("y_label2" => $ylabel2);
        } elsif ($self->getopt('type') eq 'split') {
            $chart->set('brush_size' => 1);
            my $iv = int($self->{lines} / $self->getopt('splits'));
            $chart->set('interval' => $iv);
            $chart->set('interval_ticks' => $iv);
            $chart->set('start' => $self->{counts}->{time}->[0]);
        }
    }
    $chart->set(colors => {
        background => [0, 0, 0],
        misc => [0, 0, 0],
        text => [255, 255, 255],
        x_grid_lines => [255, 255, 255],
        y_grid_lines => [255, 255, 255],
        x_label => [255, 0, 0],
        y_label => [255, 0, 0],
        y_label2 => [255, 0, 0],
        %datasets,
    });
    $chart->set(graph_border => 1);
    $chart->set(grey_background => 0);
    $chart->set(legend => 'none');
    $chart->set(png_border => 1);
    $chart->set(text_space => $self->{space});
    $chart->set(x_ticks => 'vertical');
    my ($x, $y) = ("x", "y");
    ($x, $y) = ("y", "x") if ($self->getopt('type') =~ /horizontal/i);
    $chart->set($x . "_label" => 'Time');
    my $ylabel = $self->getopt('label');
    $ylabel = join(",", map {$self->label($_)} @{$self->{fields0}})
        if (!$ylabel);
    $chart->set($y . "_label" => $ylabel);
    $chart->set("skip_${x}_ticks" => $self->{skip});
    $chart->set("f_$x" . "_tick" =>
        sub {return strftime($self->getopt('date'), localtime($_[0]))});
    $chart->set("f_$y" . "_tick" => sub {return sprintf('%.2g', $_[0])});
    my ($fh, $image);
    open($fh, ">", \$image);
    $chart->jpeg($fh);
    close $fh;
    $self->{photo}->blank;
    $self->{photo}->put(encode_base64($image));
    $self->{photo}->idletasks;
}

1;

