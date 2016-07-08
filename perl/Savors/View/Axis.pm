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

package Savors::View::Axis;

use strict;
use Tk;

use base qw(Savors::View);
use List::Util qw(min);
use Math::Trig qw(pi);

our $VERSION = 0.21;

#############
#### new ####
#############
sub new {
    my $proto = shift;
    my $class = ref $proto || $proto;
    my $self = $class->SUPER::new(@_, "dash=s,lines=i");
    return undef if (!defined $self);
    bless($self, $class);

    delete $self->{dopts}->{max};
    $self->{dopts}->{period} = 0;
    $self->{dopts}->{type} = "parallel";
    $self->{dash_eval} = $self->eval($self->getopt('dash'));

    return $self;
}

##############
#### bbox ####
##############
sub bbox {
    my $self = shift;
    my $fake = shift;
    $self->init if (!$fake);
    $self->init_labels if (!$fake);
    my $i = $self->{copts}->{offset};
    for (0..$self->{lines} - 1) {
        my $data = $self->{copts}->{buffer}->[$i];
        $self->view($data, 1)
            if ($data->[0] ne 'savors_eof' && $self->grep($data));
        $i--;
        last if ($i < 0);
    }
    $self->{canvas}->idletasks;
}

##############
#### help ####
##############
sub help {
    my $brief = shift;
    if ($brief) {
        "     axis - multi-axis relationships" .
            "    axis --color=f19 --fields=f3,f5,f7,f9 --label=si,sp,di,dp\n";
    } else {
        "USAGE: env OPT=VAL... (ARGS... |...) |axis ...\n\n" .
        "TYPES: circle,hive,parallel,star\n\n" .
        "OPTIONS:                                        EXAMPLES:\n" .
        "       --color=EVAL - expression to color by    " .
            "    --color=f19\n" .
        "      --ctype=CTYPE - method to assign colors by" .
            "    --ctype=hash:ord\n" .
        "        --dash=EVAL - condition to dash edge    " .
            "    --dash=\"f21 eq 'out'\"\n" .
        "     --fields=EVALS - expressions to plot       " .
            "    --fields=f3,f5,f7,f9\n" .
        "    --label=STRINGS - labels for axes           " .
            "    --label=sip,sport,dip,dport\n" .
        "           --legend - show color legend         " .
            "    --legend\n" .
        "        --lines=INT - data lines to show        " .
            "    --lines=20\n" .
        "         --max=INTS - max value of each field   " .
            "    --max=100,10,50\n" .
        "         --min=INTS - min value of each field   " .
            "    --min=50,0,10\n" .
        "      --period=REAL - time between updates      " .
            "    --period=3\n" .
        "     --title=STRING - title of view             " .
            "    --title=\"CPU Usage\"\n" .
        "        --type=TYPE - type of plot              " .
            "    --type=hive\n" .
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

    $self->{lines} = $self->getopt('lines');
    $self->{lines} = int($self->{height} / 2) if (!$self->{lines});
    $self->{line} = 0;
    $self->{margin} = 32;
    $self->{ymax} = $self->{height} - $self->{margin};
    
    my $nfields = scalar(@{$self->{field_evals}});
    if ($self->getopt('type') eq 'circle') {
        my $min = min($self->{height}, $self->{width}) - $self->{margin};
        my ($y, $x) = map {int(($self->{$_} - $min) / 2)} qw(height width);
        $self->{radius} = $min / 2;
        $self->{xorg} = $x + $self->{radius};
        $self->{yorg} = $y + $self->{radius};
        $self->{canvas}->createOval(
            $self->{xorg} - $self->{radius}, $self->{yorg} - $self->{radius},
            $self->{xorg} + $self->{radius}, $self->{yorg} + $self->{radius},
            -outline => 'white',
        );
 
        for (my $i = 0; $i < $nfields; $i++) {
            my $angle = pi + $i * 2 * pi / $nfields;
            my $x = $self->{xorg} + $self->{radius} * cos($angle);
            my $y = $self->{yorg} + $self->{radius} * sin($angle);
            $self->{canvas}->createOval(
                $x - 5, $y - 5, $x + 5, $y + 5,
                -fill => 'white',
            );
        }
    } elsif ($self->getopt('type') =~ /^(hive|star)$/) {
        my $min = min($self->{height}, $self->{width}) - $self->{margin};
        my ($y, $x) = map {int(($self->{$_} - $min) / 2)} qw(height width);
        $self->{radius} = $min / 2;
        $self->{xorg} = $x + $self->{radius};
        $self->{yorg} = $y + $self->{radius};
        for (my $i = 0; $i < $nfields; $i++) {
            my $angle = 3 * pi / 2 + $i * 2 * pi / $nfields;
            my $x = $self->{xorg} + $self->{radius} * cos($angle);
            my $y = $self->{yorg} + $self->{radius} * sin($angle);
            $self->{canvas}->createLine(
                $self->{xorg}, $self->{yorg}, $x, $y,
                -fill => 'white',
            );
        }
    } elsif ($self->getopt('type') eq 'parallel') {
        for (my $i = 1; $i < $nfields - 1; $i++) {
            $self->{canvas}->createLine(
                int($self->{width} * $i / ($nfields - 1)),
                1,
                int($self->{width} * $i / ($nfields - 1)),
                $self->{ymax},
                -fill => 'white',
            );
        }
    }
}

#####################
#### init_labels ####
#####################
sub init_labels {
    my $self = shift;

    my @labels = split(/\s*,\s*/, $self->getopt('label'));
    @labels = map {$self->label($_)} @{$self->{fields0}}
        if (scalar(@labels) == 0);
 
    my $nfields = scalar(@labels);
    if ($self->getopt('type') eq 'circle') {
        for (my $i = 0; $i < $nfields; $i++) {
            my $angle = pi + ($i + .5) * 2 * pi / $nfields;
            my $x = $self->{xorg} + $self->{radius} * cos($angle);
            my $y = $self->{yorg} + $self->{radius} * sin($angle);
            my %anchor;
            $anchor{-anchor} .= $y < $self->{yorg} ? 's' : 'n';
            $anchor{-anchor} .= $x < $self->{xorg} ? 'e' : 'w';
            $self->{canvas}->createText(
                $x, $y,
                -fill => 'white',
                -font => 'courier -12',
                -text => $labels[$i],
                %anchor,
            );
        }
    } elsif ($self->getopt('type') =~ /^(hive|star)$/) {
        for (my $i = 0; $i < $nfields; $i++) {
            my $angle = 3 * pi / 2 + $i * 2 * pi / $nfields;
            my $x = $self->{xorg} + $self->{radius} * cos($angle);
            my $y = $self->{yorg} + $self->{radius} * sin($angle);
            my %anchor;
            $anchor{-anchor} .= $y < $self->{yorg} ? 's' : 'n';
            $anchor{-anchor} .= $x < $self->{xorg} ? 'e' : 'w';
            $self->{canvas}->createText(
                $x, $y,
                -fill => 'white',
                -font => 'courier -12',
                -text => $labels[$i],
                %anchor,
            );
        }
    } elsif ($self->getopt('type') eq 'parallel') {
        for (my $i = 0; $i < $nfields; $i++) {
            my %anchor;
            my $x = 0;
            if ($i == 0) {
                $anchor{-anchor} = 'w';
                $x++;
            } elsif ($i == $nfields - 1) {
                $anchor{-anchor} = 'e';
                $x--;
            }
            $self->{canvas}->createText(
                $x + int($self->{width} * $i / ($nfields - 1)),
                $self->{height} - int($self->{margin} / 2),
                -fill => 'white',
                -font => 'courier -12',
                -text => $labels[$i],
                %anchor,
            );
        }
    }
}

##############
#### play ####
##############
sub play {
    my $self = shift;
    my $data = shift;
    my $raised = shift;

    if (!$self->{init_labels}) {
        # by first play, server parsed labels should hopefully exist
        $self->init_labels;
        $self->{init_labels} = 1;
    }

    if ($data->[0] eq 'savors_eof') {
        $self->bbox(1) if ($raised);
    } elsif (!$self->getopt('period')) {
        $self->view($data) if ($raised);
    } else {
        my $time = int($self->time($data));
        if ($time >= $self->{time} + $self->getopt('period')) {
            $self->bbox(1) if ($raised);
            $self->{time} = $time;
        }
    }
}

####################
#### scale_eval ####
####################
sub scale_eval {
    my $self = shift;
    my $data = shift;
    my $ifield = shift;
    my $length = shift;

    my @min = split(/,/, $self->getopt('min'));
    my @max = split(/,/, $self->getopt('max'));
    my $min = defined $min[$ifield] ? $min[$ifield] : $min[0];
    my $max = defined $max[$ifield] ? $max[$ifield] : $max[0];

#TODO: if plotting time fields, then this doesn't put them sequentially
#      along axis as time will be raw instead of parsed unix time value
    my $val = eval $self->{field_evals}->[$ifield];
    $val =~ s/\D*//g if ($val !~ /^[+-]?\ *(\d+(\.\d*)?|\.\d+)([eE][+-]?\d+)?$/);
    $val -= $min;
    if (defined $max) {
        $val = $val / $max;
    } else {
        $val = ($val % $length) / $length;
    }
    $val = 1 if ($val > 1);
    $val = 0 if ($val < 0);
    return $val;
}
 
##############
#### view ####
##############
sub view {
    my $self = shift;
    my $data = shift;
    my $noupdate = shift;

    return if (!defined $data);
    $self->{canvas}->delete("l" . $self->{line});
    my $color = $self->color($data);
    my $extra = {};
    $extra->{-tags} = "l" . $self->{line};
    $extra->{-dash} = '.' if ($self->{dash_eval} && eval $self->{dash_eval});

    if ($self->getopt('type') eq 'circle') {
        $self->view_circle($data, $color, $extra);
    } elsif ($self->getopt('type') eq 'hive') {
        $self->view_hive($data, $color, $extra);
    } elsif ($self->getopt('type') eq 'parallel') {
        $self->view_parallel($data, $color, $extra);
    } elsif ($self->getopt('type') eq 'star') {
        $self->view_star($data, $color, $extra);
    }

    $self->{line} = ($self->{line} + 1) % $self->{lines};
    $self->{canvas}->idletasks if (!$noupdate);
}

#####################
#### view_circle ####
#####################
sub view_circle {
    my $self = shift;
    my $data = shift;
    my $color = shift;
    my $extra = shift;

    my $nfields = scalar(@{$self->{field_evals}});
    my @xs;
    my @ys;
    my $irad = $self->{radius} * 2 * pi / $nfields;
    for (my $i = 0; $i < $nfields; $i++) {
        my $val = $self->scale_eval($data, $i, $irad);
        my $angle = pi + ($i + $val) * 2 * pi / $nfields;
        push(@xs, $self->{xorg} + $self->{radius} * cos($angle));
        push(@ys, $self->{yorg} + $self->{radius} * sin($angle));
    }

    for (my $i = 0; $i < $nfields; $i++) {
        $self->create_arc($color, $extra, $xs[($i + 1) % $nfields], $xs[$i],
            $ys[($i + 1) % $nfields], $ys[$i]);
    }
}

###################
#### view_hive ####
###################
sub view_hive {
    my $self = shift;
    my $data = shift;
    my $color = shift;
    my $extra = shift;

    my $nfields = scalar(@{$self->{field_evals}});
    my @xs;
    my @ys;
    for (my $i = 0; $i < $nfields; $i++) {
        my $val = $self->scale_eval($data, $i, $self->{radius});
        $val = 1 / $self->{radius} if (!$val);
        my $angle = 3 * pi / 2 + $i * 2 * pi / $nfields;
        push(@xs, $self->{xorg} + $val * $self->{radius} * cos($angle));
        push(@ys, $self->{yorg} + $val * $self->{radius} * sin($angle));
    }

    for (my $i = 0; $i < $nfields; $i++) {
        $self->create_arc($color, $extra, $xs[$i], $xs[($i + 1) % $nfields],
            $ys[$i], $ys[($i + 1) % $nfields]);
    }
}

#######################
#### view_parallel ####
#######################
sub view_parallel {
    my $self = shift;
    my $data = shift;
    my $color = shift;
    my $extra = shift;

    my $nfields = scalar(@{$self->{field_evals}});
    my @xs = (1);
    for (my $i = 1; $i < $nfields; $i++) {
        my $x = int($self->{width} * $i / ($nfields - 1));
        $x = $self->{width} - 1 if ($i == $nfields - 1);
        push(@xs, $x);
    }

    my @ys;
    for (my $i = 0; $i < $nfields; $i++) {
        my $y = $self->scale_eval($data, $i, $self->{ymax});
        # invert y so axis increases from bottom to top
        $y = (1 - $y) * $self->{ymax};
        $y = 1 if (!$y);
        push(@ys, $y);
    }

    my @xys = map {($_, shift @ys)} @xs;

    $self->{canvas}->createLine(@xys,
        -fill => $color,
        %{$extra},
    );
}

###################
#### view_star ####
###################
sub view_star {
    my $self = shift;
    my $data = shift;
    my $color = shift;
    my $extra = shift;

    my $nfields = scalar(@{$self->{field_evals}});
    my @xs;
    my @ys;
    for (my $i = 0; $i < $nfields; $i++) {
        my $val = $self->scale_eval($data, $i, $self->{radius});
        $val = 1 / $self->{radius} if (!$val);
        my $angle = 3 * pi / 2 + $i * 2 * pi / $nfields;
        push(@xs, $self->{xorg} + $val * $self->{radius} * cos($angle));
        push(@ys, $self->{yorg} + $val * $self->{radius} * sin($angle));
    }

    my @xys = map {($_, shift @ys)} @xs;
    push(@xys, $xys[0], $xys[1]);

    $self->{canvas}->createLine(@xys,
        -fill => $color,
        %{$extra},
    );
}

1;

