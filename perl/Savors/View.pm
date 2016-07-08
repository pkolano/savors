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

package Savors::View;

use strict;
use Data::RandomPerson::Names::Last;
use Geo::IP;
use Getopt::Long qw(:config bundling no_ignore_case require_order);
use Graphics::ColorObject;
use IP::Anonymous;
use Math::Trig qw(pi);
use Net::Nslookup;
use String::CRC;

our $VERSION = 0.21;

my $aky;
my $drp = Data::RandomPerson::Names::Last->new;
my $gip;
my $ipa;

#############
#### new ####
#############
sub new {
    my $proto = shift;
    my $class = ref $proto || $proto;
    my $self = {};
    bless($self, $class);

    $self->{top} = shift;
    $self->{copts} = shift;
    $self->{getopt} = shift;

    $self->{color} = 0;
    $self->{colors} = {};
    $self->{conf} = {};
    $self->{legend} = 0;
    $self->{palette} = [];
    for (my $s = 1; $s > .2; $s /= 2) {
        for (my $v = 1; $v > .5; $v -= .2) {
            next if ($v < .8 && $s < .5);
            for (my $h = 0; $h < 360; $h += 30) {
                my $color = Graphics::ColorObject->new_HSV([$h, $s, $v]);
                push(@{$self->{palette}}, "#" . $color->as_RGBhex);
            }
        }
    }

    GetOptions($self->{copts},
        "color=s", "ctype=s", "fields=s", "grep=s", "label=s", "legend",
        "max=s", "min=s", "period=f", "title=s", "type=s",
        split(/,/, $self->{getopt}),
        "conf=s" => sub {
            my ($key, $val) = split(/=|\s+/, $_[1], 2);
            $val = shift @ARGV if (!defined $val);
            $self->{conf}->{$key} = $val;
        },
    ) or return undef;

    $self->{dopts}->{color} = "fC.q(:).fF";
    $self->{dopts}->{ctype} = "rr";
    $self->{dopts}->{chash} = "crc(\$_,32)";
    $self->{dopts}->{cmax} = "#FFFFFF";
    $self->{dopts}->{cmin} = "#000000";
    $self->{dopts}->{max} = 100;
    $self->{dopts}->{min} = 0;

    my $ctype = $self->getopt('ctype');
    if ($ctype =~ /^(heat):(#[0-9a-fA-F]{6}):(#[0-9a-fA-F]{6})/) {
        $self->{copts}->{ctype} = $1;
        $self->{copts}->{cmin} = $2;
        $self->{copts}->{cmax} = $3;
    } elsif ($ctype =~ /^(hash):(.*)/) {
        $self->{copts}->{ctype} = $1;
        $self->{copts}->{chash} = $2 if ($2);
    }
    my $cmin = Graphics::ColorObject->new_RGBhex($self->getopt('cmin'));
    my $cmax = Graphics::ColorObject->new_RGBhex($self->getopt('cmax'));
    $self->{labmin} = $cmin->as_Lab;
    $self->{labmax} = $cmax->as_Lab;

    $self->{chash_eval} = $self->eval($self->getopt('chash'));
    $self->{color_eval} = $self->eval($self->getopt('color'));
    $self->{field_evals} = $self->evals($self->getopt('fields'), 'fields0');

    return $self;
}

###############
#### color ####
###############
# return color of given data based on given field or --color otherwise
sub color {
    my $self = shift;
    my $data = shift;
    my $field = shift;

    $field = $self->color_field($data) if (!defined $field);
    return $field if ($field =~ /^#[0-9a-fA-F]{6}$/);
    if ($field =~ /^(#[0-9a-fA-F]{6}):(.*)$/) {
        # color was sent by data server
        (my $color, $field) = ($1, $2);
        if ($field && !$self->{colors}->{$field}) {
            $self->{colors}->{$field} = $color;
            $self->legend(uri_unescape($field), $color)
                if ($self->getopt('legend'));
        }
        return $color;
    }
    my $color = $self->{colors}->{$field};
    if (!defined $color) {
        if ($self->getopt('ctype') eq 'hash') {
            $_ = $field;
            my $val = eval $self->{chash_eval};
            $color = $self->{palette}->[$val % scalar(@{$self->{palette}})];
        } else {
            $color = $self->{palette}->[$self->{color}];
            $self->{color} = 0
                if (++$self->{color} >= scalar(@{$self->{palette}}));
        }
        $self->{colors}->{$field} = $color;
        $self->legend($field, $color) if ($self->getopt('legend'));
        return ($field => $color) if (wantarray);
    }
    return $color;
}

#####################
#### color_field ####
#####################
sub color_field {
    my $self = shift;
    my $data = shift;
    return $self->{color_eval} ? eval $self->{color_eval} : undef;
}

####################
#### color_heat ####
####################
sub color_heat {
    my $self = shift;
    my $val = shift;

    my $color;
    if (defined $self->{copts}->{cmin}) {
        my ($min, $max) = ($self->{labmin}, $self->{labmax});
        my @lab = map {(1 - $val) * $min->[$_] + $val * $max->[$_]} (0..2);
        $color = Graphics::ColorObject->new_Lab(\@lab);
    } else {
        # .7 is blue (min) and 0 is red (max) so max term drops out
        $color = Graphics::ColorObject->new_HSV([360 * (1 - $val) * .7, 1, 1]);
    }
    return "#" . $color->as_RGBhex;
}

####################
#### create_arc ####
####################
sub create_arc {
    my $self = shift;
    my $color = shift;
    my $extra = shift;
    my @x = @_[0, 1];
    my @y = @_[2, 3];
    # set the radius to the distance between points (taken from perlmonks)
    my $rad = sqrt(abs($x[0] - $x[1])**2 + abs($y[0] - $y[1])**2);
    my $q = sqrt(($x[1] - $x[0])**2 + ($y[1] - $y[0])**2);
    # $q can be zero when two adjacent fields are at the center
    return if (!$q);
    my ($x3, $y3) = (($x[0] + $x[1]) / 2, ($y[0] + $y[1]) / 2);
    my $xc = $x3 + sqrt($rad**2 - ($q / 2)**2) * ($y[0] - $y[1]) / $q;
    my $yc = $y3 + sqrt($rad**2 - ($q / 2 )**2) * ($x[1] - $x[0]) / $q;
    my $a1 = atan2(($yc - $y[0]), -($xc - $x[0])) * (180.0 / pi);

    $self->{canvas}->createArc(
        $xc - $rad, $yc - $rad, $xc + $rad, $yc + $rad,
        -extent => -60,
        -outline => $color,
        -start => $a1,
        -style => 'arc',
        %{$extra},
    );
}

##############
#### eval ####
##############
sub eval {
    my $self = shift;
    my $expr = shift;
    return undef if (!$expr);
    return "'$expr'" if ($expr =~ /^#[0-9a-fA-F]{6}$/);
    $expr =~ s/f(\d+)/"\$data->[$1]"/g;
    $expr =~ s/fL/"\$data->[-1]"/g;
    $expr =~ s/fT/(split(':', \$data->[0]))[0]/g;
    $expr =~ s/fD/(split(':', \$data->[0]))[1]/g;
    $expr =~ s/fC/(split(':', \$data->[0]))[2]/g;
    $expr =~ s/fF/(split(':', \$data->[0]))[3]/g;
    return "package Savors::View;$expr";
}

###############
#### evals ####
###############
sub evals {
    my $self = shift;
    my $exprs = shift;
    my $save = shift;

    return undef if (!$exprs);

    my $i = 0;
    my @i;
    my $open = 0;
    foreach (split(//, $exprs)) {
        $open++ if (/\(/);
        $open-- if (/\)/);
        $i++;
        push(@i, $i) if (/,/ && !$open);
    }
    push(@i, length($exprs) + 1);

    $i = 0;
    my @evals;
    foreach (@i) {
        my $expr = substr($exprs, $i, $_ - $i - 1);
        $i = $_;
        $expr =~ s/^\s*|\s*$//g;
        if ($expr =~ /^f(\d+)-fL$/) {
            push(@evals, "package Savors::View;\@{\$data}[$1..scalar(\@{\$data})-1]");
            push(@{$self->{$save}}, $expr) if ($save);
        } elsif ($expr =~ /^f(\d+)-f(\d+)$/) {
            foreach ($1..$2) {
                push(@evals, "package Savors::View;\$data->[$_]");
                push(@{$self->{$save}}, "f$_") if ($save);
            }
        } else {
            push(@evals, $self->eval($expr));
            push(@{$self->{$save}}, $expr) if ($save);
        }
    }
    return \@evals;
}

################
#### getopt ####
################
# return configured or default value for given option
sub getopt {
    my $self = shift;
    my $opt = shift;
    my $val = $self->{copts}->{$opt};
    $val = $self->{dopts}->{$opt} if (!defined $val);
    return $val;
}

##############
#### grep ####
##############
sub grep {
    my $self = shift;
    my $data = shift;
    my $grep = $self->getopt('grep');
    return !defined $grep || grep(/$grep/, @{$data});
}

##############
#### init ####
##############
sub init {
    my $self = shift;

    if (!defined $gip) {
        $gip = Geo::IP->open(File::Spec->catfile(
            $self->{conf}->{lib_dir}, "GeoLiteCity.dat"), GEOIP_STANDARD);
    }

    if (!defined $ipa) {
        my @key = map {ord} split(//, $self->{conf}->{anon_key});
        push(@key, 1..32 - scalar(@key));
        $ipa = IP::Anonymous->new(@key);
    }

    if (!defined $aky) {
        $aky = $self->{conf}->{anon_key};
    }

    $self->{height} = int($self->getopt('maxy') * $self->getopt('sheight') -
        $self->getopt('theight'));
    $self->{width} = int($self->getopt('maxx') * $self->getopt('swidth') -
        $self->getopt('twidth'));
    $self->{height} -= int(.1 * $self->{height})
        if ($self->{height} >= 128 && $self->getopt('title'));
    $self->{width} -= 64 if ($self->{width} >= 128 && $self->getopt('legend'));
}

#########################
#### ip*/host*/user* ####
#########################
sub ipanon {return $ipa->anonymize($_[0])}
sub ipcity {return ipgip(@_)->city}
sub ipcountry {return ipgip(@_)->country_name}
sub ipcountry2 {return ipgip(@_)->country_code}
sub iplat {return ipgip(@_)->latitude}
sub iplong {return ipgip(@_)->longitude}
sub ipstate {return ipgip(@_)->region_name}
sub ipstate2 {return ipgip(@_)->region}
sub ipzip {return ipgip(@_)->postal_code}
sub ipgip {return $gip->record_by_name($_[0])}
sub hostanon {return (defined $_[1] ? $_[1] : "host") .
    (crc($_[0] . $aky, 32) % 1000)}
sub hostip {return scalar(nslookup($_[0]))}
sub useranon {return substr($drp->{choice}->{data}->[
    crc($_[0] . $aky, 32) % $drp->size], 0, 8)}

###############
#### label ####
###############
sub label {
    my $self = shift;
    my $expr = shift;
    # labels is set by savors-view and not by getopt
    my $labels = $self->getopt('labels');
    $expr =~ s/fT/Time/g;
    $expr =~ s/fD/Data/g;
    $expr =~ s/fC/Color/g;
    $expr =~ s/fL/$labels->[-1]/g if ($labels);
    $expr =~ s/f(\d+)/$labels->[$1-1]/g if ($labels);
    return $expr;
}

################
#### legend ####
################
sub legend {
    my $self = shift;
    my $field = shift;
    my $color = shift;
    $self->{canvas}->createText(
        1 + $self->{width}, 1 + $self->{legend} * 10,
        -anchor => 'nw',
        -fill => $color,
        -font => 'courier -10',
        -tags => "legend",
        -text => $field,
    );
    $self->{legend}++;
}

##############
#### save ####
##############
sub save {
    my $self = shift;
    my $file = shift;
    # background not saved by postscript so recreate it explicitly via rectangle
    my $height = int($self->getopt('maxy') * $self->getopt('sheight') -
        $self->getopt('theight'));
    my $width = int($self->getopt('maxx') * $self->getopt('swidth') -
        $self->getopt('twidth'));
    $self->{canvas}->createRectangle(1, 1, $width, $height,
        -fill => 'black',
        -tags => "bg",
    );
    $self->{canvas}->raise("!bg", "bg");
    $self->{canvas}->postscript(
        -file => $file,
        -pagewidth => int($width / 72) . 'i',
    );
    $self->{canvas}->delete("bg");
}

##############
#### time ####
##############
sub time {
    my $self = shift;
    my $data = shift;
    my $time = $data->[0];
    ($time) = split(/:/, $time);
    return $time;
}

###############
#### title ####
###############
sub title {
    my $self = shift;
    $self->{canvas}->delete('title');
    my $size = int(.1 * $self->{height});
    $self->{canvas}->createText(
        1 + int($self->{width} / 2), $self->{height} + int($size / 2),
        -fill => 'white',
        -font => "courier -$size bold",
        -tags => "title",
        -text => $self->getopt('title'),
    );
}

######################
#### uri_unescape ####
######################
# return uri-unescaped version of given string
sub uri_unescape {
    my $text = shift;
    $text =~ s/%([0-9A-Fa-f]{2})/chr(hex($1))/eg if (defined $text);
    return $text;
}

1;

