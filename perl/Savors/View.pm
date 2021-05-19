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

package Savors::View;

use Savors::FatPack::MIT;
use Savors::FatPack::PAL;

use strict;
use Digest::CRC qw(crc32);
use Geo::IP2Location;
use Getopt::Long qw(:config bundling no_ignore_case require_order);
use Graphics::ColorObject;
use IP::Anonymous;
use Math::Trig qw(pi);
use Socket;

use Savors::Debug;

our $VERSION = 2.2;

my $aky;
my $gip;
my $ipa;
my @names;

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
                # remove green-cyan transition as indistinguishable
                next if ($h == 150);
                my $color = Graphics::ColorObject->new_HSV([$h, $s, $v]);
                push(@{$self->{palette}}, "#" . $color->as_RGBhex);
            }
        }
    }

    GetOptions($self->{copts},
        "color=s", "ctype=s", "fields=s", "grep=s", "label=s", "legend:s",
        "legend-pt=i", "max=s", "min=s", "period=f", "title=s", "type=s",
        split(/,/, $self->{getopt}),
        "conf=s" => sub {
            my ($key, $val) = split(/=|\s+/, $_[1], 2);
            $val = shift @ARGV if (!defined $val);
            $self->{conf}->{$key} = $val;
        },
    ) or return undef;

    $self->{dopts}->{color} = "fC";
    $self->{dopts}->{ctype} = "rr";
    $self->{dopts}->{chash} = "crc32(\$_)";
    $self->{dopts}->{chi} = "#FFFFFF";
    $self->{dopts}->{clo} = "#000000";
    $self->{dopts}->{legend} = 64;
    $self->{dopts}->{'legend-pt'} = 10;
    $self->{dopts}->{max} = 100;
    $self->{dopts}->{min} = 0;

    my $ctype = $self->getopt('ctype');
    if ($ctype =~ /^(heat)(?::(-?\d+(?:\.\d+)?):(-?\d+(?:\.\d+)?)(?::(#[0-9a-fA-F]{6}):(#[0-9a-fA-F]{6}))?)?/) {
        $self->{copts}->{ctype} = $1;
        $self->{copts}->{cmin} = defined $2 ? $2 : 0;
        $self->{copts}->{cmax} = defined $3 ? $3 : 1;
        $self->{copts}->{clo} = $4 if ($4);
        $self->{copts}->{chi} = $5 if ($5);
    } elsif ($ctype =~ /^(hash)(:.*)?/) {
        $self->{copts}->{ctype} = $1;
        $self->{copts}->{chash} = substr($2, 1) if ($2);
    }
    my $clo = Graphics::ColorObject->new_RGBhex($self->getopt('clo'));
    my $chi = Graphics::ColorObject->new_RGBhex($self->getopt('chi'));
    $self->{lablo} = $clo->as_Lab;
    $self->{labhi} = $chi->as_Lab;

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
                if (defined $self->{copts}->{legend});
        }
        return $color;
    } elsif ($self->getopt('ctype') eq 'heat') {
        return $self->color_heat($field);
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
        $self->legend($field, $color) if (defined $self->{copts}->{legend});
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

    if (defined $self->{copts}->{cmin}) {
        my ($min, $max) = ($self->{cmin}, $self->{cmax});
        if ($val <= $min) {
            $val = 0;
        } elsif ($val >= $max) {
            $val = 1;
        } else {
            # denonimator cannot be zero or else this branch cannot be taken
            $val = ($val - $min) / ($max - $min)
        }   
    }

    my $color;
    if (defined $self->{copts}->{clo}) {
        my ($lo, $hi) = ($self->{lablo}, $self->{labhi});
        my @lab = map {(1 - $val) * $lo->[$_] + $val * $hi->[$_]} (0..2);
        $color = Graphics::ColorObject->new_Lab(\@lab);
    } else {
        # .7 is blue (lo) and 0 is red (hi) so max term drops out
        $color = Graphics::ColorObject->new_HSV([360 * (1 - $val) * .7, 1, 1]);
    }
    return "#" . $color->as_RGBhex;
}

#############################
#### crc/ip*/host*/user* ####
#############################
#TODO: return dummy values when geoip not installed
sub crc {return crc32($_[0])}
sub ipanon {return $ipa->anonymize($_[0])}
sub ipcity {return ipgip(@_)->get_city}
sub ipcountry {return ipgip(@_)->get_country_long}
sub ipcountry2 {return ipgip(@_)->get_country_short}
sub iplat {return ipgip(@_)->get_latitude}
sub iplong {return ipgip(@_)->get_longitude}
sub ipstate {return ipgip(@_)->get_region}
sub ipzip {return ipgip(@_)->get_zipcode}
sub ipgip {return $gip->record_by_name($_[0])}
sub hostanon {return (defined $_[1] ? $_[1] : "host") .
    (crc($_[0] . $aky) % 1000)}
sub hostip {my $ip = gethostbyname($_[0]);
    return $ip ? scalar(inet_ntoa($ip)) : ""}
sub useranon {
    return substr($names[crc($_[0] . $aky, 32) % scalar(@names)], 0, 8)}

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
    $expr =~ s/f(\d+)-fL/"\@{\$data}[$1..scalar(\@{\$data})-1]"/g;
    $expr =~ s/f(\d+)-f(\d+)/"\@{\$data}[$1..$2]"/g;
    $expr =~ s/f(\d+)/"\$data->[$1]"/g;
    $expr =~ s/fL/"\$data->[-1]"/g;
    $expr =~ s/fT/(split(':', \$data->[0]))[0]/g;
    $expr =~ s/fD/(split(':', \$data->[0]))[1]/g;
    $expr =~ s/fC/(split(':', \$data->[0]))[2]/g;
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
    $val = $self->{dopts}->{$opt} if (!defined $val || $val eq '');
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
        $gip = Geo::IP2Location->open(File::Spec->catfile(
            $self->{conf}->{lib_dir}, "geoip.db"));
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
    if (defined $self->{copts}->{legend}) {
        my $legend = $self->getopt('legend');
        $legend = int($legend * $self->{width}) if ($legend < 1);
        $self->{width} -= $legend if ($self->{width} >= 64 + $legend);
    }
}

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
    my $pt = $self->getopt('legend-pt');
    $self->{canvas}->createText(
        1 + $self->{width}, 1 + $self->{legend} * $pt,
        -anchor => 'nw',
        -fill => $color,
        -font => "courier -$pt",
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

################
#### @names ####
################
BEGIN {
    # taken from Data::RandomPerson::Names::EnglishLast
    @names = qw(
Adams Adamson Adler Akers Akin Aleman Alexander Allen Allison Allwood Anderson
Andreou Anthony Appelbaum Applegate Arbore Arenson Armold Arntzen Askew Athanas
Atkinson Ausman Austin Averitt Avila-sakar Badders Baer Baggerly Bailliet Baird
Baker Ball Ballentine Ballew Banks Baptist-nguyen Barbee Barber Barchas Barcio
Bardsley Barkauskas Barnes Barnett Barnwell Barrera Barreto Barroso Barrow Bart
Barton Bass Bates Bavinger Baxter Bazaldua Becker Beeghly Belforte Bellamy
Bellavance Beltran Belusar Bennett Benoit Bensley Berger Berggren Bergman Berry
Bertelson Bess Beusse Bickford Bierner Bird Birdwell Bixby Blackmon Blackwell
Blair Blankinship Blanton Block Blomkalns Bloomfield Blume Boeckenhauer Bolding
Bolt Bolton Book Boucher Boudreau Bowman Boyd Boyes Boyles Braby Braden Bradley
Brady Bragg Brandow Brantley Brauner Braunhardt Bray Bredenberg Bremer Breyer
Bricout Briggs Brittain Brockman Brockmoller Broman Brooks Brown Brubaker Bruce
Brumfield Brumley Bruning Buck Budd Buhler Buhr Burleson Burns Burton Bush
Butterfield Byers Byon Byrd Bzostek Cabrera Caesar Caffey Caffrey Calhoun Call
Callahan Campbell Cano Capri Carey Carlisle Carlson Carmichael Carnes Carr
Carreira Carroll Carson Carswell Carter Cartwright Cason Cates Catlett Caudle
Cavallaro Cave Cazamias Chabot Chance Chapman Characklis Cheatham Chen Chern
Cheville Chong Christensen Church Claibourn Clark Clasen Claude Close Coakley
Coffey Cohen Cole Collier Conant Connell Conte Conway Cooley Cooper Copeland
Coram Corbett Cort Cortes Cousins Cowsar Cox Coyne Crain Crankshaw Craven
Crawford Cressman Crestani Crier Crocker Cromwell Crouse Crowder Crowe Culpepper
Cummings Cunningham Currie Cusey Cutcher Cyprus D'ascenzo Dabak Dakoulas Daly
Dana Danburg Danenhauer Darley Darrouzet Dartt Daugherty Davila Davis Dawkins
Day Dehart Demoss Demuth Devincentis Deaton Dees Degenhardt Deggeller Deigaard
Delabroy Delaney Demir Denison Denney Derr Dettweiler Deuel Devitt Diamond
Dickinson Dietrich Dilbeck Dobson Dodds Dodson Doherty Dooley Dorsey Dortch
Doughty Dove Dowd Dowling Drescher Drucker Dryer Dryver Duckworth Dunbar Dunham
Dunn Duston Dyson Eason Eaton Ebert Eckhoff Edelman Edmonds Eichhorn Eisbach
Elders Elias Elijah Elizabeth Elliott Elliston Elms Emerson Engelberg Engle
Eplett Epp Erickson Estades Etezadi Evans Ewing Fair Farfan Fargason Farhat
Farry Fawcett Faye Federle Felcher Feldman Ferguson Fergusson Fernandez Ferrer
Fine Fineman Fisher Flanagan Flathmann Fleming Fletcher Folk Fortune Fossati
Foster Foulston Fowler Fox Francis Frantom Franz Frazer Fredericks Frey Freymann
Fuentes Fuller Fundling Furlong Gainer Galang Galeazzi Gamse Gannaway Garcia
Gardner Garneau Gartler Garverick Garza Gatt Gattis Gayman Geiger Gelder George
Gerbino Gerbode Gibson Gifford Gillespie Gillingham Gilpin Gilyot Girgis
Gjertsen Glantz Glaze Glenn Glotzbach Gobble Gockenbach Goff Goffin Golden
Goldwyn Gomez Gonzalez Good Graham Gramm Granlund Grant Gray Grayson Greene
Greenslade Greenwood Greer Griffin Grinstein Grisham Gross Grove Guthrie Guyton
Haas Hackney Haddock Hagelstein Hagen Haggard Haines Hale Haley Hall Halladay
Hamill Hamilton Hammer Hancock Hane Hansen Harding Harless Harms Harper Harrigan
Harris Harrison Hart Harton Hartz Harvey Hastings Hauenstein Haushalter Haven
Hawes Hawkins Hawley Haygood Haylock Hazard Heath Heidel Heins Hellums Hendricks
Henry Henson Herbert Herman Hernandez Herrera Hertzmann Hewitt Hightower
Hildebrand Hill Hindman Hirasaki Hirsh Hochman Hocker Hoffman Hoffmann Holder
Holland Holloman Holstein Holt Holzer Honeyman Hood Hooks Hopper Horne House
Houston Howard Howell Howley Huang Hudgings Huffman Hughes Humphrey Hunt Hunter
Hurley Huston Hutchinson Hyatt Irving Jacobs Jaramillo Jaranson Jarboe Jarrell
Jenkins Johnson Johnston Jones Joy Juette Julicher Jumper Kabir Kamberova Kamen
Kamine Kampe Kane Kang Kapetanovic Kargatis Karlin Karlsson Kasbekar Kasper
Kastensmidt Katz Kauffman Kavanagh Kaydos Kearsley Keleher Kelly Kelty Kendrick
Key Kicinski Kiefer Kielt Kim Kimmel Kincaid King Kinney Kipp Kirby Kirk
Kirkland Kirkpatrick Klamczynski Klein Kopnicky Kotsonis Koutras Kramer Kremer
Krohn Kuhlken Kunitz Lalonde Lavalle Laware Lacy Lam Lamb Lampkin Lane Langston
Lanier Larsen Lassiter Latchford Lawera Leblanc Legrand Leatherbury Lebron
Ledman Lee Leinenbach Leslie Levy Lewis Lichtenstein Lisowski Liston Litvak
Llano-restrepo Lloyd Lock Lodge Logan Lomonaco Long Lopez Lopez-bassols Loren
Loughridge Love Ludtke Luers Lukes Luxemburg Macallister Macleod Mackey Maddox
Magee Mallinson Mann Manning Manthos Marie Marrow Marshall Martin Martinez
Martisek Massey Mathis Matt Maxwell Mayer Mazurek Mcadams Mcafee Mcalexander
Mcbride Mccarthy Mcclure Mccord Mccoy Mccrary Mccrossin Mcdonald Mcelfresh
Mcfarland Mcgarr Mcghee Mcgoldrick Mcgrath Mcguire Mckinley Mcmahan Mcmahon
Mcmath Mcnally Mcdonald Meade Meador Mebane Medrano Melton Merchant Merwin
Millam Millard Miller Mills Milstead Minard Miner Minkoff Minnotte Minyard Mirza
Mitchell Money Monk Montgomery Monton Moore Moren Moreno Morris Morse Moss Moyer
Mueller Mull Mullet Mullins Munn Murdock Murphey Murphy Murray Murry Mutchler
Myers Myrick Nassar Nathan Nazzal Neal Nederveld Nelson Nguyen Nichols Nielsen
Nockton Nolan Noonan Norbury Nordlander Norris Norvell Noyes Nugent Nunn O'brien
O'connell O'neill O'steen Ober Odegard Oliver Ollmann Olson Ongley Ordway Ortiz
Ouellette Overcash Overfelt Overley Owens Page Paige Pardue Parham Parker Parks
Patterson Patton Paul Payne Peck Penisson Percer Perez Perlioni Perrino Peterman
Peters Pfeiffer Phelps Philip Philippe Phillips Pickett Pippenger Pistole
Platzek Player Poddar Poirier Poklepovic Polk Polking Pond Popish Porter Pound
Pounds Powell Powers Prado Preston Price Prichep Priour Prischmann Pryor Puckett
Raglin Ralston Rampersad Ratner Rawles Ray Read Reddy Reed Reese Reeves
Reichenbach Reifel Rein Reiten Reiter Reitmeier Reynolds Rhinehart Richardson
Rider Ritchie Rittenbach Roberts Robinson Rodriguez Rogers Roper Rosemblun Rosen
Rosenberg Rosenblatt Ross Roth Rowatt Roy Royston Rozendal Rubble Ruhlin Rupert
Russell Ruthruff Ryan Rye Sabry Sachitano Sachs Sammartino Sands Saunders Savely
Scales Schaefer Schafer Scheer Schild Schlitt Schmitz Schneider Schoenberger
Schoppe Scott Seay Segura Selesnick Self Seligmann Sewall Shami Shampine Sharp
Shaw Shefelbine Sheldon Sherrill Shidle Shifley Shillingsburg Shisler Shopbell
Shupack Sievert Simpson Sims Sissman Smayling Smith Snyder Solomon Solon Soltero
Sommers Sonneborn Sorensen Southworth Spear Speight Spencer Spruell Spudich
Stacy Staebel Steele Steinhour Steinke Stepp Stevens Stewart Stickel Stine
Stivers Stobb Stone Stratmann Stubbers Stuckey Stugart Sullivan Sultan Sumrall
Sunley Sunshine Sutton Swaim Swales Sweed Swick Swift Swindell Swint Symonds
Syzdek Szafranski Takimoto Talbott Talwar Tanner Taslimi Tate Tatum Taylor
Tchainikov Terk Thacker Thomas Thompson Thomson Thornton Thurman Thurow Tilley
Tolle Towns Trafton Tran Trevas Trevino Triggs Truchard Tunison Turner Twedell
Tyler Tyree Unger Van Vanderzanden Vanlandingham Varanasi Varela Varman Venier
Verspoor Vick Visinsky Voltz Wagner Wake Walcott Waldron Walker Wallace Walters
Walton Ward Wardle Warnes Warren Washington Watson Watters Webber Weidenfeller
Weien Weimer Weiner Weinger Weinheimer Weirich Welch Wells Wendt West
Westmoreland Wex Whitaker White Whitley Wiediger Wilburn Williams Williamson
Willman Wilson Winger Wise Wisur Witt Wong Woodbury Wooten Workman Wright Wyatt
Yates Yeamans Yen York Yotov Younan Young Zeldin Zettner Ziegler Zitterkopf
Zucker
    );
}

1;

