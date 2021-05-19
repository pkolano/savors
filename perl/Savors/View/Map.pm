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

package Savors::View::Map;

use Savors::FatPack::GPL;
use Savors::FatPack::PAL;

use strict;
use File::Spec;
use Geo::ShapeFile;
use Tk;
use Tk::AbstractCanvas;
use Tk::Canvas;

use base qw(Savors::View);

our $VERSION = 2.2;

#############
#### new ####
#############
sub new {
    my $proto = shift;
    my $class = ref $proto || $proto;
    my $self = $class->SUPER::new(@_,
        "attr=s,dash=s,file=s,lines=i,no-tags=s,tags=s");
    return undef if (!defined $self);
    bless($self, $class);

    $self->{counts} = {};
    $self->{dash_eval} = $self->eval($self->getopt('dash'));
    $self->{dopts}->{file} = "world";
    $self->{dopts}->{'no-tags'} = '\b\B';
    $self->{dopts}->{period} = 0;
    $self->{dopts}->{tags} = '.';
    $self->{dopts}->{type} = "arc";
    $self->{notags} = $self->getopt('no-tags');
    $self->{tags} = $self->getopt('tags');
    $self->{time} = 0;

    return $self;
}

##############
#### bbox ####
##############
sub bbox {
    my $self = shift;
    my $fake = shift;
    $self->init if (!$fake);
    if ($self->getopt('type') eq 'arc') {
        my $i = $self->{copts}->{offset};
        for (0..$self->{lines} - 1) {
            my $data = $self->{copts}->{buffer}->[$i];
            $self->view_arc($data, 1)
                if ($data->[0] ne 'savors_eof' && $self->grep($data));
            $i--;
            last if ($i < 0);
        }
    }
    $self->{canvas}->idletasks;
}

##############
#### help ####
##############
sub help {
    my $brief = shift;
    if ($brief) {
        "      map - world/country/shape map " .
            "    map --color=f12 --fields=f3,f7 --file=us\n";
    } else {
        "USAGE: env OPT=VAL... (ARGS... |...) |map --opt=val...\n\n" .
        "TYPES: arc,bubble,heat\n\n" .
        "OPTIONS:                                          EXAMPLES:\n" .
        "      --attr=STRING - attribute containing tags   " .
            "    --attr=fips\n" .
        "       --color=EVAL - expression to color by      " .
            "    --color=f19\n" .
        "      --ctype=CTYPE - method to assign colors by  " .
            "    --ctype=hash:ord\n" .
        "        --dash=EVAL - condition to dash edge      " .
            "    --dash=\"f21 eq 'out'\"\n" .
        "     --fields=EVALS - expressions denoting edges  " .
            "    --fields=f3,f7\n" .
        "        --file=FILE - name of shape file          " .
            "    --file=us\n" .
        "    --legend[=SIZE] - show color legend           \n" .
        "                        [REAL width or INT pixels]" .
            "    --legend=0.2\n" .
        "    --legend-pt=INT - legend font point size      " .
            "    --legend-pt=12\n" .
        "        --max=REALS - max value of each field     " .
            "    --max=100,10,50\n" .
        "        --min=REALS - min value of each field     " .
            "    --min=50,0,10\n" .
        "    --no-tags=REGEX - exclude matching tags       " .
            "    --no-tags=02|15|72|78\n" .
        "      --period=REAL - time between updates        " .
            "    --period=15\n" .
        "       --tags=REGEX - include matching tags       " .
            "    --tags=ca|mx|us\n" .
        "     --title=STRING - title of view               " .
            "    --title=\"CPU Usage\"\n" .
        "        --type=TYPE - type of map                 " .
            "    --type=arc\n" .
        "";
    }
}

##############
#### init ####
##############
sub init {
    my $self = shift;
    $self->SUPER::init;

    if (!defined $self->{canvas}) {
        # use all-enclosing frame to get outer border without inner borders
        $self->{frame0} = $self->{top}->Frame(
            -highlightthickness => 1,
        )->pack(
            -expand => 1,
            -fill => 'both',
        );

        $self->{frame} = $self->{frame0}->Frame(
        )->pack(
            -expand => 1,
            -fill => 'both',
            -side => 'left',
        );
        $self->{canvas} = $self->{frame}->AbstractCanvas(
            -background => 'black',
            -highlightthickness => 0,
        )->pack(
            -side => 'top',
            -expand => 1,
            -fill => 'both',
        );

    	if (defined $self->{copts}->{legend}) {
        	my $legend = $self->getopt('legend');
        	$legend = int($legend * $self->{width}) if ($legend < 1);
            $self->{lcanvas} = $self->{frame0}->Canvas(
                -background => 'black',
                -highlightthickness => 0,
                -width => $legend,
            )->pack(
                -fill => 'y',
                -side => 'right',
            );
        }

        if ($self->getopt('title')) {
			my $size = int(.1 * $self->{height});
            $self->{tcanvas} = $self->{frame}->Canvas(
                -background => 'black',
                -height => $size,
                -highlightthickness => 0,
            )->pack(
                -fill => 'x',
                -side => 'bottom',
            );
        }
    } else {
        $self->{canvas}->delete('!legend');
    }
    $self->title if ($self->getopt('title'));

    if ($self->getopt('type') eq 'arc') {
        $self->{lines} = $self->getopt('lines');
        $self->{lines} = $self->{height} if (!$self->{lines});
        $self->{line} = 0;
    }

    if (!defined $self->{shapes}) {
        my $file = $self->getopt('file');
        $self->{shapes} = Geo::ShapeFile->new(File::Spec->catfile(
            $self->{conf}->{lib_dir}, "maps", $file, $file));
        my %db = $self->{shapes}->get_dbf_record(1);
        foreach my $key (keys %db) {
            if ($key =~ /fips/i) {
                $self->{dopts}->{attr} = $key;
                last;
            }
        }
    }

    for my $s (1 .. $self->{shapes}->shapes) {
        my $shape = $self->{shapes}->get_shp_record($s);
        my %db = $self->{shapes}->get_dbf_record($s);
        my $tag = lc $db{$self->getopt('attr')};
        next if ($tag =~ /$self->{notags}/);
        next if ($tag !~ /$self->{tags}/);
        for my $p (1 .. $shape->num_parts) {
            my @part = $shape->get_part($p);
            my @poly;
            foreach my $xy (@part) {
                my $x =($xy->X + 180) / 360 * $self->{width};
                my $y =(-$xy->Y + 90) / 180 * $self->{height};
                push(@poly, $x, $y);
            }
            $self->{canvas}->createPolygon(@poly,
                -outline => 'white',
                -tags => $tag,
            );
        }
    }
    $self->{bbox} = [];
    push(@{$self->{bbox}}, $self->{canvas}->bbox('all'));
    $self->{canvas}->viewArea(@{$self->{bbox}}, -border => 0);
    # have to do this twice or else map inverted for some reason
    $self->{canvas}->viewArea(@{$self->{bbox}}, -border => 0);
}

################
#### legend ####
################
sub legend {
    my $self = shift;
    my $field = shift;
    my $color = shift;
    my $canvas = $self->{canvas};
    my $width = $self->{width};
    $self->{canvas} = $self->{lcanvas};
    $self->{width} = 0;
    $self->SUPER::legend($field, $color);
    $self->{lcanvas}->idletasks;
    $self->{canvas} = $canvas;
    $self->{width} = $width;
}

##############
#### play ####
##############
sub play {
    my $self = shift;
    my $data = shift;
    my $raised = shift;

    if ($self->getopt('type') eq 'arc') {
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
    } else {
        if ($data->[0] eq 'savors_eof') {
            $self->view if ($raised);
            return;
        }
        my @fields = map {eval} @{$self->{field_evals}};
        my $count = shift @fields;
        my $color = $self->color($data);
        my @bbx = sort {$a <=> $b} @{$self->{bbox}}[0,2];
        my @bby = sort {$a <=> $b} @{$self->{bbox}}[1,3];
        for (my $i = 0; $i < scalar(@fields); $i += 2) {
            my $x = ($fields[$i + 1] + 180) * $self->{width} / 360;
            my $y = (-$fields[$i] + 90) * $self->{height} / 180;
            next if ($x < $bbx[0] || $x > $bbx[1]);
            next if ($y < $bby[0] || $y > $bby[1]);
            if ($self->getopt('type') eq 'bubble') {
                $self->{counts}->{"$x,$y,$color"} += $count;
            } elsif ($self->getopt('type') eq 'heat') {
                my $tags = $self->{canvas}->find('closest', $x, $y);
                $self->{counts}->{$tags->[0]} += $count;
            }
        }

        my $time = int($self->time($data));
        if ($self->getopt('period') == 0 ||
                $time >= $self->{time} + $self->getopt('period')) {
            $self->view if ($raised);
            $self->{time} = $time;
            $self->{counts} = {};
        }
    }
}

###############
#### title ####
###############
sub title {
    my $self = shift;
    my $canvas = $self->{canvas};
    my $height = $self->{height};
    $self->{canvas} = $self->{tcanvas};
    $self->{height} = 0;
    $self->SUPER::title;
    $self->{tcanvas}->idletasks;
    $self->{canvas} = $canvas;
    $self->{height} = $height;
}

##############
#### view ####
##############
sub view {
    my $self = shift;
    my $data = shift;

    if ($self->getopt('type') eq 'arc') {
        $self->view_arc($data);
    } elsif ($self->getopt('type') eq 'bubble') {
        $self->view_bubble;
    } elsif ($self->getopt('type') eq 'heat') {
        $self->view_heat;
    }
}

##################
#### view_arc ####
##################
sub view_arc {
    my $self = shift;
    my $data = shift;
    my $noupdate = shift;

    return if (!defined $data);
    my @fields = map {eval} @{$self->{field_evals}};
    my @x = map {($_ + 180) * $self->{width} / 360} @fields[1,3];
    my @y = map {(-$_ + 90) * $self->{height} / 180} @fields[0,2];
    return if ($x[0] == $x[1] && $y[0] == $y[1]);
    my @bbx = sort {$a <=> $b} @{$self->{bbox}}[0,2];
    my @bby = sort {$a <=> $b} @{$self->{bbox}}[1,3];
    foreach (0..1) {
        return if ($x[$_] < $bbx[0] || $x[$_] > $bbx[1]);
        return if ($y[$_] < $bby[0] || $y[$_] > $bby[1]);
    }

    $self->{canvas}->delete("l" . $self->{line});
    my $color = $self->color($data);

    my $extra = {};
    $extra->{-tags} = "l" . $self->{line};
    $extra->{-dash} = '.' if ($self->{dash_eval} && eval $self->{dash_eval});

    $self->create_arc($color, $extra, @x, @y);

    $self->{line} = ($self->{line} + 1) % $self->{lines};
    $self->{canvas}->idletasks if (!$noupdate);
}

#####################
#### view_bubble ####
#####################
sub view_bubble {
    my $self = shift;
    $self->{canvas}->delete("bubble");
    foreach my $xyc (keys %{$self->{counts}}) {
        my $count = $self->{counts}->{$xyc};
        $count = 1 if ($count <= 0);
        $count = log($count);
        $count = int($count / 2) + 1;
        my ($x, $y, $color) = split(/,/, $xyc);
        $self->{canvas}->createOval(
            $x - $count, $y - $count, $x + $count, $y + $count,
            -fill => $color,
            -tags => "bubble",
        );
    }
    $self->{canvas}->idletasks;
}

###################
#### view_heat ####
###################
sub view_heat {
    my $self = shift;

    $self->{canvas}->itemconfigure('all',
        -fill => 'black',
    );

    my $i = 0;
    my @min = split(/,/, $self->getopt('min'));
    my @max = split(/,/, $self->getopt('max'));
    foreach my $tag (keys %{$self->{counts}}) {
        my $count = $self->{counts}->{$tag};
        my $min = defined $min[$i] ? $min[$i] : $min[0];
        my $max = defined $max[$i] ? $max[$i] : $max[0];
        my $val = ($count - $min) / $max;
        $val = 1 if ($val > 1);
        $val = 0 if ($val < 0);
        my $color = $self->color_heat($val);;
        $self->{canvas}->itemconfigure($tag, 
            -fill => $color,
        );
    }

    $self->{canvas}->idletasks;
}

1;

