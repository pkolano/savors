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

package Savors::Console::Layout;

use strict;
use Time::HiRes qw(time);

use base qw(Savors::Console::Level);
use Savors::Console::Region;

our $VERSION = 0.21;

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
    $self->{split} = -1;
    $self->{current} = 0;
    $self->{atime} = time;

    push(@{$self->{children}}, Savors::Console::Region->new($self));

    return $self;
}

##############
#### bbox ####
##############
sub bbox {
    my $self = shift;
    my $child = shift;
    my $bbox;
    if (ref($self->{parent}) ne ref($self)) {
        # swidth, sheight, sx, sy
        $bbox = [1, 1, 0, 0];
    } else {
        $bbox = $self->{parent}->bbox($self);
    }
    if ($self->{split} >= 0) {
        $bbox->[$self->{split}] /= scalar(@{$self->{children}});
        $bbox->[2 + $self->{split}] +=
            abs($self->index($child)) * $bbox->[$self->{split}];
    }
    return $bbox;
}

##############
#### down ####
##############
sub down {
    return $_[0]->move($_[1], 1, 0, 1);
}

##############
#### left ####
##############
sub left {
    return $_[0]->move($_[1], 0, 1, 0);
}

###############
#### lower ####
###############
sub lower {
    my $self = shift;
    $_->lower foreach (@{$self->{children}});
}

##############
#### move ####
##############
sub move {
    my $self = shift;
    my $current = shift;
    my ($i1, $i2, $dir) = @_;
    my $prev;

    if (!$current) {
        $current = $self->current;
        $prev = $self->{children}->[$self->{current}];
    }
    
    my @nodes = (undef, $current);
    my $next = {atime => 0};
    foreach my $child (@{$self->{children}}) {
        $nodes[0] = $child;
        if (ref($child) ne ref($self) &&
                $nodes[$i1]->overlap($nodes[$i2], $dir)) {
            $next = $child if ($child->{atime} > $next->{atime});
        } elsif (ref($child) eq ref($self)) {
            my $tmp = $child->move($current, $i1, $i2, $dir);
            $next = $tmp if ($tmp->{atime} > $next->{atime});
        }
    }
    return $next if (!$prev);
    if ($prev != $next) {
        $prev->blur;
        $next->current($next->current);
        $next->focus;
    }
}

###############
#### raise ####
###############
sub raise {
    my $self = shift;
    $_->raise foreach (@{$self->{children}});
}

################
#### remove ####
################
sub remove {
    my $self = shift;
    my $child = shift;
    return if (scalar(@{$self->{children}}) == 1);
    splice(@{$self->{children}}, $self->index($child), 1);
    $self->{current}-- if ($self->{current} >= scalar(@{$self->{children}}));
    if (scalar(@{$self->{children}}) == 1) {
        if (ref $self->{parent} eq ref $self) {
            $child = $self->{children}->[0];
            $self->{parent}->replace($self, $child);
        } else {
            $self->{split} = -1;
        }
    }
    $self->focus;
    $self->update;
}

#################
#### replace ####
#################
sub replace {
    my $self = shift;
    my $old = shift;
    my $new = shift;
    splice(@{$self->{children}}, $self->index($old), 1, $new);
    $new->{parent} = $self;
}

###############
#### right ####
###############
sub right {
    return $_[0]->move($_[1], 1, 0, 0);
}

###############
#### split ####
###############
sub split {
    my $self = shift;
    my $child = shift;
    my $split = shift;
    my $same = 1;
    foreach (@{$self->{children}}) {
        if (ref($_) eq ref($self)) {
            $same = 0;
            last;
        }
    }
    if ($self->{split} == -1 || $same && $self->{split} == $split) {
        $self->{split} = $split;
        splice(@{$self->{children}}, $self->index($child) + 1, 0,
            $child->new($self));
        $self->update;
    } else {
        my $new = $self->new($self);
        $new->{split} = $split;
        unshift(@{$new->{children}}, $child);
        $child->{parent} = $new;
        $self->replace($child, $new);
        $new->update;
    }
    $child->{atime} = time;
}

############
#### up ####
############
sub up {
    return $_[0]->move($_[1], 0, 1, 1);
}

1;

