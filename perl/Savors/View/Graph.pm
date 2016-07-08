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

package Savors::View::Graph;

use strict;
use File::Temp;
use GD;
use Graph::Easy;
use Graph::Easy::As_svg;
use IPC::Open2;
use MIME::Base64;
use POSIX;
use Tie::IxHash;
use Tk;
use Tk::PNG;
use XML::Simple;

use base qw(Savors::View);

our $VERSION = 0.21;

#############
#### new ####
#############
sub new {
    my $proto = shift;
    my $class = ref $proto || $proto;
    my $self = $class->SUPER::new(@_, "cdefault=s,swap=s,timeout=i");
    return undef if (!defined $self);
    bless($self, $class);

    $self->{dopts}->{cdefault} = "#99CC00";
    $self->{dopts}->{dpi} = 96;
    $self->{dopts}->{period} = 1;
    $self->{dopts}->{timeout} = 60;
    $self->{dopts}->{type} = "twopi";
    $self->{label_eval} = $self->eval($self->getopt('label'));
    $self->{swap_eval} = $self->eval($self->getopt('swap'));
    $self->{time} = 0;

    if ($self->getopt('type') eq 'easy') {
        $self->{easy} = Graph::Easy->new(timeout => $self->getopt('timeout'));
    } else {
        $self->{nodes} = {};
        if ($self->getopt('type') eq 'sequence') {
            $self->{edges} = [];
            tie(%{$self->{nodes}}, 'Tie::IxHash');
        } else {
            $self->{edges} = {};
        }
    }

    return $self;
}

##############
#### bbox ####
##############
sub bbox {
    my $self = shift;
    $self->init;
    $self->view;
}

###############
#### color ####
###############
sub color {
    my $self = shift;
    my $data = shift;
    my $field = shift;

    my $fC = (split(':', $data->[0]))[2];
    if (!$self->{copts}->{color} && !$fC && wantarray) {
        my @fields = map {eval} @{$self->{field_evals}};
        my @fields = map {s/,//g; $_} @fields;
        my %cnew;
        foreach my $cfield (@fields) {
            $cnew{$cfield} = $self->SUPER::color($data, $cfield)
                if (!defined $self->{colors}->{$cfield});
        }
        return %cnew;
    } elsif (wantarray) {
        return ($self->SUPER::color($data, $field));
    } else {
        return $self->SUPER::color($data, $field);
    }
}

##############
#### help ####
##############
sub help {
    my $brief = shift;
    if ($brief) {
        "    graph - various graphs          " .
            "    graph --color=f2 --fields=f15,f1 --period=15 --type=fdp\n";
    } else {
        "USAGE: env OPT=VAL... (ARGS... |...) |graph ...\n\n" .
        "TYPES: circo,dot,easy,fdp,neato,sequence,sfdp,twopi\n\n" .
        "OPTIONS:                                           EXAMPLES:\n" .
        "        --color=EVAL - expression to color edges by" .
            "    --color=f6\n" .
        "    --cdefault=COLOR - default node/edge color     " .
            "    --cdefault='#ccff00'\n" .
        "       --ctype=CTYPE - method to assign colors by  " .
            "    --ctype=hash:ord\n" .
        "      --fields=EVALS - expressions denoting edges  " .
            "    --fields=f4,f6\n" .
        "        --label=EVAL - expression to label edges by" .
            "    --label=f2\n" .
        "            --legend - show color legend           " .
            "    --legend\n" .
        "          --max=INTS - max value of each field     " .
            "    --max=100,10,50\n" .
        "          --min=INTS - min value of each field     " .
            "    --min=50,0,10\n" .
        "       --period=REAL - time between updates        " .
            "    --period=15\n" .
        "         --swap=EVAL - condition to reverse edge   " .
            "    --swap='f5>10000'\n" .
        "       --timeout=INT - easy layout timeout         " .
            "    --timeout=60\n" .
        "      --title=STRING - title of view               " .
            "    --title=\"CPU Usage\"\n" .
        "         --type=TYPE - type of graph               " .
            "    --type=circo\n" .
        "",
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
        if ($self->getopt('type') ne 'easy') {
            $self->{photo} = $self->{top}->Photo;
            $self->{canvas}->createImage(1, 1,
                -anchor => 'nw',
                -image => $self->{photo},
            );
        }
    } else {
        $self->{canvas}->move('legend', $self->{width} - $oldx, 0);
    }
    $self->title if ($self->getopt('title'));
}

##############
#### play ####
##############
sub play {
    my $self = shift;
    my $data = shift;
    my $raised = shift;

    if ($data->[0] eq 'savors_eof') {
        $self->view if ($raised);
        return;
    }
    my $time = int($self->time($data));
    if ($time >= $self->{time} + $self->getopt('period')) {
        $self->view if ($raised && $self->{time} > 0);
        $self->{time} = $time;
        if ($self->getopt('type') eq 'easy') {
            $self->{easy} = Graph::Easy->new(timeout => $self->{timeout});
        } else {
            $self->{nodes} = {};
            if ($self->getopt('type') eq 'sequence') {
                $self->{edges} = [];
                tie(%{$self->{nodes}}, 'Tie::IxHash');
            } else {
                $self->{edges} = {};
            }
        }
    }

    my @fields = map {eval} @{$self->{field_evals}};
    my @fields = map {s/,//g; $_} @fields;
    my $src = shift @fields;
    my $fC = (split(':', $data->[0]))[2];
    my $color = $self->{copts}->{color} || $fC ?
        $self->color($data) : $self->getopt('cdefault');
    my $label = eval $self->{label_eval};
    # remove commas and quotes so don't interfere with join/tool input
    $label =~ s/[,"]//g;
    my $swap = $self->{swap_eval} && eval $self->{swap_eval};
    foreach (@fields) {
        my @edge = ($src, $_);
        @edge = reverse @edge if ($swap);
        my @colors = $self->{copts}->{color} || $fC ?
            map {$self->getopt('cdefault')} @edge :
            map {scalar($self->color($data, $_))} @edge;
 
        for (my $i = 0; $i < scalar(@edge); $i++) {
            my ($field, $color) = ($edge[$i], $colors[$i]);
            if ($self->getopt('type') eq 'easy') {
                my $node = $self->{easy}->add_node($field);
                $node->set_attribute('fill', $color);
            } else {
                $self->{nodes}->{$field} = $color;
            }
        }

        if ($self->getopt('type') eq 'easy') {
            my $edge = $self->{easy}->add_edge_once($edge[0], $edge[1]);
            return if (!$edge);
            $edge->set_attribute('color', $color);
            $edge->set_attribute('label', $label) if ($label);
        } else {
            push(@edge, $color, $label);
            my $join = join(",", @edge);
            if ($self->getopt('type') eq 'sequence') {
                push(@{$self->{edges}}, $join)
                    if ($self->{edges}->[-1] ne $join);
            } else {
                $self->{edges}->{$join} = 1;
            }
        }
    }
}

##############
#### view ####
##############
sub view {
    my $self = shift;
    if ($self->getopt('type') eq 'easy') {
        $self->view_easy;
    } else {
        return if (!scalar(keys %{$self->{nodes}}));
        if ($self->getopt('type') eq 'sequence') {
            $self->view_sequence;
        } else {
            $self->view_graphviz;
        }
    }
}

###################
#### view_easy ####
###################
sub view_easy {
    my $self = shift;
    $self->{easy}->set_attribute('flow', 'east')
        if ($self->{width} > $self->{height});

#TODO: handle labels
    my $easy_svg = $self->{easy}->as_svg;
    if (!$easy_svg) {
        $self->{canvas}->createText(1, 1,
            -anchor => 'nw',
            -fill => 'white',
            -font => 'courier',
            -text => "graph layout could not be completed in " .
                $self->getopt('timeout') . " seconds",
        );
        $self->{canvas}->idletasks;
        # return may be undefined during timeout
        return;
    }
    my $svg = XMLin($easy_svg,
        ForceArray => [qw(g line)], KeyAttr => [], NormalizeSpace => 2);
    my $sx = 1.0 * $self->{width} / $svg->{width};
    my $sy = 1.0 * $self->{height} / $svg->{height};
    $self->{canvas}->delete('!legend');
    foreach my $g (@{$svg->{g}}) {
        if ($g->{rect}) {
            $self->{canvas}->createRectangle(
                int($sx * $g->{rect}->{x}),
                int($sy * $g->{rect}->{y}),
                int($sx * ($g->{rect}->{x} + $g->{rect}->{width})),
                int($sy * ($g->{rect}->{y} + $g->{rect}->{height})),
                -fill => $g->{rect}->{fill},
            );
            if ($g->{text}) {
                my $hsize = int($sy * ($g->{rect}->{height} - 8));
                my $wsize = int($sx * $g->{rect}->{width} /
                    (length $g->{text}->{content}));
                if ($hsize >= 4 && $wsize >= 4) {
                    my $font = $self->{top}->Font(
                        -family => 'helvetica',
                        -size => $hsize < $wsize ? $hsize : $wsize,
                    );
                    $self->{canvas}->createText(
                        int($sx * $g->{text}->{x}),
                        int($sy * $g->{text}->{y}),
                        -fill => $g->{text}->{fill},
                        -font => $font,
                        -text => $g->{text}->{content},
                    );
                }
            }
        }
        if ($g->{line}) {
            my @xya;
            if ($g->{use}) {
                my @use = ref($g->{use}) eq 'ARRAY' ? @{$g->{use}} : ($g->{use});
                foreach my $use (@use) {
                    if ($use->{transform} =~
                            /translate\(([\d.]+)\s+([\d.]+)\)rotate\(([\d-]+)\)/) {
                        push(@xya, {x => $1, y => $2,
                            a => $3 == -90 || $3 == 180 ? 'first' : 'last'});
                    } else {
                        push(@xya, {x => $use->{x}, y => $use->{y}, a => 'last'});
                    }
                }
            }
            my @lines = @{$g->{line}};
            if ($g->{g}) {
                foreach my $g2 (@{$g->{g}}) {
                    foreach my $line2 (@{$g2->{line}}) {
                        $line2->{stroke} = $g2->{stroke};
                        push(@lines, $line2);
                    }
                }
            }
            foreach my $line (@lines) {
                my %a;
                foreach my $xya (@xya) {
                    if (abs($line->{x1} - $xya->{x}) == 1 ||
                            abs($line->{x2} - $xya->{x}) == 1 ||
                            abs($line->{y1} - $xya->{y}) == 1 ||
                            abs($line->{y2} - $xya->{y}) == 1) {
                        $a{-arrow} = $xya->{a};
                        last;
                    }
                }
                $self->{canvas}->createLine(
                    int($sx * $line->{x1}), int($sy * $line->{y1}),
                    int($sx * $line->{x2}), int($sy * $line->{y2}),
                    -fill => $line->{stroke},
                    %a,
                );
            }
        }
    }
    $self->{canvas}->idletasks;
}

#######################
#### view_graphviz ####
#######################
sub view_graphviz {
    my $self = shift;
    my ($in, $out);
    my $pid = open2($in, $out, qw(dot -Tpng));
    print $out "digraph view {\n";
    print $out "bgcolor=black;\n";
    print $out "layout=", $self->getopt('type'), ";\n";
    # never use overlap=scale as it can take very long for large graphs
    print $out "ratio=fill;\n";
    print $out "size=\"", 1.0 * $self->{width} / $self->getopt('dpi'), ",",
        1.0 * $self->{height} / $self->getopt('dpi'), "\";\n";
    print $out "node [style=filled];\n";

    while (my ($label, $color) = each %{$self->{nodes}}) {
        print $out "\"$label\" [label=\"$label\", color=\"$color\"];\n";
    }
    foreach (keys(%{$self->{edges}})) {
        my ($src, $dst, $color, $label) = split(/,/);
        my $l = $label ? ", label=\"$label\", fontcolor=\"$color\"" : "";
        print $out "\"$src\" -> \"$dst\" [color=\"$color\"$l];\n";
    }
    print $out "}";
    close $out;
 
    my $image;
    $image .= $_ while (<$in>);
    close $in;
    waitpid($pid, 0);

    $self->{photo}->blank;
    $self->{photo}->put(encode_base64($image));
    $self->{canvas}->idletasks;
}

#######################
#### view_sequence ####
#######################
sub view_sequence {
    my $self = shift;
    my $fh = File::Temp->new;
    my $file = $fh->filename;
    close $fh;
    my ($in, $out);
    my $pid = open2($in, $out, "mscgen", "-Tpng", "-o$file");
    print $out "msc {\n";
    print $out "width=\"", $self->{width}, "\";\n";

    my $comma = 0;
    while (my ($label, $color) = each %{$self->{nodes}}) {
        print $out ",\n" if ($comma);
        print $out "\"$label\" [textcolor=\"$color\"]";
        $comma = 1;
    }
    print $out ";\n";

    foreach my $edge (@{$self->{edges}}) {
        my ($src, $dst, $color, $label) = split(/,/, $edge);
        my $l = $label ? "label=\"$label\", " : "";
        print $out "\"$src\" => \"$dst\" [$l";
        print $out "linecolor=\"$color\", textcolor=\"$color\"];\n";
    }
    print $out "}";
    close $out;
    close $in;
    waitpid($pid, 0);
 
    # resize and swap black/white
    my $gd0 = GD::Image->new($file);
    my $white = $gd0->colorClosest(255, 255, 255);
    my $black = $gd0->colorClosest(0, 0, 0);
    $gd0->colorDeallocate($white);
    $gd0->colorAllocate(0, 0, 0);
    $gd0->colorDeallocate($black);
    $gd0->colorAllocate(255, 255, 255);
    my $gd = GD::Image->new($self->{width}, $self->{sheight}, 1);
    $gd->copyResampled($gd0, 0, 0, 0, 0,
        $gd->width, $gd->height, $gd0->width, $gd0->height);
    $self->{photo}->blank;
    $self->{photo}->put(encode_base64($gd->png));
    $self->{canvas}->idletasks;
}

1;

