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

package Savors::Console::Region;

use strict;
use Time::HiRes qw(time);

use base qw(Savors::Console::Level);
use Savors::Console::Window;

our $VERSION = 0.20;

#############
#### new ####
#############
sub new {
    my $proto = shift;
    my $class = ref $proto || $proto;
    my $self = {};
    bless($self, $class);

    $self->{parent} = shift;
    $self->{children} = [];
    $self->{current} = 0;
    $self->{atime} = time;

    $self->create;

    return $self;
}

##############
#### bbox ####
##############
sub bbox {
    my $self = shift;
    return $self->{parent}->bbox($self);
}

################
#### create ####
################
sub create {
    my $self = shift;
    push(@{$self->{children}}, Savors::Console::Window->new($self));
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

#################
#### overlap ####
#################
sub overlap {
    my $self = shift;
    my $next = shift;
    my $dir = shift;

    my $bbox0 = $self->bbox;
    my $bbox1 = $next->bbox;
    my ($r0x0, $r0x1, $r0y0, $r0y1) =
        ($bbox0->[2], $bbox0->[2] + $bbox0->[0],
        $bbox0->[3], $bbox0->[3] + $bbox0->[1]);
    my ($r1x0, $r1x1, $r1y0, $r1y1) =
        ($bbox1->[2], $bbox1->[2] + $bbox1->[0],
        $bbox1->[3], $bbox1->[3] + $bbox1->[1]);

    if ($dir) {
        # next is below self
        if (($r1y0 == $r0y1 || $r1y0 == 0 && $r0y1 == 1) &&
                $r1x1 > $r0x0 && $r1x0 < $r0x1) {
            return 1;
        }
    } else {
        # next is right of self
        if (($r1x0 == $r0x1 || $r1x0 == 0 && $r0x1 == 1) &&
                $r1y1 > $r0y0 && $r1y0 < $r0y1) {
            return 1;
        }
    }
    return 0;
}

################
#### remove ####
################
sub remove {
    my $self = shift;
    $_->remove foreach (@{$self->{children}});
    $self->{parent}->remove($self);
}

###############
#### split ####
###############
sub split {
    my $self = shift;
    my $split = shift;
    $self->{parent}->split($self, $split);
}

1;

