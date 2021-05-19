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

package Savors::Console::Layout;

use Savors::FatPack::PAL;

use strict;
use Text::Balanced qw(extract_bracketed);
use Time::HiRes qw(time);

use base qw(Savors::Console::Level);
use Savors::Console::Region;
use Savors::Debug;

our $VERSION = 2.2;

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
    my $bbox = $self->{parent}->bbox($self);
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

#################
#### psmerge ####
#################
# based on epsfcompose by Nick Kaiser - kaiser@hawaii.edu (no license specified)
sub psmerge {
    my $split = shift;
    my $out = shift;
    my @files = $split ? reverse @_ : @_;

    # get the bounding boxes
    my (%dx, %t, %x);
    my @scale;
    foreach my $f (0 .. scalar(@files) - 1) {
        open(EPS, $files[$f]);
        # must not read to $_ below or console will mysteriously die
        while (my $line = <EPS>) {
            next if ($line !~ /^%%BoundingBox:/);
            my @xy = split(/\s/, $line);
            next if (scalar(@xy) != 5);
            shift @xy;
            # get coords of 4 corners (llx, lly, urx, ury)
            $x{$f,1,0} = $xy[0];
            $x{$f,1,1} = $xy[1];
            $x{$f,2,0} = $xy[0];
            $x{$f,2,1} = $xy[3];
            $x{$f,3,0} = $xy[2];
            $x{$f,3,1} = $xy[3];
            $x{$f,4,0} = $xy[2];
            $x{$f,4,1} = $xy[1];

            if ($f == 0) {
                $scale[$f] = 1;
            } elsif ($split) {
                $scale[$f] = ($x{0,3,0} - $x{0,1,0}) / ($xy[2] - $xy[0]);
            } else {
                $scale[$f] = ($x{0,3,1} - $x{0,1,1}) / ($xy[3] - $xy[1]);
            }
            $t{$f,0,0} = $scale[$f];
            $t{$f,0,1} = 0;
            $t{$f,1,0} = 0;
            $t{$f,1,1} = $scale[$f];
            last;
        }
        close EPS;

        # apply scaling and rotation to corners of b-boxes
        foreach my $c (1 .. 4) {
            my @x;
            foreach my $i (0 .. 1) {
                $x[$i] = $t{$f,$i,0} * $x{$f,$c,0} + $t{$f,$i,1} * $x{$f,$c,1};
            }
            foreach my $i (0 .. 1) {
                $x{$f,$c,$i} = $x[$i];
            }
        }

        # apply shifts to each of bbox corners
        my @xo = $split ? (0, $f) : ($f, 0);
        foreach my $i (0 .. 1) {
            # additionally shift bounding boxes so use same origin of 0,0
            $dx{$f,$i} = -$x{$f,1,$i} + ($x{$f,3,$i} - $x{$f,1,$i}) * $xo[$i];
            foreach my $c (1 .. 4) {
                $x{$f,$c,$i} += $dx{$f,$i};
            }
        }
    }

    # figure the final bbox
    my (@xmin, @xmax);
    foreach my $i (0 .. 1) {
        $xmin[$i] = $xmax[$i] = $x{0,1,$i};
        foreach my $f (0 .. scalar(@files) - 1) {
            foreach my $c (1 .. 4) {
                $xmin[$i] = $x{$f,$c,$i} if ($x{$f,$c,$i} < $xmin[$i]);
                $xmax[$i] = $x{$f,$c,$i} if ($x{$f,$c,$i} > $xmax[$i]);
            }
        }
    }

    # make final bounding box
    my (@ll, @ur);
    foreach my $i (0 .. 1) {
        $ll[$i] = $xmin[$i];
        $ur[$i] = $xmax[$i];
    }

    # print the 1st two lines
    open(OUT, '>', $out);
    print OUT "%!PS-Adobe-3.0 EPSF-3.0\n";
    print OUT "%%BoundingBox: $ll[0] $ll[1] $ur[0] $ur[1]\n";
    print OUT "%%EndComments\n";
    foreach my $f (0 .. scalar(@files) - 1) {
        print OUT "/nksave save def\n";
        print OUT "/showpage {} def\n";
        print OUT "0 setgray 0 setlinecap\n";
        print OUT "1 setlinewidth 0 setlinejoin\n";
        print OUT "10 setmiterlimit [] 0 setdash newpath\n";
        print OUT "%%BeginDocument: $files[$f]\n";
        print OUT "$dx{$f,0} $dx{$f,1} translate\n";
        print OUT "$scale[$f] $scale[$f] scale\n";
        my $skip = 1;
        open(EPS, $files[$f]);
        # must not read to $_ below or console will mysteriously die
        while (my $line = <EPS>) {
            if (!$skip) {
                print OUT $line;
            }
            $skip = 0 if ($line =~ /^%%EndComments/);
        }
        close EPS;
        print OUT "%%EndDocument\n";
        print OUT "nksave restore\n";
    }
    print OUT "showpage\n";
    close OUT;
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
    if (!defined $child || !ref $child) {
        $_->remove($child) foreach (@{$self->{children}});
        return;
    }
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

#############
#### run ####
#############
sub run {
    my $self = shift;
    my $cmds = shift;
    my $layout0 = shift;

    my $subs = {};
    my $layout = run_layout($layout0, $subs);

    my @regions;
    if ($layout =~ /-/) {
        @regions = split(/-/, $layout);
        @regions = map {s/^(\d+)$/$1x1/; $_} @regions;
        $self->{split} = 1;
    } elsif ($layout =~ /\|/) {
        @regions = split(/\|/, $layout);
        @regions = map {s/^(\d+)$/1x$1/; $_} @regions;
        $self->{split} = 0;
    } elsif ($layout =~ /1x(\d+)/) {
        $self->{split} = 1;
        push(@{$self->{children}}, Savors::Console::Region->new($self))
            foreach (1 .. $1 - 1);
        $_->run($cmds) foreach (@{$self->{children}});
        return;
    } elsif ($layout =~ /(\d+)x1/ || $layout =~ /^(\d+)$/) {
        $self->{split} = 0;
        push(@{$self->{children}}, Savors::Console::Region->new($self))
            foreach (1 .. $1 - 1);
        $_->run($cmds) foreach (@{$self->{children}});
        return;
    } elsif ($layout =~ /(\d+)x(\d+)/) {
        @regions = map {$1} 1 .. $2;
        $self->{split} = 1;
    } else {
        #TODO: error
    }
    foreach my $region (@regions) {
        push(@{$self->{children}}, Savors::Console::Layout->new($self));
    }
    # remove original region
    shift @{$self->{children}};
    my $i = 0;
    foreach my $region (@regions) {
        $region =~ s/^(s\d+)$/$subs->{$1}/;
        $self->{children}->[$i++]->run($cmds, $region);
    }
}

####################
#### run_layout ####
####################
sub run_layout {
    my $layout = shift;
    my $subs = shift;
    my ($sub, $rem, $pre) =
        extract_bracketed($layout, '(', '[x\s\d\|\-]*');
    if ($sub && !$rem && !$pre) {
        return run_layout(substr($sub, 1, -1), $subs);
    } elsif ($sub) {
        $sub =~ s/^.|.$//g;
        my $key = "s" . $subs->{n}++;
        $subs->{$key} = $sub;
        return $pre . $key . run_layout($rem, $subs);
    } else {
        return $layout;
    }
}

##############
#### save ####
##############
sub save {
    my $self = shift;
    my $file0 = shift;

    if (scalar(@{$self->{children}}) == 1) {
        $self->{children}->[0]->save($file0);
    } else {
        my $i = 0;
        my @files;
        foreach (@{$self->{children}}) {
            my $file = $file0 . ($i++) . ".ps";
            push(@files, $file);
            $_->save($file);
        }
        psmerge($self->{split}, $file0, @files);
        unlink @files;
    }
}

##############
#### send ####
##############
sub send {
    my $self = shift;
    my $msg = shift;
    my @sockets;
    push(@sockets, @{$_->send($msg)}) foreach (@{$self->{children}});
    return \@sockets;
}

################
#### server ####
################
sub server {
    my $self = shift;
    my $server = shift;
    my %servers;
    foreach (@{$self->{children}}) {
        my $vserver = $_->server($server);
        while (my ($key, $val) = each %{$vserver}) {
            $servers{$key} = $val;
        }
    }
    return \%servers;
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

