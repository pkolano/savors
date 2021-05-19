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

package Savors::View::Tree;

use Savors::FatPack::PAL;

use strict;
use Digest::CRC qw(crc32);
use File::Spec;
use MIME::Base64;
use Tk;
use Tk::JPEG;
use Treemap::Input;
use Treemap::Output::Imager;
use Treemap::Squarified;
use XML::TreePP;

use base qw(Savors::View);

our $VERSION = 2.2;

#############
#### new ####
#############
sub new {
    my $proto = shift;
    my $class = ref $proto || $proto;
    my $self = $class->SUPER::new(@_,
        "face=s,font=s,show=s,xfields=s,yfields=s");
    return undef if (!defined $self);
    bless($self, $class);

    $self->{dopts}->{face} = 'Arial';
    $self->{dopts}->{period} = 1;
    $self->{dopts}->{type} = "squarified";
    $self->{root} = {};
    my @show = split(/,/, $self->getopt('show'));
    $self->{show} = \@show;
    $self->{xfield_evals} = $self->evals($self->getopt('xfields'));
    $self->{yfield_evals} = $self->evals($self->getopt('yfields'));

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

##############
#### help ####
##############
sub help {
    my $brief = shift;
    if ($brief) {
        "     tree - various treemaps        " .
            "    tree --color=f2 --fields=f3,f2,f4,f5 --period=60\n";
    } else {
        "USAGE: env OPT=VAL... (ARGS... |...) |tree --opt=val...\n\n" .
        "TYPES: histo,squarified,weighted\n\n" .
        "OPTIONS:                                          EXAMPLES:\n" .
        "       --color=EVAL - expression to color by      " .
            "    --color=f2\n" .
        "      --ctype=CTYPE - method to assign colors by  " .
            "    --ctype=hash:ord\n" .
        "        --face=FONT - alternate font face         " .
            "    --face=Arial\n" .
        "     --fields=EVALS - expressions to plot         " .
            "    --fields=f28,f2,f3+.01\n" .
        "        --font=PATH - path to alternate font      " .
            "    --font=/usr/share/fonts/truetype/Vera.ttf\n" .
        "    --legend[=SIZE] - show color legend           \n" .
        "                        [REAL width or INT pixels]" .
            "    --legend=0.2\n" .
        "    --legend-pt=INT - legend font point size      " .
            "    --legend-pt=12\n" .
        "      --period=REAL - time between updates        " .
            "    --period=15\n" .
        "        --show=INTS - max items for each level    " .
            "    --show=10,5,10\n" .
        "     --title=STRING - title of view               " .
            "    --title=\"CPU Usage\"\n" .
        "        --type=TYPE - type of tree                " .
            "    --type=histo\n" .
        "    --xfields=EVALS - x location of each field    " .
            "    --xfields=iplong(f5)\n" .
        "    --yfields=EVALS - y location of each field    " .
            "    --yfields=iplat(f5)\n" .
        "";
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
        $self->{photo} = $self->{top}->Photo;
        $self->{canvas}->createImage(1, 1,
            -anchor => 'nw',
            -image => $self->{photo},
        );

        $self->{dopts}->{font} = File::Spec->catfile($self->{conf}->{lib_dir},
            "DejaVuSansCondensed.ttf");
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
        $self->{root} = {};
    }

    my $value = eval $self->{field_evals}->[-1];
    my $root = $self->{root};
    for (my $i = 0; $i < scalar(@{$self->{field_evals}}) - 2; $i++) {
        my $field = eval $self->{field_evals}->[$i];
        # escape xml characters
        $field =~ s/$_/'&#'.ord($_).';'/ge foreach(qw(& < > ' "));
        $root->{$field} = {} if (!defined $root->{$field});
        $root->{"$field.count"} += $value;
        $root = $root->{$field};
        if ($self->getopt('type') ne 'squarified') {
            foreach my $xy (qw(x y)) {
                if (!$root->{".$xy"} && $self->{"${xy}field_evals"}->[$i]) {
                    my $eval = eval $self->{"${xy}field_evals"}->[$i];
                    $root->{".$xy"} = $eval if ($eval);
                }
            }
        }
    }

    my $field = $self->color($data) . "," . eval $self->{field_evals}->[-2];
    if ($self->getopt('type') ne 'squarified') {
        foreach my $xy (qw(x y)) {
            $field .= "," . eval $self->{"${xy}field_evals"}->[-2]
                if ($self->{"${xy}field_evals"}->[-2]);
        }
    }
    $root->{$field} += $value;
}

##############
#### view ####
##############
sub view {
    my $self = shift;
    return if (!scalar(keys %{$self->{root}}));

    my $tm_in = Treemap::Input->new;
    my $tm_out = Treemap::Output::Imager->new(
        WIDTH => $self->{width},
        HEIGHT => $self->{height},
        FONT_FILE => ($^O eq 'MSWin32' ? undef : $self->getopt('font')),
        FONT_FACE => $self->getopt('face'),
    );
    require Treemap::Ordered;
    my $mod = "Treemap::" .
        ($self->getopt('type') eq 'squarified' ? "Squarified" : "Ordered");
    my $tm = $mod->new(
        INPUT => $tm_in, OUTPUT => $tm_out, PADDING => 1, SPACING => 1);
    my $xml = XML::TreePP->new(attr_prefix => "", force_array => [qw(children)]);
    $tm_in->{DATA} = $xml->parse(scalar($self->xml($self->{root}, "", 0)));
    $tm_in->{DATA}->{weighted} = 1 if ($self->getopt('type') eq 'weighted');
    $tm->map;
    my $image;
    $tm_out->{IMAGE}->write(data => \$image, type => 'jpeg');
    $self->{photo}->blank;
    $self->{photo}->put(encode_base64($image));
    $self->{canvas}->idletasks;
}

#############
#### xml ####
#############
sub xml {
    my $self = shift;
    my $root = shift;
    my $root_name = shift;
    my $show = shift;

    my ($root_n, $root_size, $root_x, $root_xml, $root_y);
    if (grep(/\.count/, keys(%{$root}))) {
        my $i;
        foreach my $name (sort {$root->{"$b.count"} <=> $root->{"$a.count"}}
                grep(!/\.count$|^\.x$|^\.y$/, keys(%{$root}))) {
            last if ($self->{show}->[$show] && $i == $self->{show}->[$show]);
            $i++;
            my ($xml, $size, $x, $y) =
                $self->xml($root->{$name}, $name, $show + 1);
            $root_xml .= $xml;
            $root_size += $size;
            if ($self->getopt('type') ne 'squarified') {
                $root_x += ($x - $root_x) / ($root_n + 1)
                    if (!defined $root->{".x"});
                $root_y += ($y - $root_y) / ($root_n + 1)
                    if (!defined $root->{".y"});
                $root_n++ if (!defined $root->{".x"} || !defined $root->{".y"});;
            }
        }
    } else {
        while (my ($name, $size) = each %{$root}) {
            next if ($name =~ /^\.[xy]$/);
            (my $color, $name, my $x, my $y) = split(/,/, $name);
            if ($self->getopt('type') ne 'squarified') {
                if (!$x || !$y) {
                    my $crc = crc32($name);
                    $x = $crc & 0xffff if (!$x);
                    $y = $crc >> 16 if (!$y);
                }
                $root_x += ($x - $root_x) / ($root_n + 1)
                    if (!defined $root->{".x"});
                $root_y += ($y - $root_y) / ($root_n + 1)
                    if (!defined $root->{".y"});
                $root_n++ if (!defined $root->{".x"} || !defined $root->{".y"});;
                $x = " x=\"$x\"";
                $y = " y=\"$y\"";
            }
            $root_xml .= "<children name=\"$name\" size=\"$size\" colour=\"$color\"$x$y/>";
            $root_size += $size;
        }
    }

    $root_x = $root->{".x"} if (defined $root->{".x"});
    $root_y = $root->{".y"} if (defined $root->{".x"});
    my $xml = "<children name=\"$root_name\" size=\"$root_size\" colour=\"#FFFFFF\"";
    $xml .= " x=\"$root_x\" y=\"$root_y\""
        if ($self->getopt('type') ne 'squarified');
    $root_xml = $xml . ">$root_xml</children>";
    return wantarray ? ($root_xml, $root_size, $root_x, $root_y) : $root_xml;
}

1;

# This chunk of stuff was generated by App::FatPacker. To find the original
# file's code, look for the end of this BEGIN block or the string 'FATPACK'
BEGIN {
my %fatpacked;

$fatpacked{"Treemap/Ordered.pm"} = '#line '.(1+__LINE__).' "'.__FILE__."\"\n".<<'TREEMAP_ORDERED';
  package Treemap::Ordered;
  
  use strict;
  
  require Exporter;
  require Treemap;
  
  our @ISA = qw(Exporter Treemap);
  our @EXPORT_OK = ();
  our @EXPORT = qw();
  our $VERSION = 2.2;
  
  my $weighted;
  
  sub partition {
      my $self = shift;
      my (@p, @q, $tree);
      ($tree, $p[0], $p[1], $q[0], $q[1]) = @_;
      my @nodes = @{$tree};
  
      if (scalar(@nodes) == 1) {
          my ($pt, $qt) = $self->_shrink(\@p, \@q, $self->{PADDING});
          @p = @{$pt};
          @q = @{$qt};
          $self->_map($tree->[0], @p, @q);
          return;
      }
  
      my $pq = $q[0] - $p[0] > $q[1] - $p[1] ? 0 : 1;
      my $xy = $pq ? "y" : "x";
      my $max = $q[$pq] - $p[$pq];
  
      # invert y for canvas coordinates
      my @sort = $pq ? sort {$b->{$xy} <=> $a->{$xy}} @nodes :
          sort {$a->{$xy} <=> $b->{$xy}} @nodes;
      my $size;
      $size += $_->{size} foreach (@sort);
  
      my ($med, $medsize);
      if ($size && $weighted) {
          # weighted map
          $medsize = $sort[0]->{size};
          $med = 1;
          for ($med = 1; $med < scalar(@sort); $med++) {
              last if ($medsize + $sort[$med]->{size} > $size / 2);
              $medsize += $sort[$med]->{size};
          }
          if (abs(.5 - $medsize / $size) >
                  abs(.5 - ($medsize + $sort[$med] / $size))) {
              $medsize += $sort[$med]->{size};
              $med++;
          }
      } else {
          # histomap
          $med = int(scalar(@sort) / 2);
          for (my $i = 0; $i < $med; $i++) {
              $medsize += $sort[$i]->{size};
          }
      }
  
      $size = 1 if (!$size);
      my $medpq = $p[$pq] + int($max * $medsize / $size);
      my $oldpq = $q[$pq];
      $q[$pq] = $medpq;
      $self->partition([@sort[0..$med - 1]], @p, @q);
      $p[$pq] = $medpq;
      $q[$pq] = $oldpq;
      $self->partition([@sort[$med..scalar(@sort) - 1]], @p, @q);
  }
  
  sub _map {
      my $self = shift;
      my (@p, @q, $tree);
      ($tree, $p[0], $p[1], $q[0], $q[1]) = @_;
      $weighted = 1 if ($tree->{weighted});
  
      $self->{OUTPUT}->rect($p[0], $p[1], $q[0], $q[1], $tree->{colour});
  
      if ($tree->{children} && scalar(@{$tree->{children}}) > 0) {
          my ($pt, $qt) = $self->_shrink(\@p, \@q, $self->{PADDING});
          @p = @{$pt};
          @q = @{$qt};
  
          if (scalar(@{$tree->{children}}) == 1) {
              $self->_map($tree->{children}->[0], @p, @q);
          } else {
              $self->partition($tree->{children}, @p, @q);
          }
      }
      $self->{OUTPUT}->text($p[0], $p[1], $q[0], $q[1], $tree->{name},
          $tree->{children} ? 1 : undef);
  }
  
  1;
TREEMAP_ORDERED

s/^  //mg for values %fatpacked;

my $class = 'FatPacked::'.(0+\%fatpacked);
no strict 'refs';
*{"${class}::files"} = sub { keys %{$_[0]} };

if ($] < 5.008) {
  *{"${class}::INC"} = sub {
     if (my $fat = $_[0]{$_[1]}) {
       return sub {
         return 0 unless length $fat;
         $fat =~ s/^([^\n]*\n?)//;
         $_ = $1;
         return 1;
       };
     }
     return;
  };
}

else {
  *{"${class}::INC"} = sub {
    if (my $fat = $_[0]{$_[1]}) {
      open my $fh, '<', \$fat
        or die "FatPacker error loading $_[1] (could be a perl installation issue?)";
      return $fh;
    }
    return;
  };
}

unshift @INC, bless \%fatpacked, $class;
  } # END OF FATPACK CODE

