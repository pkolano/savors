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

package Savors::Console::Wall;

use strict;
use String::ShellQuote;

use base qw(Savors::Console::Level);
use Savors::Console::Layout;

our $VERSION = 0.02;

#############
#### new ####
#############
sub new {
    my $proto = shift;
    my $class = ref $proto || $proto;
    my $self = {};
    bless($self, $class);

    my $layout = shift;
    $layout = "1x1" if (!$layout);
    ($self->{cols}, $self->{rows}) = split(/x/, $layout);

    my $displays = shift;
    $displays = "localhost" if (!$displays);
    $self->{displays} = [split(/,/, $displays)];

    $self->{children} = [];
    $self->{current} = 0;

    $self->create;

    return $self;
}

################
#### create ####
################
sub create {
    my $self = shift;
    push(@{$self->{children}}, Savors::Console::Layout->new($self));
    my $old = $self->{current};
    $self->{current} = scalar(@{$self->{children}}) - 1;
    if ($self->{current} != $old) {
        $self->{children}->[$old]->blur;
        $self->{children}->[$old]->lower;
        $self->focus;
    }
    $self->raise;
}

##############
#### next ####
##############
sub next {
    my $self = shift;
    my $old = $self->{current};
    $self->{current}++;
    $self->{current} %= scalar(@{$self->{children}});
    if ($self->{current} != $old) {
        $self->{children}->[$old]->blur;
        $self->{children}->[$old]->lower;
        $self->focus;
        $self->raise;
    }
}

##############
#### prev ####
##############
sub prev {
    my $self = shift;
    my $old = $self->{current};
    $self->{current} += scalar(@{$self->{children}}) - 1;
    $self->{current} %= scalar(@{$self->{children}});
    if ($self->{current} != $old) {
        $self->{children}->[$old]->blur;
        $self->{children}->[$old]->lower;
        $self->focus;
        $self->raise;
    }
}

#############
#### run ####
#############
sub run {
    my $self = shift;
    my $cmd0 = shift;
    my $bbox = shift;
    my $ports0 = shift;

    $cmd0 =~ s/\s+--vgeometry=\S+\s+// 
        if (scalar(@{$self->{displays}} > 1));

    my $col1 = $self->{cols} * $bbox->[2];
    my $col2 = $col1 + $self->{cols} * $bbox->[0];

    my $row1 = $self->{rows} * $bbox->[3];
    my $row2 = $row1 + $self->{rows} * $bbox->[1];

    my %ports;
    my $vgeom0 = "r$self->{cols}x$self->{rows}";
    for (my $r = int($row1); $r < $row2; $r++) {
        for (my $c = int($col1); $c < $col2; $c++) {
            my $dindex = $r * $self->{cols} + $c;
            if (defined $ports0->{$dindex}) {
                $ports{$dindex} = $ports0->{$dindex};
            } else {
                my $vgeom = $vgeom0 . "+-$c+-$r";
                my $display = $self->{displays}->[$dindex];
                my ($host, $edisplay, $libdir) = split(/:/, $display);
                $edisplay = ":" . $edisplay if (defined $edisplay);
                my $cmd = $cmd0;
                $cmd =~ s/(lib_dir=)\S+/$1$libdir/ if ($libdir);
                $cmd =~ s/(--swidth)/--display=$edisplay $1/ if ($edisplay);
                $cmd =~ s/(--swidth)/--vgeometry=$vgeom $1/
                    if (scalar(@{$self->{displays}} > 1));
                $cmd = "ssh -qx $host " . shell_quote($cmd)
                    if ($host ne 'localhost');
                my $port = qx($cmd 2>/dev/null);
                $port = "$host:$port" if ($port =~ /^\d+$/);
                $ports{$dindex} = $port;
            }
        }
    }
    return \%ports;
}

1;

