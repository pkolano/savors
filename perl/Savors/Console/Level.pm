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

package Savors::Console::Level;

use strict;
use Time::HiRes qw(time);

our $VERSION = 2.2;

##############
#### bbox ####
##############
sub bbox {
    my $self = shift;
    return $self->{parent}->bbox($self);
}

##############
#### blur ####
##############
sub blur {
    my $self = shift;
    $self->{children}->[$self->{current}]->blur;
}

#################
#### current ####
#################
sub current {
    my $self = shift;
    my $next = shift;
    if ($next) {
        $self->{atime} = time;
        $self->{current} = $self->index($next);
        $self->{parent}->current($self) if ($self->{parent});
    } else {
        $next = $self;
        while (ref($next) eq ref($self)) {
            $next = $next->{children}->[$next->{current}];
        }
        return $next;
    }
}

###############
#### focus ####
###############
sub focus {
    my $self = shift;
    $self->{children}->[$self->{current}]->focus;
}

###############
#### index ####
###############
sub index {
    my $self = shift;
    my $child = shift;
    return -1 if (!$self->{children});
    my $i;
    my $n = scalar(@{$self->{children}});
    for ($i = 0; $i < $n; $i++) {
        last if ($self->{children}->[$i] == $child);
    }
    return -1 if ($i == $n);
    return $i;
}

################
#### layout ####
################
sub layout {
    my $self = shift;
    $self = $self->{parent} while (ref($self) ne 'Savors::Console::Layout');
    return $self;
}

###############
#### lower ####
###############
sub lower {
    my $self = shift;
    $self->{children}->[$self->{current}]->lower;
}

###############
#### raise ####
###############
sub raise {
    my $self = shift;
    $self->{children}->[$self->{current}]->raise;
}

################
#### region ####
################
sub region {
    my $self = shift;
    $self = $self->{parent} while (ref($self) ne 'Savors::Console::Region');
    return $self;
}

################
#### update ####
################
sub update {
    my $self = shift;
    $_->update foreach (@{$self->{children}});
}

##############
#### wall ####
##############
sub wall {
    my $self = shift;
    $self = $self->{parent} while (ref($self) ne 'Savors::Console::Wall');
    return $self;
}

1;

