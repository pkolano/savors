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

package Savors::Console::Window;

use strict;
use IO::Socket::INET;
use IO::Socket::UNIX;
use List::Util qw(min);
use POSIX;
use Time::HiRes qw(sleep time);

use base qw(Savors::Console::Level);
use Savors::Console::Layout;
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
    $self->{atime} = time;
    $self->{cmd} = undef;
    $self->{colors} = {};
    $self->{cursor} = "1.0";
    $self->{focused} = 0;
    $self->{insert} = 0;
    $self->{layout} = undef;
    $self->{ports} = undef;
    $self->{raised} = 0;
    $self->{sockets} = {};
    $self->{text} = "";

    return $self;
}

##############
#### blur ####
##############
sub blur {
    my $self = shift;
    my $text = $self->wall->text;
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
        my $text = $self->wall->text;
        if ($text) {
            $text->Contents($self->{text});
            $text->SetCursor($self->{cursor});
        }
        $self->{focused} = 1;
    }

    my $canvas = $self->wall->canvas;
    if ($canvas) {
        my $bbox = $self->bbox;
        $canvas->delete('focus');
        $canvas->createRectangle(
            1 + int($canvas->width * $bbox->[2]),
            1 + int($canvas->height * $bbox->[3]),
            -1 + int($canvas->width * ($bbox->[2] + $bbox->[0])),
            -1 + int($canvas->height * ($bbox->[3] + $bbox->[1])),
            -fill => '#002b36',
            -tags => 'focus',
        );
        $canvas->lower('focus');
        $canvas->idletasks;
    }
}

################
#### insert ####
################
sub insert {
    my $self = shift;
    my $val = shift;
    $self->{insert} = $val if (defined $val);
    return $self->{insert};
}

###############
#### lower ####
###############
sub lower {
    my $self = shift;
    $self->{layout}->lower if ($self->{layout});
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
    $self->{layout}->raise if ($self->{layout});
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
    if ($self->{layout}) {
        $self->{layout}->remove(1);
        $self->{layout} = undef;
    } 
    my $canvas = $self->wall->canvas;
    $canvas->delete($self) if ($canvas);
    if ($self->{ports}) {
        $self->send("quit");
        close $_ foreach (values %{$self->{sockets}});
        $self->{ports} = undef;
        $self->{sockets} = {};
    }
    $self->{cmd} = undef;
    $self->{colors} = {};
    $self->{servers} = {};
}

#############
#### run ####
#############
sub run {
    my $self = shift;
    my $cmds = shift;
    my $layout = shift;

    if (!$cmds) {
        return 1 if ($self->{layout} || $self->{cmd});
        return 0;
    }
    if ($layout) {
        $self->{layout} = Savors::Console::Layout->new($self);
        $self->{layout}->run($cmds, $layout);
        $self->{layout}->update;
    } else {
        $self->{cmd} = $cmds->[0]->[0];
        $self->update;
        $self->{ports} = $self->wall->run($self->{cmd}, $self->bbox);
        $self->server($_) foreach (@{$cmds->[0]->[1]});
    }
}

##############
#### save ####
##############
sub save {
    my $self = shift;
    my $file = shift;
    if ($self->{layout}) {
        $self->{layout}->save($file);
    } else {
        $self->send("save $file");
        sleep 0.1 while (! -e "$file.done");
        unlink "$file.done";
    }
}

##############
#### send ####
##############
sub send {
    my $self = shift;
    my $msg = shift;
    my $dindex0 = shift;

    if ($self->{layout}) {
        return $self->{layout}->send($msg);
    } elsif ($msg && $self->{ports}) {
        while (my ($dindex, $port) = each %{$self->{ports}}) {
            next if (defined $dindex0 && $dindex != $dindex0);
            my $sock = $self->{sockets}->{$dindex};
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
                $self->{sockets}->{$dindex} = $sock;
                sleep 0.1 while (!$sock->connected);
            }
            syswrite($sock, "$msg\n");
        }
        #TODO: need error checking for socket (i.e. still exists)
    }
    return [values %{$self->{sockets}}];
}

################
#### server ####
################
sub server {
    my $self = shift;
    my $server = shift;
    if ($self->{layout}) {
        return $self->{layout}->server($server);
    } elsif (defined $server) {
        $self->{servers}->{$server} = $server;
        $self->send("server $server->{addr}");
    }
    return $self->{servers};
}

################
#### update ####
################
sub update {
    my $self = shift;
    if ($self->{layout}) {
        $self->{layout}->update;
        $self->focus(1) if ($self->{focused});
        return;
    }
    my $bbox = $self->bbox;
    # may be undefined when no console window
    my $canvas = $self->wall->canvas;
    if ($canvas) {
        $canvas->delete($self);
        if ($self->{raised}) {
            my $cmd = $self->{cmd};
            $cmd =~ s/.*--view=|\s.*//g;
            $cmd = " " if (length($cmd) == 0);
            my $hsize = $canvas->width * $bbox->[0];
            my $vsize = $canvas->height * $bbox->[1];
            my $size = min(int($hsize / length($cmd)), int($vsize));
            $canvas->createText(
                1 + int($canvas->width * $bbox->[2] + $hsize / 2),
                1 + int($canvas->height * $bbox->[3] + $vsize / 2),
                -fill => 'white',
                -font => "courier -$size",
                -tags => $self,
                -text => $cmd,
            );
            $canvas->createRectangle(
                1 + int($canvas->width * $bbox->[2]),
                1 + int($canvas->height * $bbox->[3]),
                -1 + int($canvas->width * $bbox->[2] + $hsize),
                -1 + int($canvas->height * $bbox->[3] + $vsize),
                -outline => 'white',
                -tags => $self,
            );
        }
    }

    $self->focus(1) if ($self->{focused});
    my $ports0 = $self->{ports};
    return if (!$ports0);
    my $ports = $self->wall->run($self->{cmd}, $bbox, $ports0);
    foreach my $dindex (keys %{$ports0}) {
        if (!$ports->{$dindex}) {
            $self->send("quit display", $dindex);
            delete $self->{sockets}->{$dindex};
        }
    }
    $self->{ports} = $ports;
    foreach my $dindex (keys %{$ports}) {
        if (!$ports0->{$dindex}) {
            foreach my $server (values %{$self->{servers}}) {
                $self->send("server $server->{addr}", $dindex);
            }
        }
    }
    $self->send("bbox " . join(" ", @{$bbox}));
    $canvas->idletasks if ($canvas);
}

1;

