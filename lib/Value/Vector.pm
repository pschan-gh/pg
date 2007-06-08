########################################################################### 
#
#  Implements Vector class
#
package Value::Vector;
my $pkg = 'Value::Vector';

use strict;
our @ISA = qw(Value);

#
#  Convert a value to a Vector.  The value can be
#    a list of numbers, or an reference to an array of numbers
#    a point or vector object (demote a vector)
#    a matrix if it is  n x 1  or  1 x n
#    a string that parses to a vector
#
sub new {
  my $self = shift; my $class = ref($self) || $self;
  my $context = (Value::isContext($_[0]) ? shift : $self->context);
  my $p = shift; $p = [$p,@_] if (scalar(@_) > 0);
  $p = Value::makeValue($p,context=>$context) if (defined($p) && !ref($p));
  return $p if (Value::isFormula($p) && $p->type eq Value::class($self));
  my $pclass = Value::class($p); my $isFormula = 0;
  my @d; @d = $p->dimensions if $pclass eq 'Matrix';
  if ($pclass =~ m/Point|Vector/) {$p = $p->data}
  elsif ($pclass eq 'Matrix' && scalar(@d) == 1) {$p = [$p->value]}
  elsif ($pclass eq 'Matrix' && scalar(@d) == 2 && $d[0] == 1) {$p = ($p->value)[0]}
  elsif ($pclass eq 'Matrix' && scalar(@d) == 2 && $d[1] == 1) {$p = ($p->transpose->value)[0]}
  else {
    $p = [$p] if (defined($p) && ref($p) ne 'ARRAY');
    Value::Error("Vectors must have at least one coordinate") unless defined($p) && scalar(@{$p}) > 0;
    foreach my $x (@{$p}) {
      $x = Value::makeValue($x,context=>$context);
      $isFormula = 1 if Value::isFormula($x);
      Value::Error("Coordinate of Vector can't be %s",Value::showClass($x))
        unless Value::isNumber($x);
    }
  }
  if ($isFormula) {
    my $v = $self->formula($p);
    if (ref($self) && $self->{ColumnVector}) {
      $v->{tree}{ColumnVector} = 1;
      $v->{tree}{open} = $v->{tree}{close} = undef;
    }
    return $v;
  }
  my $v = bless {data => $p, context => $context}, $class;
  $v->{ColumnVector} = 1 if ref($self) && $self->{ColumnVector};
  return $v;
}

#
#  Try to promote arbitary data to a vector
#
sub promote {
  my $self = shift; my $class = ref($self) || $self;
  my $x = (scalar(@_) ? shift : $self);
  return $self->new($x,@_) if scalar(@_) > 0 || ref($x) eq 'ARRAY';
  return $x if ref($x) eq $class;
  return $self->make($x->value) if Value::class($x) eq 'Point';
  Value::Error("Can't convert %s to %s",Value::showClass($x),Value::showClass($self));
}

############################################
#
#  Operations on vectors
#

#
#  Don't automatically promote to Vectors for these
#
sub _mult  {Value::binOp(@_,"mult")}
sub _div   {Value::binOp(@_,"div")}
sub _power {Value::binOp(@_,"power")}

sub add {
  my ($l,$r) = @_; my $self = $l;
  my @l = $l->value; my @r = $r->value;
  Value::Error("Vector addition with different number of coordinates")
    unless scalar(@l) == scalar(@r);
  my @s = ();
  foreach my $i (0..scalar(@l)-1) {push(@s,$l[$i] + $r[$i])}
  return $self->make(@s);
}

sub sub {
  my ($self,$l,$r) = Value::checkOpOrder(@_);
  my @l = $l->value; my @r = $r->value;
  Value::Error("Vector subtraction with different number of coordinates")
    unless scalar(@l) == scalar(@r);
  my @s = ();
  foreach my $i (0..scalar(@l)-1) {push(@s,$l[$i] - $r[$i])}
  return $self->make(@s);
}

sub mult {
  my ($l,$r,$flag) = @_; my $self = $l;
  Value::Error("Vectors can only be multiplied by numbers")
    unless (Value::matchNumber($r) || Value::isComplex($r));
  my @coords = ();
  foreach my $x ($l->value) {push(@coords,$x*$r)}
  return $self->make(@coords);
}

sub div {
  my ($l,$r,$flag) = @_; my $self = $l;
  Value::Error("Can't divide by a Vector") if $flag;
  Value::Error("Vectors can only be divided by numbers")
    unless (Value::matchNumber($r) || Value::isComplex($r));
  Value::Error("Division by zero") if $r == 0;
  my @coords = ();
  foreach my $x ($l->value) {push(@coords,$x/$r)}
  return $self->make(@coords);
}

sub power {
  my ($l,$r,$flag) = @_;
  Value::Error("Can't raise Vectors to powers") unless $flag;
  Value::Error("Can't use Vectors in exponents");
}

sub dot {
  my ($l,$r,$flag) = @_; my $self = $l;
  my @l = $l->value; my @r = $r->value;
  Value::Error("Vector dot product with different number of coordinates")
    unless scalar(@l) == scalar(@r);
  my $s = 0;
  foreach my $i (0..scalar(@l)-1) {$s += $l[$i] * $r[$i]}
  return $s;
}

sub cross {
  my ($l,$r,$flag) = @_; my $self = $l;
  my @l = $l->value; my @r = $r->value;
  Value::Error("Vector must be in 3-space for cross product")
    unless scalar(@l) == 3 && scalar(@r) == 3;
  $pkg->make($l[1]*$r[2] - $l[2]*$r[1],
           -($l[0]*$r[2] - $l[2]*$r[0]),
             $l[0]*$r[1] - $l[1]*$r[0]);
}

#
#  If points are different length, shorter is smaller,
#  Otherwise, do lexicographic comparison.
#
sub compare {
  my ($self,$l,$r) = Value::checkOpOrder(@_);
  my @l = $l->value; my @r = $r->value;
  return scalar(@l) <=> scalar(@r) unless scalar(@l) == scalar(@r);
  my $cmp = 0;
  foreach my $i (0..scalar(@l)-1) {
    $cmp = $l[$i] <=> $r[$i];
    last if $cmp;
  }
  return $cmp;
}

sub neg {
  my $self = promote(@_); my @coords = ();
  foreach my $x ($self->value) {push(@coords,-$x)}
  return $self->make(@coords);
}

sub abs {my $self = shift; $self->norm(@_)}
sub norm {
  my $self = promote(@_); my $s = 0;
  foreach my $x ($self->value) {$s += $x*$x}
  return CORE::sqrt($s);
}

sub unit {
  my $self = promote(@_);
  my $n = $self->norm; return $self if $n == 0;
  return $self / $n;
}

############################################
#
#  Check for parallel vectors
#

sub isParallel {
  my $self = (ref($_[0]) ? $_[0] : shift);
  my $U = $self->promote(shift); my $V = $self->promote(shift);
  my $context =  $self->context;
  my $sameDirection = shift;
  my @u = $U->value; my @v = $V->value;
  return 0 unless  scalar(@u) == scalar(@v);
  my $k = ''; # will be scaling factor for u = k v
  foreach my $i (0..$#u) {
    #
    #  make sure we use fuzzy math
    #
    $u[$i] = Value::Real->new($context,$u[$i]) unless Value::isReal($u[$i]);
    $v[$i] = Value::Real->new($context,$v[$i]) unless Value::isReal($v[$i]);
    if ($k ne '') {
      return 0 if ($v[$i] != $k*$u[$i]);
    } else {
      #
      #  if one is zero and the other isn't then not parallel
      #  otherwise use the ratio of the two as k.
      #
      if ($u[$i] == 0) {
	return 0 if $v[$i] != 0;
      } else {
	return 0 if $v[$i] == 0;
	$k = ($v[$i]/$u[$i])->value;
        return 0 if $k < 0 && $sameDirection;
      }
    }
  }
  #
  #  Note: it will return 1 if both are zero vectors.  This is a
  #  feature, since one is provided by the problem writer, and he
  #  should only supply the zero vector if he means it.  One could
  #  return ($k ne '') to return 0 if both are zero.
  #
  return 1;
}

sub areParallel {isParallel(@_)}


############################################
#
#  Generate the various output formats
#

my $ijk_string = ['i','j','k','0'];
my $ijk_TeX = ['\boldsymbol{i}','\boldsymbol{j}','\boldsymbol{k}','\boldsymbol{0}'];

sub stringify {
  my $self = shift;
  return $self->TeX if $self->getFlag('StringifyAsTeX');
  $self->string;
}

sub string {
  my $self = shift; my $equation = shift;
  return $self->ijk($ijk_string)
    if ($self->{ijk} || $equation->{ijk} || $self->getFlag("ijk")) &&
        !$self->{ColumnVector};
  return $self->SUPER::string($equation,@_);
}

sub pdot {
  my $self = shift;
  my $string = $self->string;
  $string = '('.$string.')' if $string =~ m/[-+]/ &&
    ($self->getFlag("ijk")) && !$self->{ColumnVector};
  return $string;
}

sub TeX {
  my $self = shift; my $equation = shift;
  if ($self->{ColumnVector}) {
    my $def = ($equation->{context} || $self->context)->lists->get('Matrix');
    my $open = shift; my $close = shift;
    $open  = $self->{open}  unless defined($open);
    $open  = $def->{open}   unless defined($open);
    $close = $self->{close} unless defined($close);
    $close = $def->{close}  unless defined($close);
    $open =~ s/([{}])/\\$1/g; $close =~ s/([{}])/\\$1/g;
    $open = '\left'.$open if $open; $close = '\right'.$close if $close;
    my @coords = ();
    foreach my $x (@{$self->data}) {
      if (Value::isValue($x)) {push(@coords,$x->TeX($equation))} else {push(@coords,$x)}
    }
    return $open.'\begin{array}{c}'.join('\\\\',@coords).'\\\\\end{array}'.$close;
  }
  return $self->ijk if ($self->{ijk} || $equation->{ijk} || $self->getFlag("ijk"));
  return $self->SUPER::TeX($equation,@_);
}

sub ijk {
  my $self = shift; my $ijk = shift;
  if (!$ijk) {
    my $context = $self->context;
    $ijk = []; $ijk->[3] = '{\bf 0}';
    foreach my $i (0,1,2)
     {$ijk->[$i] = $context->{constants}{$ijk_string->[$i]}{TeX} || $ijk_TeX->[$i]}
  }
  my @coords = @{$self->data};
  Value::Error("Method 'ijk' can only be used on vectors in three-space")
    unless (scalar(@coords) <= 3);
  my $string = ''; my $n; my $term;
  foreach $n (0..scalar(@coords)-1) {
    $term = $coords[$n]; $term = (Value::isValue($term))? $term->string : "$term";
    if ($term ne 0) {
      $term = '' if $term eq '1'; $term = '-' if $term eq '-1';
      $term = '('.$term.')' if $term =~ m/e/i;
      $term = '+' . $term unless $string eq '' or $term =~ m/^-/;
      $string .= $term . $ijk->[$n];
    }
  }
  $string = $ijk->[3] if $string eq '';
  return $string;
}

###########################################################################

1;

