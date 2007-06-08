########################################################################### 

package Value::Set;
my $pkg = 'Value::Set';

use strict;
our @ISA = qw(Value);

#  Convert a value to a Set.  The value can be
#    a list of numbers, or an reference to an array of numbers
#    a point, vector or set object
#    a matrix if it is  n x 1  or  1 x n
#    a string that evaluates to a point
#
sub new {
  my $self = shift; my $class = ref($self) || $self;
  my $context = (Value::isContext($_[0]) ? shift : $self->context);
  my $p = shift; $p = [$p,@_] if (scalar(@_) > 0);
  $p = Value::makeValue($p,context=>$context) if (defined($p) && !ref($p));
  return $p if (Value::isFormula($p) && $p->type eq Value::class($self));
  my $pclass = Value::class($p); my $isFormula = 0;
  my @d; @d = $p->dimensions if $pclass eq 'Matrix';
  if ($pclass eq 'List' && $p->typeRef->{entryType}{name} eq 'Number') {$p = $p->data}
  elsif ($pclass =~ m/Point|Vector|Set/) {$p = $p->data}
  elsif ($pclass eq 'Matrix' && scalar(@d) == 1) {$p = [$p->value]}
  elsif ($pclass eq 'Matrix' && scalar(@d) == 2 && $d[0] == 1) {$p = ($p->value)[0]}
  elsif ($pclass eq 'Matrix' && scalar(@d) == 2 && $d[1] == 1) {$p = ($p->transpose->value)[0]}
  else {
    $p = [$p] if (defined($p) && ref($p) ne 'ARRAY');
    foreach my $x (@{$p}) {
      $x = Value::makeValue($x,context=>$context);
      $isFormula = 1 if Value::isFormula($x);
      Value::Error("An element of a set can't be %s",Value::showClass($x))
        unless Value::isRealNumber($x);
    }
  }
  return $self->formula($p) if $isFormula;
  my $def = $context->lists->get('Set');
  my $set = bless {
    data => $p, open => $def->{open}, close => $def->{close},
    context => $context,
  }, $class;
  $set = $set->reduce if $self->getFlag('reduceSets');
  return $set;
}

#
#  Set the canBeInterval flag
#
sub make {
  my $self = shift;
  my $context = (Value::isContext($_[0]) ? shift : $self->context);
  my $def = $context->lists->get('Set');
  $self = $self->SUPER::make($context,@_);
  $self->{open} = $def->{open}; $self->{close} = $def->{close};
  return $self;
}

sub isOne {0}
sub isZero {0}

sub canBeInUnion {1}
sub isSetOfReals {1}

#
#  Try to promote arbitrary data to a set
#
sub promote {
  my $self = shift; my $class = ref($self) || $self;
  my $x = (scalar(@_) ? shift : $self);
  $x = Value::makeValue($x,context=>$self->context);
  return $self->new($x,@_) if scalar(@_) > 0 || Value::isRealNumber($x);
  return $x if ref($x) eq $class;
  $x = $self->Package("Interval")->promote($x)->inContext($self->context) if $x->canBeInUnion;
  return $x if $x->isSetOfReals;
  return $self->new($x->value)
    if $x->type eq 'List' && $x->typeRef->{entryType}{name} eq 'Number';
  Value::Error("Can't convert %s to %s",$x->showClass,$self->showClass);
}

############################################
#
#  Operations on sets
#

#
#  Addition forms additional sets
#
sub add {
  my ($self,$l,$r) = Value::checkOpOrder(@_);
  Value::Union::form($self->context,$l,$r);
}
sub dot {my $self = shift; $self->add(@_)}

#
#  Subtraction removes items from a set
#
sub sub {
  my ($self,$l,$r) = Value::checkOpOrder(@_);
  return Value::Union::form($self->context,subIntervalSet($l,$r)) if Value::class($l) eq 'Interval';
  return Value::Union::form($self->context,subSetInterval($l,$r)) if Value::class($r) eq 'Interval';
  return Value::Union::form($self->context,subSetSet($l,$r));
}

#
#  Subtract one set from another
#    (return the resulting set or nothing for empty set)
#
sub subSetSet {
  my ($self,$other) = @_;
  my @l = $self->sort->value; my @r = $other->sort->value;
  my @entries = ();
  while (scalar(@l) && scalar(@r)) {
    if ($l[0] < $r[0]) {
      push(@entries,shift(@l));
    } else {
      while ($l[0] == $r[0]) {shift(@l); last if scalar(@l) == 0};
      shift(@r);
    }
  }
  push(@entries,@l);
  return () unless scalar(@entries);
  return $self->make(@entries);
}

#
#  Subtract a set from an interval
#    (returns a collection of intervals)
#
sub subIntervalSet {
  my $self = shift;
  my $I = $self->copy; my $S = shift;
  my @union = (); my ($a,$b) = $I->value;
  foreach my $x ($S->reduce->value) {
    next if $x < $a;
    if ($x == $a) {
      return @union if $a == $b;
      $I->{open} = '(';
    } elsif ($x < $b) {
      push(@union,$self->Package("Interval")->make($self->context,$I->{open},$a,$x,')'));
      $I->{open} = '('; $I->{data}[0] = $x;
    } else {
      $I->{close} = ')' if ($x == $b);
      last;
    }
  }
  return (@union,$I);
}

#
#  Subtract an interval from a set
#    (returns the resulting set or nothing for the empty set)
#
sub subSetInterval {
  my $S = shift; my $I = shift;
  my ($a,$b) = $I->value;
  my @entries = ();
  foreach my $x ($S->value) {
    push(@entries,$x)
      if ($x < $a || $x > $b) ||
         ($x == $a && $I->{open}  ne '[') ||
	 ($x == $b && $I->{close} ne ']');
  }
  return () unless scalar(@entries);
  return $S->make(@entries);
}

#
#  Compare two sets lexicographically on their sorted contents
#
sub compare {
  my ($l,$r,$flag) = @_; my $self = $l;
  if ($r->class eq 'Interval') {
    return ($flag? 1: -1) if $l->length == 0;
    my ($a,$b) = $r->value; my $c = $l->{data}[0];
    return (($flag) ? $a <=> $c : $c <=> $a)
      if ($l->length == 1 && $a == $b) || $a != $c;
    return ($flag? 1: -1);
  }
  if ($l->getFlag('reduceSetsForComparison')) {$l = $l->reduce; $r = $r->reduce}
  if ($flag) {my $tmp = $l; $l = $r; $r = $tmp};
  my @l = $l->sort->value; my @r = $r->sort->value;
  while (scalar(@l) && scalar(@r)) {
    my $cmp = shift(@l) <=> shift(@r);
    return $cmp if $cmp;
  }
  return scalar(@l) - scalar(@r);
}

############################################
#
#  Utility routines
#

#
#  Remove repeated values
#
sub reduce {
  my $self = shift;
  return $self if $self->{isReduced} || $self->length < 2;
  my @data = $self->sort->value; my @set = ();
  while (scalar(@data)) {
    push(@set,shift(@data));
    shift(@data) while (scalar(@data) && $set[-1] == $data[0]);
  }
  return $self->make(@set)->with(isReduced=>1);
}

#
#  True if the set is reduced
#
sub isReduced {
  my $self = shift;
  return 1 if $self->{isReduced} || $self->length < 2;
  return $self->reduce->length == $self->length;
}

#
#  Sort the data for a set
#
sub sort {
  my $self = shift;
  return $self->make(CORE::sort {$a <=> $b} $self->value);
}


#
#  Tests for containment, subsets, etc.
#

sub contains {
  my $self = shift; my $other = $self->promote(shift)->reduce;
  return unless $other->type eq 'Set';
  return ($other-$self)->isEmpty;
}

sub isSubsetOf {
  my $self = shift; my $other = $self->promote(shift);
  return $other->contains($self);
}

sub isEmpty {(shift)->length == 0}

sub intersect {
  my $self = shift; my $other = shift;
  return $self-($self-$other);
}

sub intersects {
  my $self = shift; my $other = shift;
  return !$self->intersect($other)->isEmpty;
}

###########################################################################

1;
