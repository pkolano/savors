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

package Savors::View::Rain;

use strict;
use POSIX qw(ceil);
use Tk;

use base qw(Savors::View);

our $VERSION = 0.21;

#############
#### new ####
#############
sub new {
    my $proto = shift;
    my $class = ref $proto || $proto;
    my $self = $class->SUPER::new(@_, "hex,size=i");
    return undef if (!defined $self);
    bless($self, $class);

    $self->{dopts}->{period} = 0;
    $self->{dopts}->{size} = 14;

    return $self;
}

##############
#### bbox ####
##############
sub bbox {
    my $self = shift;
    my $fake = shift;
    $self->init if (!$fake);
    my $i = $self->{copts}->{offset};
    for (0..$self->{lines} - 2) {
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
        "     rain - text/binary rainfall    " .
            "    rain --color=f19 --fields=f17,f18 --hex --size=1\n";
    } else {
        "USAGE: env OPT=VAL... (ARGS... |...) |rain ...\n\n" .
        "OPTIONS:                                       EXAMPLES:\n" .
        "      --color=EVAL - expression to color by    " .
            "    --color=f19\n" .
        "     --ctype=CTYPE - method to assign colors by" .
            "    --ctype=hash:ord\n" .
        "    --fields=EVALS - subset of fields to show  " .
            "    --fields=f17,f18\n" .
        "             --hex - show binary data as hex   " .
            "    --hex\n" .
        "          --legend - show color legend         " .
            "    --legend\n" .
        "        --max=INTS - max value of each field   " .
            "    --max=100,10,50\n" .
        "        --min=INTS - min value of each field   " .
            "    --min=50,0,10\n" .
        "     --period=REAL - time between updates      " .
            "    --period=3\n" .
        "        --size=INT - font size or 1 for binary " .
            "    --size=1\n" .
        "    --title=STRING - title of view             " .
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

        if ($self->getopt('size') > 1) {
            # calculate height in pixels
            $self->{canvas}->createText(1, 1,
                -anchor => 'nw',
                -font => "courier -" . $self->getopt('size'),
                -tag => "test",
                -text => "test",
            );
            my @bbox = $self->{canvas}->bbox("test");
            $self->{pixels} = $bbox[3] - $bbox[1];
        } else {
            $self->{pixels} = 1;
        }
    } else {
        $self->{canvas}->delete('!legend');
        $self->{canvas}->move('legend', $self->{width} - $oldx, 0);
    }
    $self->title if ($self->getopt('title'));

    $self->{lines} = int($self->{height} / $self->{pixels});
    $self->{line} = 0;
}

##############
#### play ####
##############
sub play {
    my $self = shift;
    my $data = shift;
    my $raised = shift;

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

##############
#### view ####
##############
sub view {
    my $self = shift;
    my $data = shift;
    my $noupdate = shift;

    return if (!defined $data);
    my @fields;
    if (defined $self->getopt('fields')) {
        @fields = map {eval} @{$self->{field_evals}};
    } else {
        @fields = @{$data}[1 .. scalar(@{$data}) - 1];
    }

    my $color = $self->color($data);
    $self->{canvas}->delete("l" . $self->{line});

    $self->{canvas}->itemconfigure(
        "l" . (($self->{line} - 1 + $self->{lines}) % $self->{lines}),
        -state => 'normal',
    );
 
    if ($self->getopt('size') == 1) {
        my @bytes;
        if ($self->getopt('hex')) {
            @bytes = unpack("C*", pack("H*", join("", @fields)));
        } else {
            @bytes = unpack("C*", join("", @fields));
        }

        my $bits = "#define bm_width " . (8 * int($self->{width} / 8)) .
            "\n#define bm_height 1\n";
        $bits .= "static unsigned char bm_bits[] = {\n";
        for (my $i = 0; $i < int($self->{width} / 8); $i++) {
            if ($i < scalar(@bytes)) {
                $bits .= "0x" . unpack("H*", pack("C", $bytes[$i])) . ",";
            } else {
                $bits .= "0x00,";
            }
        }
        chop $bits;
        $bits .= "};";
        my $bitmap = $self->{top}->Bitmap(
            -data => $bits,
            -foreground => $color,
        );
        my $wbitmap = $self->{top}->Bitmap(
            -data => $bits,
            -foreground => 'white',
        );

        $self->{canvas}->createImage(1, 1 + $self->{line},
            -anchor => 'nw',
            -disabledimage => $wbitmap,
            -image => $bitmap,
            -state => 'disabled',
            -tags => "l" . $self->{line},
        );
    } else {
        $self->{canvas}->createText(1, ceil($self->{line} * $self->{pixels}),
            -anchor => 'nw',
            -disabledfill => 'white',
            -fill => $color,
            -font => "courier -" . $self->getopt('size'),
            -state => 'disabled',
            -tags => "l" . $self->{line},
            -text => \@fields,
        );
    }

    $self->{line} = ($self->{line} + 1) % $self->{lines};
    $self->{canvas}->idletasks if (!$noupdate);
}

1;

