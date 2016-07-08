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

package Savors::Console::Window;

use strict;
use IO::Socket::INET;
use IO::Socket::UNIX;
use List::Util qw(min);
use POSIX;
use Time::HiRes qw(sleep time);

use base qw(Savors::Console::Level);

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
    $self->{atime} = time;
    $self->{bbox} = [];
    $self->{cmds} = [];
    $self->{cursor} = "1.0";
    $self->{focused} = 0;
    $self->{insert} = 0;
    $self->{ports} = [];
    $self->{raised} = 0;
    $self->{sockets} = [];
    $self->{text} = "";
    $self->{colors} = {};

    return $self;
}

##############
#### blur ####
##############
sub blur {
    my $self = shift;
    my $text = $self->wall->{text};
    $self->{cursor} = $text->index('insert');
    $self->{text} = $text->Contents;
    $self->{focused} = 0;
}

###############
#### focus ####
###############
sub focus {
    my $self = shift;
    my $nograb = shift;

    if (!$nograb) {
        my $text = $self->wall->{text};
        $text->Contents($self->{text});
        $text->SetCursor($self->{cursor});
        $self->{focused} = 1;
    }

    my $bbox = $self->{parent}->bbox;
    my $canvas = $self->wall->{canvas};
    $canvas->delete('focus');
    $canvas->createRectangle(
        1 + int($canvas->width * $bbox->[2]),
        1 + int($canvas->height * $bbox->[3]),
        -1 + int($canvas->width * ($bbox->[2] + $bbox->[0])),
        -1 + int($canvas->height * ($bbox->[3] + $bbox->[1])),
        -outline => 'white',
        -tags => 'focus',
        -width => 5,
    );
    $canvas->idletasks;
}

###############
#### lower ####
###############
sub lower {
    my $self = shift;
    if ($self->{raised}) {
        $self->send("lower");
        $self->{raised} = 0;
        $self->update;
    }
}

###############
#### raise ####
###############
sub raise {
    my $self = shift;
    if (!$self->{raised}) {
        $self->send("raise");
        $self->{raised} = 1;
        $self->update;
    }
}

################
#### remove ####
################
sub remove {
    my $self = shift;
    my $canvas = $self->wall->{canvas};
    $canvas->delete($self) if ($canvas);
    if (scalar(@{$self->{ports}})) {
        $self->send("quit");
        foreach my $socks (@{$self->{sockets}}) {
            close $_ foreach (values %{$socks});
        }
        $self->{bbox} = [];
        $self->{cmds} = [];
        $self->{colors} = {};
        $self->{ports} = [];
        $self->{sockets} = [];
    }
}

#############
#### run ####
#############
sub run {
    my $self = shift;
    my $cmd = shift;
    my $bbox0 = $self->{parent}->bbox;
    my @bbox;
    foreach (qw(swidth sheight sx sy)) {
        push(@bbox, $1) if ($cmd =~ /\s--$_=(\S+)/);
    }
    $bbox[$_] /= $bbox0->[$_] foreach (0, 1);
    $bbox[$_] -= $bbox0->[$_] foreach (2, 3);
    $bbox[$_] /= $bbox0->[$_ - 2] foreach (2, 3);
    push(@{$self->{bbox}}, \@bbox);
    push(@{$self->{cmds}}, $cmd);
    $self->update;
    push(@{$self->{ports}}, $self->wall->run($cmd, \@bbox));
}

##############
#### send ####
##############
sub send {
    my $self = shift;
    my $msg = shift;
    my $index1 = shift;
    my $dindex0 = shift;
    my $index2 = defined $index1 ? $index1 : scalar(@{$self->{ports}}) - 1;
    $index1 = 0 if (!defined $index1);
    foreach my $i ($index1 .. $index2) {
        my $socks = $self->{sockets}->[$i];
        my $ports = $self->{ports}->[$i];
        if (!defined $socks) {
            $self->{sockets}->[$i] = {};
            $socks = $self->{sockets}->[$i];
        }
        while (my ($dindex, $port) = each %{$ports}) {
            next if (defined $dindex0 && $dindex != $dindex0);
            my $sock = $socks->{$dindex};
            if (!$sock) {
                if ($port =~ /:\d+$/) {
                    $sock = IO::Socket::INET->new(
                        Blocking => 0,
                        PeerAddr => $port,
                        Proto => 'tcp',
                    );
                } else {
                    $sock = IO::Socket::UNIX->new(
                        Peer => $port,
                    );
                    $sock->blocking(0);
                }
                $socks->{$dindex} = $sock;
                sleep 0.1 while (!$sock->connected);
            }
            syswrite($sock, "$msg\n");
        }
        #TODO: need error checking for socket (i.e. still exists)
    }
}

##############
#### save ####
##############
sub save {
    my $self = shift;
    my $file0 = shift;
    if (scalar(@{$self->{ports}}) > 1) {
        for (my $i = 1; $i <= scalar(@{$self->{ports}}); $i++) {
            my $file = $file0;
            if ($file !~ s/\.(?!.*\.)/-$i./) {
                $file .= "-$i";
            }
            $self->send("save $file", $i - 1);
        }
    } else {
        $self->send("save $file0");
    }
}

################
#### server ####
################
sub server {
    my $self = shift;
    my $server = shift;
    $self->{servers}->{$server} = $server;
    $self->send("server $server->{addr}", scalar(@{$self->{ports}}) - 1);
}

################
#### update ####
################
sub update {
    my $self = shift;
    my $canvas = $self->wall->{canvas};
    # may be undefined when no console window
    return if (!$canvas);
    $canvas->delete($self);
    if ($self->{raised}) {
        my $bbox0 = $self->{parent}->bbox;
        my $cmd = scalar(@{$self->{cmds}}) == 1 ? $self->{cmds}->[0] :
            (scalar(@{$self->{cmds}}) > 1 ? "multi" : "");
        $cmd =~ s/.*--view=|\s.*//g;
        $cmd = " " if (length($cmd) == 0);
        my $hsize = $canvas->width * $bbox0->[0];
        my $vsize = $canvas->height * $bbox0->[1];
        my $size = min(int($hsize / length($cmd)), int($vsize));
        $canvas->createText(
            1 + int($canvas->width * $bbox0->[2] + $hsize / 2),
            1 + int($canvas->height * $bbox0->[3] + $vsize / 2),
            -fill => 'white',
            -font => "courier -$size",
            -tags => $self,
            -text => $cmd,
        );
        $canvas->createRectangle(
            1 + int($canvas->width * $bbox0->[2]),
            1 + int($canvas->height * $bbox0->[3]),
            -1 + int($canvas->width * $bbox0->[2] + $hsize),
            -1 + int($canvas->height * $bbox0->[3] + $vsize),
            -outline => 'white',
            -tags => $self,
        );

        $self->focus(1) if ($self->{focused});
        for (my $i = 0; $i < scalar(@{$self->{ports}}); $i++) {
            my @bbox = @{$bbox0};
            $bbox[$_] += $self->{bbox}->[$i]->[$_] * $bbox[$_ - 2]
                foreach (2, 3);
            $bbox[$_] *= $self->{bbox}->[$i]->[$_] foreach (0, 1);
            my $ports0 = $self->{ports}->[$i];
            my $ports = $self->wall->run($self->{cmds}->[$i], \@bbox, $ports0);
            foreach my $dindex (keys %{$ports0}) {
                if (!$ports->{$dindex}) {
                    $self->send("quit display", $i, $dindex);
                    delete $self->{sockets}->[$i]->{$dindex};
                }
            }
            $self->{ports}->[$i] = $ports;
            foreach my $dindex (keys %{$ports}) {
                if (!$ports0->{$dindex}) {
                    foreach my $server (values %{$self->{servers}}) {
                        $self->send("server $server->{addr}", $i, $dindex);
                    }
                }
            }
            $self->send("bbox " . join(" ", @bbox), $i);
        }
    }
    $canvas->idletasks;
}

1;

