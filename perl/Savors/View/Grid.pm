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

package Savors::View::Grid;

use Savors::FatPack::PAL;

use strict;
use List::Util qw(min);
use POSIX;
use Tie::IxHash;
use Tk;

use base qw(Savors::View);

our $VERSION = 2.2;

#############
#### new ####
#############
sub new {
    my $proto = shift;
    my $class = ref $proto || $proto;
    my $self = $class->SUPER::new(@_, "lines=i,swap=s");
    return undef if (!defined $self);
    bless($self, $class);

    $self->{counts} = {};
    tie(%{$self->{counts}}, 'Tie::IxHash');
    $self->{dopts}->{lines} = 20;
    $self->{dopts}->{type} = "heat";
    $self->{dopts}->{period} = $self->getopt('type') eq 'heat' ? 0 : 1;
    $self->{swap_eval} = $self->eval($self->getopt('swap'));
    $self->{time} = 0;

    return $self;
}

##############
#### bbox ####
##############
sub bbox {
    my $self = shift;
    $self->init;
    $self->view(1);
}

##############
#### help ####
##############
sub help {
    my $brief = shift;
    if ($brief) {
        "     grid - gridded plots           " .
            "    grid --color=fD --fields=f22+f23 --label=fV --max=125\n";
    } else {
        "USAGE: env OPT=VAL... (ARGS... |...) |grid --opt=val...\n\n" .
        "TYPES: graph,heat,set\n\n" .
        "OPTIONS:                                          EXAMPLES:\n" .
        "      --ctype=CTYPE - method to assign colors by  " .
            "    --ctype=hash:ord\n" .
        "     --fields=EVALS - expressions to plot         " .
            "    --fields=f4-f123\n" .
        "       --label=EVAL - expression to label by      " .
            "    --label=fD\n" .
        "    --legend[=SIZE] - show color legend           \n" .
        "                        [REAL width or INT pixels]" .
            "    --legend=0.2\n" .
        "    --legend-pt=INT - legend font point size      " .
            "    --legend-pt=12\n" .
        "        --lines=INT - number of periods to show   " .
            "    --lines=20\n" .
        "        --max=REALS - max value of each field     " .
            "    --max=100,10,50\n" .
        "        --min=REALS - min value of each field     " .
            "    --min=50,0,10\n" .
        "      --period=REAL - time between updates        " .
            "    --period=15\n" .
        "        --swap=EVAL - condition to reverse edge   " .
            "    --swap='f5>10000'\n" .
        "     --title=STRING - title of view               " .
            "    --title=\"CPU Usage\"\n" .
        "        --type=TYPE - type of grid                " .
            "    --type=set\n" .
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
    } else {
        $self->{canvas}->delete('!legend');
        $self->{canvas}->move('legend', $self->{width} - $oldx, 0);
    }
    $self->title if ($self->getopt('title'));

    if ($self->getopt('type') eq 'heat') {
        $self->{hsize} = int($self->{width} / ($self->getopt('lines') + 1));
        $self->{label_eval} = $self->eval($self->getopt('label'));
        $self->{line} = 0;
    }
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
    if ($self->getopt('type') ne 'heat') {
        my $time = int($self->time($data));
        if ($self->getopt('period') == 0 ||
                $time >= $self->{time} + $self->getopt('period')) {
            $self->view if ($raised);
            $self->{time} = $time;
            $self->{counts} = {};
        }
    }

    if ($self->getopt('type') eq 'graph') {
        my @fields = map {eval} @{$self->{field_evals}};
        my @fields = map {s/,//g; $_} @fields;
        my $src = shift @fields;
        my $color = $self->color($data);
        my $swap = $self->{swap_eval} && eval $self->{swap_eval};
        foreach (@fields) {
            my @edge = ($src, $_);
            @edge = reverse @edge if ($swap);
            $self->{counts}->{join(",", @edge)} = $color;
        }
    } elsif ($self->getopt('type') eq 'heat') {
        if ($self->{label_eval}) {
            my $key = eval $self->{label_eval};
            my @fields = map {eval} @{$self->{field_evals}};
            if (scalar(@fields) == 1) {
                $self->{counts}->{$key} += $fields[0];
            } else {
                my @labels = map {$self->label($_)} @{$self->{fields0}};
                for (my $i = 0; $i < scalar(@fields); $i++) {
                    $self->{counts}->{$key . ":". $labels[$i]} += $fields[$i];
                }
            }
        } else {
            my @fields = map {eval} @{$self->{field_evals}};
            if (scalar(@{$self->{fields0}}) < scalar(@fields)) {
                my $l = scalar(@{$data});
                $self->{fields0} = [map {
                    if (/f(\d+)-fL/) {
                        map {"f$_"} ($1..$l);
                    } else {
                        $_;
                    }} @{$self->{fields0}}];
            }
            for (my $i = 0; $i < scalar(@fields); $i++) {
                my $label = $self->label($self->{fields0}->[$i]);
                $self->{counts}->{$label} += $fields[$i];
            }
        }
    } elsif ($self->getopt('type') eq 'set') {
        my @fields = map {eval} @{$self->{field_evals}};
        my @fields = map {s/,//g; $_} @fields;
        my $row = shift @fields;
        my $count = !$self->{color_eval} ? 1 : eval $self->{color_eval};
        $self->{counts}->{"$row,$_"} += $count foreach (@fields);
    }

    if ($self->getopt('type') eq 'heat') {
        my $time = int($self->time($data));
        if ($self->getopt('period') == 0 ||
                $time >= $self->{time} + $self->getopt('period')) {
            # set time immediately as it is used in view
            $self->{time} = $time;
            $self->view if ($raised);
            $self->{counts}->{$_} = 0 foreach (keys %{$self->{counts}});
            $self->{line} = ($self->{line} + 1) % $self->getopt('lines');
        }
    }
}

##############
#### view ####
##############
sub view {
    my $self = shift;
    my $bbox = shift;
    if ($self->getopt('type') eq 'heat') {
        $self->view_heat($bbox);
    } else {
        $self->view_static;
    }
}

###################
#### view_heat ####
###################
sub view_heat {
    my $self = shift;
    my $bbox = shift;

#TODO: use extra space below and to the right for labels
    if ($bbox || $self->{ncounts} != scalar(keys %{$self->{counts}})) {
        $self->{ncounts} = scalar(keys %{$self->{counts}});
        $self->{canvas}->delete('labels');
        $self->{vsize} = int($self->{height} / ($self->{ncounts} + 1));
        my $i = 0;
        foreach my $label (keys %{$self->{counts}}) {
            my $size = int(sqrt($self->{hsize} * $self->{vsize} /
                (length($label) + $label =~ tr/ / /)));
            $size = min($size, $self->{hsize}, $self->{vsize});
            $self->{canvas}->createText(
                1 + $self->{hsize}, 1 + ($i + 1.5) * $self->{vsize},
                -anchor => 'e',
                -fill => 'white',
                -font => "courier -$size bold",
                -tags => "labels",
                -text => $label,
                -width => $self->{hsize},
            );
            $i++;
        }
    }

    $self->{canvas}->delete("l" . $self->{line});
    $self->{canvas}->delete("scan");

    my $i = 0;
    my @min = split(/,/, $self->getopt('min'));
    my @max = split(/,/, $self->getopt('max'));
    foreach my $count (values %{$self->{counts}}) {
        my $min = defined $min[$i] ? $min[$i] : $min[0];
        my $max = defined $max[$i] ? $max[$i] : $max[0];
        my $val = ($count - $min) / $max;
        $val = 1 if ($val > 1);
        $val = 0 if ($val < 0);
        my $color = $self->color_heat($val);
        my $scan = int(255 * $val);
        $scan = 255 if ($scan > 255);
        $self->{canvas}->createRectangle(
            1 + ($self->{line} + 1) * $self->{hsize},
            1 + ($i + 1) * $self->{vsize},
            1 + ($self->{line} + 2) * $self->{hsize},
            1 + ($i + 2) * $self->{vsize},
            -fill => $color,
            -tags => "l" . $self->{line},
        );
        $self->{canvas}->createRectangle(
            1 + ($self->{line} + 1) * $self->{hsize},
            1 + ($i + 1) * $self->{vsize},
            1 + ($self->{line} + 2) * $self->{hsize},
            1 + ($i + 2) * $self->{vsize},
            -fill => sprintf("#%02x%02x%02x", $scan, $scan, $scan),
            -tags => "scan",
        );
        $i++;
    }

    my $text = $self->{time} ? strftime('%T', localtime($self->{time})) : " ";
    my $size = int(sqrt($self->{hsize} * $self->{vsize} /
        (length($text) + $text =~ tr/ / /)));
    $size = min($size, $self->{hsize}, $self->{vsize});
    $self->{canvas}->createText(
        1 + ($self->{line} + 1.5) * $self->{hsize}, 1 + $self->{vsize},
        -anchor => 's',
        -fill => 'white',
        -font => "courier -$size bold",
        -text => $text,
        -tags => ["l" . $self->{line}, "labels"],
        -width => $self->{hsize},
    );

    $self->{canvas}->idletasks;
}

#####################
#### view_static ####
#####################
sub view_static {
    my $self = shift;

    $self->{canvas}->delete('!legend');

    my %rows;
    my %cols;
    foreach (keys %{$self->{counts}}) {
        my ($row, $col) = split(/,/);
        $rows{$row} = 1;
        $cols{$col} = 1;
    }

    my $vsize = int($self->{height} / (scalar(keys %rows) + 1));
    my $hsize = int($self->{width} / (scalar(keys %cols) + 1));

    my $i = 0;
    foreach my $text (sort(keys %rows)) {
        # subtract 10% to account for vertical space added by -width
        my $size = int(.9 * sqrt($hsize * $vsize /
            (length($text) + $text =~ tr/ / /)));
        $size = min($size, $hsize, $vsize);
        $self->{canvas}->createText(
            1 + $hsize, 1 + ($i + 1.5) * $vsize,
            -anchor => 'e',
            -fill => 'white',
            -font => "courier -$size bold",
            -text => $text,
            -width => $hsize,
        );
        $i++;
    }

    $i = 0;
    foreach my $text (sort(keys %cols)) {
        # subtract 10% to account for vertical space added by -width
        my $size = int(.9 * sqrt($hsize * $vsize /
            (length($text) + $text =~ tr/ / /)));
        $size = min($size, $hsize, $vsize);
        $self->{canvas}->createText(
            1 + ($i + 1.5) * $hsize, 1 + $vsize,
            -anchor => 's',
            -fill => 'white',
            -font => "courier -$size bold",
            -text => $text,
            -width => $hsize,
        );
        $i++;
    }

    $i = 0;
    foreach my $row (sort(keys %rows)) {
        my $j = -1;
        foreach my $col (sort(keys %cols)) {
            $j++;
            my $val = $self->{counts}->{"$row,$col"};
            next if (!defined $val);
            my $color;
            if ($self->getopt('type') eq 'graph') {
                $color = $val;
            } elsif ($self->getopt('type') eq 'set') {
                $val = ($val - $self->getopt('min')) / $self->getopt('max');
                $val = 1 if ($val > 1);
                $val = 0 if ($val < 0);
                $color = $self->color_heat($val);
            }
            $self->{canvas}->createRectangle(
                1 + ($j + 1) * $hsize, 1 + ($i + 1) * $vsize,
                1 + ($j + 2) * $hsize, 1 + ($i + 2) * $vsize,
                -fill => $color,
            );
        }
        $i++;
    }

    $self->{canvas}->idletasks;
}

1;

