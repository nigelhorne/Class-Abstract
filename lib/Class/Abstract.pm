package Class::Abstract;

# Minimum required Perl version: 5.8.
use 5.008;
use strict;
use warnings;
use Carp         qw(croak);
use Readonly;
use Scalar::Util qw(blessed);
use Return::Set  qw(set_return);

=encoding utf8

=head1 NAME

Class::Abstract - Enforce abstract (non-instantiable) base classes for plain-Perl OO

=head1 VERSION

Version 0.02

=cut

our $VERSION = '0.02';

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

# Self-referential constant: the canonical name of this package.
Readonly::Scalar my $SELF => __PACKAGE__;

# Return::Set schema for import(): it always hands back the class name.
Readonly::Scalar my $IMPORT_SCHEMA => { type => 'string' };

# Every message this module can raise, in one place.  Keys are
# "<routine>:<condition>" so _resolve_class() can build them from the
# routine name.  The text is part of the public contract (see MESSAGES):
# callers and tests match on it, so change it only in a major release.
Readonly::Hash my %MESSAGE => (
	'abstract'              => 'Cannot instantiate abstract class %s directly',
	'new:unblessed'         => 'new() invocant must be a class name or blessed object, got %s',
	'new:undef'             => 'new() requires a defined class name as invocant',
	'check:unblessed'       => 'check_abstract() requires a class name or blessed object, got %s',
	'check:undef'           => 'check_abstract() requires a defined class name',
	'is_abstract:unblessed' => 'is_abstract() requires a class name or object invocant, got %s',
	'is_abstract:undef'     => 'is_abstract() requires a class name or object invocant',
	'internal:key'          => 'Class::Abstract internal error: unknown message key %s',
);

# ---------------------------------------------------------------------------
# Public variables
# ---------------------------------------------------------------------------

# Set to a true value to suppress all abstract-class croaks globally.
# Always use 'local' in tests to prevent state from bleeding between cases.
our $BYPASS = 0;

# Runtime tunables.  Modify $config{harness_bypass} to control whether
# HARNESS_ACTIVE suppresses enforcement.
our %config = (
	# 1 = suppress croaks when HARNESS_ACTIVE is set.  Off by default (since
	# 0.03) so that test suites catch accidental abstract instantiation.
	harness_bypass => 0,
);

# ---------------------------------------------------------------------------
# PUBLIC INTERFACE
# ---------------------------------------------------------------------------

=head1 SYNOPSIS

    # ---- Preferred: use parent -------------------------------------------
    package Animal;
    use parent 'Class::Abstract';

    # ---- Alternative: use Class::Abstract --------------------------------
    package Vehicle;
    use Class::Abstract;    # equivalent: adds Class::Abstract to @ISA

    # ---- Combine with Sub::Abstract for method contracts -----------------
    package Animal;
    use parent 'Class::Abstract';
    use Sub::Abstract qw(speak eat);   # subclasses must implement these

    # ---- Concrete subclass -----------------------------------------------
    package Dog;
    use parent 'Animal';

    sub new {
        my ($class, %args) = @_;
        my $self = $class->SUPER::new;  # delegates through Animal to here
        $self->{name} = $args{name};
        return $self;
    }
    sub speak { 'Woof' }
    sub eat   { 'Nom'  }

    # ---- If Animal defines its own new(), call check_abstract() first ----
    package Animal;
    use parent 'Class::Abstract';

    sub new {
        my $class = shift;
        Class::Abstract::check_abstract($class);  # enforces abstract contract
        return bless { a => 'default' }, $class;
    }

    # ---- Runtime behaviour -----------------------------------------------
    Animal->new;             # croaks: Cannot instantiate abstract class Animal directly
    Dog->new(name => 'Rex'); # returns a blessed Dog hashref
    Animal->is_abstract;     # 1
    Dog->is_abstract;        # 0

=head1 DESCRIPTION

Prevents direct instantiation of a class while still allowing concrete
subclasses to call C<$class-E<gt>SUPER::new(...)> through the normal
inheritance chain.

A class becomes abstract by listing C<Class::Abstract> as a direct parent:

    package Animal;
    use parent 'Class::Abstract';   # Animal is abstract

or equivalently via C<use>:

    use Class::Abstract;            # also adds to @ISA

Only the class that has C<Class::Abstract> directly in its C<@ISA> is
abstract.  Subclasses of that class are B<not> automatically abstract; each
abstract class in a hierarchy must opt in explicitly.

The enforcement check is performed at runtime inside C<new()>.  When a
concrete subclass calls C<$class-E<gt>SUPER::new(...)>, C<$class> is the
concrete subclass, not the abstract base, so the check passes.

=head2 Usage forms

=over 4

=item Inheritance form (preferred)

    package Animal;
    use parent 'Class::Abstract';

C<parent.pm> adds C<Class::Abstract> to C<@Animal::ISA>, making
C<Class::Abstract::new> available via MRO.  No C<import()> call is made.
C<< Animal->new >> will croak; C<< Dog->new >> (where Dog inherits Animal)
will not.

=item Import form

    package Vehicle;
    use Class::Abstract;

Calls C<import()>, which pushes C<Class::Abstract> onto C<@Vehicle::ISA>
if not already present.  Functionally identical to the inheritance form.

=back

=head2 Multiple abstract levels in a hierarchy

Each abstract class must opt in:

    package Animal;   use parent 'Class::Abstract';           # abstract
    package Mammal;   use parent 'Class::Abstract', 'Animal'; # also abstract
    package Dog;      use parent 'Mammal';                    # concrete

=head2 Integration with Sub::Abstract

The two modules complement each other:

    use parent 'Class::Abstract';          # cannot instantiate directly
    use Sub::Abstract qw(speak eat);       # subclasses must implement speak + eat

=head2 Bypass for testing

Enforcement is B<on> by default, including under a test harness, so your
test suite will catch an accidental C<< Animal->new >>.  Either condition
alone (OR logic) suppresses the croak:

=over 4

=item * C<$Class::Abstract::BYPASS> set to a true value.  Use C<local> in tests.
Checked first; short-circuits the second condition.

=item * C<$ENV{HARNESS_ACTIVE}> set (the convention used by L<Test::Harness>/prove)
B<and> C<$config{harness_bypass}> is true.  It is false by default.

=back

To build an abstract instance in a test (for example to exercise a method
of the abstract class itself), localise the bypass:

    my $animal = do { local $Class::Abstract::BYPASS = 1; Animal->new };

To get the pre-0.03 behaviour back for a whole test suite, where
enforcement was off whenever C<HARNESS_ACTIVE> was set:

    $Class::Abstract::config{harness_bypass} = 1;

B<Important:> C<$BYPASS> takes full precedence.  Setting
C<harness_bypass = 0> does not re-enable enforcement when C<$BYPASS> is
true.

=head2 Error messages

Every message the module can raise is listed below.  The routine-specific
L</MESSAGES> sections say which routine raises which.

    Message                                                     Raised by
    -------                                                     ---------
    Cannot instantiate abstract class CLASS directly            new, check_abstract
    new() invocant must be a class name or blessed object,      new
      got REFTYPE
    new() requires a defined class name as invocant             new
    check_abstract() requires a class name or blessed object,   check_abstract
      got REFTYPE
    check_abstract() requires a defined class name              check_abstract
    is_abstract() requires a class name or object invocant,     is_abstract
      got REFTYPE
    is_abstract() requires a class name or object invocant      is_abstract

=head1 METHODS/SUBROUTINES

=head2 import

    use Class::Abstract;

Called automatically by C<use Class::Abstract>.  Makes the calling package
abstract by adding C<Class::Abstract> to its C<@ISA>, exactly as
C<use parent 'Class::Abstract'> would.

=head3 ARGUMENTS

=over 4

=item C<$class> (required, implicit)

Always C<'Class::Abstract'> in normal usage.  Any import list is ignored.

=back

=head3 RETURNS

The class name (C<'Class::Abstract'>) as a plain string.  C<use> discards
it; the value is only visible to code that calls C<import()> directly.

=head3 SIDE EFFECTS

Appends C<'Class::Abstract'> to the caller's C<@ISA>, unless:

=over 4

=item * it is already there (so repeated C<use> lines are harmless),

=item * the caller I<is> C<Class::Abstract> (that would be circular), or

=item * the caller is undef or the empty string, which can happen in unusual
contexts such as C<BEGIN> blocks inside a string C<eval>.  The empty string
would otherwise resolve to C<@main::ISA>.

=back

=head3 EXAMPLE

    package Vehicle;
    use Class::Abstract;          # @Vehicle::ISA is now ('Class::Abstract')
    use Class::Abstract;          # no change: already present

    package Car;
    our @ISA = ('Vehicle');       # Car is concrete

    package main;
    Car->new;                     # ok
    Vehicle->new;                 # croaks (outside a test harness)

=head3 API SPECIFICATION

=head4 Input

    # Positional; no named parameters.
    {
        class => { type => 'string', position => 0, optional => 0 },
    }

=head4 Output

    { type => 'string' }    # always the invocant, normally 'Class::Abstract'

=head3 MESSAGES

None.  C<import()> never croaks or warns.

=head3 FORMAL SPECIFICATION

    Package == seq CHAR

    ┌─ Import ──────────────────────────────────────────────
    │ ΔSymbolTable
    │ class?  : Package
    │ caller? : Package ∪ {⊥}
    │ result! : Package
    ├───────────────────────────────────────────────────────
    │ registrable ⇔ caller? ≠ ⊥ ∧ #caller? > 0
    │               ∧ caller? ≠ 'Class::Abstract'
    │               ∧ 'Class::Abstract' ∉ ran ISA(caller?)
    │ registrable ⇒ ISA'(caller?) = ISA(caller?) ⁀ ⟨'Class::Abstract'⟩
    │ ¬registrable ⇒ ISA' = ISA
    │ result! = class?
    └───────────────────────────────────────────────────────

=cut

sub import {
	my ($class) = @_;
	my $caller  = caller;

	# Register the caller only when it is a real package other than this one
	# and is not already registered (keeps repeated 'use' idempotent).
	# The defined/length guard stops '' from resolving to @main::ISA.
	if (defined($caller) && length($caller) && ($caller ne $SELF) && !_is_direct_abstract($caller)) {
		# Writing another package's @ISA needs a symbolic reference.
		no strict 'refs';    ## no critic (ProhibitNoStrict)
		push @{"${caller}::ISA"}, $SELF;
	}

	return set_return($class, $IMPORT_SCHEMA);
}

=head2 new

    my $obj = ConcreteChild->new;
    my $obj = ConcreteChild->new(%initial_attrs);
    my $copy = $obj->new;

Base constructor with abstract-class enforcement.  Croaks when called on an
abstract class (one with C<Class::Abstract> directly in its C<@ISA>, or
C<Class::Abstract> itself).  Succeeds for concrete subclasses, including
via C<$class-E<gt>SUPER::new(...)> from a child's own C<new()>, and returns
a blessed empty hashref.

The check uses the B<original invocant> (C<$class>), not the package where
C<new()> is defined.  That is why C<SUPER::new> works: C<$class> is still
the concrete subclass, so the check passes.

=head3 ARGUMENTS

=over 4

=item C<$class> (required)

The invocant: a class name or a blessed object.  An object stands in for
its class, so C<< $obj->new >> builds a new, empty object of the same
class.  Unblessed references, C<undef> and the empty string are rejected.

=item C<%initial_attrs> (optional, ignored)

Extra arguments are accepted and discarded, so subclass C<new()> methods
can pass their arguments through C<SUPER::new> safely.  Subclasses
populate their own attributes after calling C<SUPER::new>.

=back

=head3 RETURNS

A new blessed empty hashref of class C<$class>.

=head3 SIDE EFFECTS

None beyond the allocation.  Asking about a class name that has never
been loaded does not create that package in the symbol table (C<bless>
itself will, as it always does, once the check passes).

=head3 EXAMPLE

    package Animal;
    use parent 'Class::Abstract';

    package Dog;
    our @ISA = ('Animal');

    sub new {
        my ($class, %args) = @_;
        my $self = $class->SUPER::new;   # reaches Class::Abstract::new
        $self->{name} = $args{name};     # populate after SUPER
        return $self;
    }

    package main;
    my $rex = Dog->new(name => 'Rex');   # ok: Dog is concrete
    eval { Animal->new };                # dies: Animal is abstract
    print $@;  # Cannot instantiate abstract class Animal directly at ...

=head3 API SPECIFICATION

=head4 Input

    # Positional: ($class, @ignored)
    {
        class => {
            type     => [ 'string', 'object' ],  # non-empty name or blessed ref
            position => 0,
            optional => 0,
            min      => 1,                       # length, when a string
        },
    }

=head4 Output

    { type => 'object', isa => $class }    # blessed empty hashref

=head3 MESSAGES

    Message                                    Meaning / Resolution
    -------                                    --------------------
    Cannot instantiate abstract class CLASS    CLASS has Class::Abstract directly
      directly                                 in its @ISA (or is Class::Abstract)
                                               and no bypass is active.
                                               Instantiate a concrete subclass.
    new() invocant must be a class name or     new() was called as a function on
      blessed object, got REFTYPE              an unblessed reference.  Call it
                                               as a class or object method.
    new() requires a defined class name as     new() was called as a function
      invocant                                 with undef or ''.  Pass a class
                                               name.

=head3 FORMAL SPECIFICATION

    ┌─ New ─────────────────────────────────────────────────
    │ ΞRegistry
    │ inv?    : Package ∪ Object ∪ Ref ∪ {⊥}
    │ result! : Object
    ├───────────────────────────────────────────────────────
    │ inv? ∉ Ref ∖ Object ∧ inv? ≠ ⊥ ∧ inv? ≠ ''
    │ c = resolve(inv?)
    │ ¬is_direct_abstract(c) ∨ bypass_active
    │ result! = bless({}, c)
    └───────────────────────────────────────────────────────

    ┌─ NewAbstract ─────────────────────────────────────────
    │ ΞRegistry
    │ inv? : Package ∪ Object
    ├───────────────────────────────────────────────────────
    │ is_direct_abstract(resolve(inv?)) ∧ ¬bypass_active
    │ croak('Cannot instantiate abstract class ' ⁀ resolve(inv?) ⁀ ' directly')
    └───────────────────────────────────────────────────────

    NewOp ≙ New ∨ NewAbstract ∨ BadInvocant

=cut

sub new {
	my ($invocant) = @_;

	# Validate the invocant, then refuse abstract classes; both helpers
	# croak on failure so reaching bless means the class is instantiable.
	my $class = _resolve_class('new', $invocant);
	_enforce($class);

	return bless {}, $class;
}

=head2 check_abstract

    Class::Abstract::check_abstract($class);
    $class->Class::Abstract::check_abstract;

Enforces the abstract-class contract from inside a user-defined C<new()>.

If your abstract class defines its own C<new()> and that C<new()> creates
the object itself (via C<bless>) instead of calling
C<$class-E<gt>SUPER::new>, the check in C<Class::Abstract::new> is never
reached.  Call C<check_abstract()> first to restore it.

=head3 ARGUMENTS

=over 4

=item C<$class> (required)

A class name string or a blessed object.  Unblessed references, C<undef>
and the empty string are rejected.

=back

=head3 RETURNS

C<undef> when C<$class> is concrete or a bypass is active.  Croaks
otherwise.

=head3 SIDE EFFECTS

None.  Respects C<$BYPASS> and C<harness_bypass> exactly as C<new()> does.

=head3 EXAMPLE

    package Animal;
    use parent 'Class::Abstract';

    sub new {
        my ($class, %args) = @_;
        Class::Abstract::check_abstract($class);    # croaks if $class is Animal
        return bless { legs => $args{legs} }, $class;
    }

    package Dog;
    our @ISA = ('Animal');

    package main;
    Dog->new(legs => 4);     # ok
    Animal->new(legs => 4);  # croaks: Cannot instantiate abstract class Animal directly

=head3 API SPECIFICATION

=head4 Input

    # Positional: ($class)
    {
        class => {
            type     => [ 'string', 'object' ],
            position => 0,
            optional => 0,
            min      => 1,
        },
    }

=head4 Output

    { type => 'undef' }

=head3 MESSAGES

    Message                                    Meaning / Resolution
    -------                                    --------------------
    Cannot instantiate abstract class CLASS    As for new().
      directly
    check_abstract() requires a class name     Argument was an unblessed reference.
      or blessed object, got REFTYPE           Pass $class (or $self).
    check_abstract() requires a defined        Argument was undef or ''.  Usually
      class name                               a missing 'my $class = shift'.

=head3 FORMAL SPECIFICATION

    ┌─ CheckAbstract ───────────────────────────────────────
    │ ΞRegistry
    │ inv?    : Package ∪ Object
    │ result! : {⊥}
    ├───────────────────────────────────────────────────────
    │ ¬is_direct_abstract(resolve(inv?)) ∨ bypass_active
    │ result! = ⊥
    └───────────────────────────────────────────────────────

    CheckAbstractOp ≙ CheckAbstract ∨ NewAbstract ∨ BadInvocant

=cut

sub check_abstract {
	my ($invocant) = @_;

	# Same rules as new(), minus the bless: the caller builds the object.
	_enforce(_resolve_class('check', $invocant));

	return;
}

=head2 is_abstract

    my $bool = SomeClass->is_abstract;
    my $bool = $obj->is_abstract;
    my $bool = Class::Abstract->is_abstract('SomeClass');
    my $bool = Class::Abstract->is_abstract($obj);

Returns C<1> if the class is B<directly> abstract: it has
C<Class::Abstract> in its own C<@ISA>, or it is C<Class::Abstract>.
Returns C<0> for concrete subclasses, even though they inherit from an
abstract base.

Any class with C<Class::Abstract> in its ancestry inherits this method, so
it works as a class method or an instance method.

=head3 ARGUMENTS

=over 4

=item C<$self_or_class> (required)

The invocant: a class name or a blessed object (whose class is used).

=item C<$target> (optional)

A class name or blessed object to check instead of the invocant.  This is
the form C<< Class::Abstract->is_abstract('SomeClass') >>.  C<undef> means
"not given", so the invocant is checked.

=back

=head3 RETURNS

C<1> if directly abstract, C<0> otherwise, as a plain integer.

=head3 SIDE EFFECTS

None.  In particular, asking about a package that does not exist does not
create it.

=head3 EXAMPLE

    Animal->is_abstract;                        # 1 (Class::Abstract in @Animal::ISA)
    Dog->is_abstract;                           # 0 (@Dog::ISA is ('Animal'))

    my $dog = Dog->new(name => 'Rex');
    $dog->is_abstract;                          # 0 (checks 'Dog')

    Class::Abstract->is_abstract('Animal');     # 1
    Class::Abstract->is_abstract($dog);         # 0 (checks ref($dog))
    Class::Abstract->is_abstract('No::Such');   # 0, and No::Such is not created

=head3 API SPECIFICATION

=head4 Input

    # Positional: ($self_or_class, $target)
    {
        self_or_class => { type => [ 'string', 'object' ], position => 0, optional => 0, min => 1 },
        target        => { type => [ 'string', 'object' ], position => 1, optional => 1, min => 1 },
    }

=head4 Output

    { type => 'integer', min => 0, max => 1 }

=head3 MESSAGES

    Message                                    Meaning / Resolution
    -------                                    --------------------
    is_abstract() requires a class name or     The class to check was an unblessed
      object invocant, got REFTYPE             reference.  Pass a name or object.
    is_abstract() requires a class name or     The class to check was undef or ''.
      object invocant

=head3 FORMAL SPECIFICATION

    ┌─ IsAbstract ──────────────────────────────────────────
    │ ΞRegistry
    │ self?   : Package ∪ Object
    │ target? : Package ∪ Object ∪ {⊥}
    │ result! : {0, 1}
    ├───────────────────────────────────────────────────────
    │ c = resolve(if target? = ⊥ then self? else target?)
    │ result! = 1 ⇔ is_direct_abstract(c)
    └───────────────────────────────────────────────────────

=cut

sub is_abstract {
	my ($self, $target) = @_;

	# An explicit target (Class::Abstract->is_abstract('Foo') or ($obj))
	# wins; otherwise check the invocant itself.  Both go through the same
	# resolver, so an object argument is checked by its class, not by its
	# stringification ('Foo=HASH(0x...)').
	my $class = _resolve_class('is_abstract', defined($target) ? $target : $self);

	return _is_direct_abstract($class);
}

# ---------------------------------------------------------------------------
# PRIVATE SUBROUTINES
#
# Not exported and not part of the API.  The white-box tests (t/function.t,
# t/edge_cases.t, t/mutant_killers.t) call and spy on them directly, which
# is why they are plain named subs called by name: a spy installed on the
# glob is then seen by every caller.
# ---------------------------------------------------------------------------

# _fail
# Purpose      : The single place this module raises an error, so message
#                text lives only in %MESSAGE.
# Entry        : $key  -- a key of %MESSAGE.
#                @args -- sprintf arguments for that message.
# Exit status  : Never returns.
# Side effects : Throws via croak.  Every frame between here and the user
#                is in this package (or a subclass), so Carp reports the
#                user's line, not ours.
# Notes        : A Readonly hash returns undef for a missing key rather
#                than dying, so a mistyped key would croak with an empty
#                message.  Report the bad key instead.
sub _fail {
	my ($key, @args) = @_;

	my $template = $MESSAGE{$key};
	($template, @args) = ($MESSAGE{'internal:key'}, $key) unless defined $template;

	croak sprintf($template, @args);
}

# _resolve_class
# Purpose      : Turn an invocant into a validated class name, applying one
#                set of rules for every public routine.
# Entry        : $routine  -- message-key prefix: 'new', 'check' or
#                             'is_abstract'.
#                $invocant -- class name, blessed object, or junk.
# Exit status  : Returns a defined, non-empty class-name string.
#                Croaks if $invocant is an unblessed reference, undef or ''.
# Side effects : None.
# Notes        : blessed() is tested with defined(), not truth, because an
#                object blessed into package '0' has blessed() eq '0'
#                (and ref() eq '0'), which plain truth tests misread.
sub _resolve_class {
	my ($routine, $invocant) = @_;

	# An object stands in for its class.  Any other reference is a caller
	# error, never a class name.
	my $pkg = blessed($invocant);
	if (defined $pkg) {
		$invocant = $pkg;
	} elsif (ref $invocant) {
		_fail("${routine}:unblessed", ref $invocant);
	}

	# undef cannot name a package, and '' would silently mean main::.
	_fail("${routine}:undef") unless defined($invocant) && length($invocant);

	return $invocant;
}

# _bypass_active
# Purpose      : Decide whether enforcement is switched off.
# Entry        : None (reads $BYPASS, %config, $ENV{HARNESS_ACTIVE}).
# Exit status  : 1 if any bypass applies, else 0.
# Side effects : None.
# Notes        : $BYPASS is checked first and short-circuits, so it wins
#                over harness_bypass (documented under LIMITATIONS).
sub _bypass_active {
	return ($BYPASS || ($config{harness_bypass} && $ENV{HARNESS_ACTIVE})) ? 1 : 0;
}

# _enforce
# Purpose      : Croak if $class is directly abstract and no bypass is on.
# Entry        : $class -- an already-validated class name.
# Exit status  : Returns $class on success; croaks otherwise.
# Side effects : None.
# Notes        : The bypass test runs first so that, with a bypass on,
#                _is_direct_abstract() is never called.  t/function.t
#                counts those calls, so keep this order.
sub _enforce {
	my ($class) = @_;
	_fail('abstract', $class) if !_bypass_active() && _is_direct_abstract($class);
	return $class;
}

# _direct_isa
# Purpose      : Return a package's own @ISA without creating the package.
#                The obvious @{"${class}::ISA"} autovivifies the stash, so a
#                mere is_abstract('Typo::Name') would conjure an empty
#                package into existence.
# Entry        : $class -- package name string.  '' means main::.
# Exit status  : An arrayref.  It is the live @ISA if the package and its
#                @ISA exist, otherwise a new empty arrayref.
# Side effects : None.  The symbol table is only read, never written.
# Notes        : The old "'" package separator (Foo'Bar) is not recognised.
sub _direct_isa {
	my ($class) = @_;

	# Walk the stash tree one '::' segment at a time from main::.  Empty
	# segments (from '::Foo' or 'Foo::') are skipped, as Perl skips them.
	# A stash entry may hold a non-glob (e.g. an optimised constant), so
	# check that each entry really is a glob before dereferencing it.
	my $stash = \%main::;
	foreach my $segment (grep { length } split /::/, $class) {
		my $glob = $stash->{"${segment}::"};
		$stash = (defined($glob) && ref(\$glob) eq 'GLOB') ? *{$glob}{HASH} : undef;
		last unless $stash;
	}

	# The package exists only if every segment resolved.  *ISA{ARRAY} is
	# undef until @ISA is first used, so fall back to an empty list.
	my $isa = $stash ? $stash->{ISA} : undef;
	return (defined($isa) && ref(\$isa) eq 'GLOB' && *{$isa}{ARRAY}) || [];
}

# _is_direct_abstract
# Purpose      : Decide whether a class is directly abstract: it is
#                Class::Abstract, or Class::Abstract is in its own @ISA.
# Entry        : $class -- package name string, or undef.
# Exit status  : Exactly 1 or 0 (never undef or ''); the mutation tests in
#                t/mutant_killers.t rely on these exact integers.
# Side effects : None.  $_ is localised by grep.
# Notes        : Intentionally shallow: a subclass of an abstract class is
#                concrete unless it opts in too.  Undefined @ISA elements
#                are skipped so that they do not warn.
sub _is_direct_abstract {
	my ($class) = @_;

	# undef names nothing; Class::Abstract itself must never be built;
	# anything else is abstract iff we sit directly in its @ISA.
	my $abstract = !defined($class)  ? 0
		: ($class eq $SELF)       ? 1
		: (grep { defined($_) && ($_ eq $SELF) } @{ _direct_isa($class) }) ? 1
		: 0;

	return $abstract;
}

1;

__END__

=head1 LIMITATIONS

=over 4

=item Incompatible change in 0.03: enforcement is on under a test harness

Up to 0.02, C<harness_bypass> defaulted to 1, so C<< Animal->new >>
silently succeeded whenever C<$ENV{HARNESS_ACTIVE}> was set.  That hid
mistakes in the test suite of every distribution using Class::Abstract,
which is exactly where an accidental instantiation of an abstract class
ought to be caught.  The default is now 0.  A test suite that relied on
the old behaviour will now croak with "Cannot instantiate abstract class
... directly".  Either fix the test to instantiate a concrete subclass,
wrap the call in C<local $Class::Abstract::BYPASS = 1>, or restore the
old default with C<< $Class::Abstract::config{harness_bypass} = 1 >>.

=item Only constructors that reach new() or check_abstract() are guarded

C<bless {}, 'Animal'>, L<Storable/dclone>, C<thaw>, and any C<new()>
override that forgets to call C<check_abstract()> all produce abstract
instances without complaint.  Enforcement is a runtime convention, not a
language guarantee.

=item Only direct @ISA is checked

C<_is_direct_abstract> looks only at the invocant's own C<@ISA>.  If
C<Class::Abstract> appears higher in the MRO (e.g. C<Dog> inherits
C<Animal>, which is abstract), C<Dog> is B<not> abstract, which is the
intended behaviour.  It also means a subclass must opt in explicitly to be
abstract:

    package Mammal;
    use parent 'Class::Abstract', 'Animal';   # both in @ISA; Mammal is abstract

=item C<isa()> cannot distinguish abstract from concrete

C<< Dog->isa('Class::Abstract') >> is true because Dog inherits from
Class::Abstract transitively.  Use C<is_abstract()> to tell a class that
is itself abstract apart from one that merely descends from an abstract
class.

=item C<can('new')> returns the croak-stub

C<< Animal->can('new') >> returns C<\&Class::Abstract::new>, a true CODE
ref.  The method is callable; it just croaks.

=item new() discards constructor arguments

The base constructor ignores everything after C<$class> and returns an
empty blessed hashref.  Subclasses populate their own attributes after
calling C<SUPER::new>, or override C<new()> (and call C<check_abstract()>).

=item Bypass is global and loosely typed

C<$BYPASS> switches enforcement off for I<every> class, not just the one
under test, and any true value counts (including C<"false"> and
C<"0E0">).  Always use C<local>.  C<$BYPASS> also short-circuits the
harness check, so C<harness_bypass = 0> does B<not> re-enable enforcement
while C<$BYPASS> is true.  To be sure enforcement is on regardless of
what the surrounding code has set, clear both:

    local $Class::Abstract::BYPASS = 0;
    local $Class::Abstract::config{harness_bypass} = 0;

=item Old-style package separator

Class names written with the obsolete C<'> separator (C<Foo'Bar>) are not
translated to C<Foo::Bar> when looking up C<@ISA>, so they report as
concrete.

=item Thread safety

No shared mutable state exists beyond C<$BYPASS> and C<%config>, which
are read-only in normal operation.  C<import()> writes to the caller's
C<@ISA>, normally at compile time; that is safe as long as modules are not
C<require>d concurrently from several threads.

=item Not for Moo/Moose

Moo's C<requires> and Moose's abstract-class extensions give similar
guarantees within their own object systems.  This module is for plain-Perl
OO only.

=back

=head1 FORMAL SPECIFICATION

Shared definitions used by the per-routine specifications above.

    Package == seq CHAR
    [Object, Ref]                     -- blessed / any references; Object ⊆ Ref

    ┌─ Registry ────────────────────────────────────────────
    │ bypass         : 𝔹
    │ harness_bypass : 𝔹
    │ HARNESS_ACTIVE : 𝔹
    │ ISA            : Package ⇸ seq Package
    └───────────────────────────────────────────────────────

    ┌─ InitRegistry ────────────────────────────────────────
    │ Registry'
    ├───────────────────────────────────────────────────────
    │ bypass' = false ∧ harness_bypass' = false
    └───────────────────────────────────────────────────────

    bypass_active ⇔ bypass ∨ (harness_bypass ∧ HARNESS_ACTIVE)

    resolve : (Package ∪ Object) ⇸ Package
    resolve(x) = class_of(x)  if x ∈ Object
               = x            if x ∈ Package ∧ #x > 0

    is_direct_abstract : Package → 𝔹
    is_direct_abstract(c) ⇔ c = 'Class::Abstract'
                          ∨ (c ∈ dom ISA ∧ 'Class::Abstract' ∈ ran ISA(c))

    ┌─ BadInvocant ─────────────────────────────────────────
    │ ΞRegistry
    │ inv? : Package ∪ Ref ∪ {⊥}
    ├───────────────────────────────────────────────────────
    │ inv? ∈ Ref ∖ Object ∨ inv? = ⊥ ∨ inv? = ''
    │ croak(message for the calling routine)
    └───────────────────────────────────────────────────────

    -- Key property: when Dog->SUPER::new runs, inv? = 'Dog' and
    -- 'Class::Abstract' ∉ ran ISA('Dog'), so enforcement never fires
    -- for concrete subclasses.  Every operation leaves dom ISA unchanged
    -- except Import (ΞRegistry): lookups never create packages.

=head1 PUBLIC VARIABLES

=head2 C<$BYPASS>

Set to a true value to disable the abstract-class croak.  Use C<local>:

    local $Class::Abstract::BYPASS = 1;

B<Warning:> any true value (including C<"false"> and C<"0E0">) enables
the bypass.

=head2 C<%config>

=over 4

=item C<harness_bypass> (default: 0)

When true, the abstract-class croak is suppressed whenever
C<$ENV{HARNESS_ACTIVE}> is set.  The default was 1 up to version 0.02;
set it to 1 to get that behaviour back.  C<$BYPASS> takes precedence
(see L</LIMITATIONS>).

=back

=head1 DEPENDENCIES

L<Carp> (core),
L<Scalar::Util> (core),
L<Readonly>,
L<Return::Set>.

=head1 SEE ALSO

=over 4

=item * L<Test Dashboard|https://nigelhorne.github.io/Class-Abstract/coverage/>

=item * L<Sub::Abstract>

Sister module: enforces abstract (pure-virtual) method contracts.
Pair with C<Class::Abstract> to create fully enforced abstract base classes.

=item * L<Sub::Private>

Sister module: enforces strictly private (owner-only) access.

=item * L<Sub::Protected>

Sister module: enforces protected (owner + subclass) access.

=back

=head1 AUTHOR

Nigel Horne, C<< <njh at nigelhorne.com> >>

=head1 LICENCE AND COPYRIGHT

Copyright 2026 Nigel Horne.

Usage is subject to the GPL2 licence terms.
If you use it, please let me know.

=cut
