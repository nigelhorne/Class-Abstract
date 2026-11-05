## Name

Class::Abstract - Enforce abstract (non-instantiable) base classes for plain-Perl OO

## Version

Version 0.02

## Synopsis

```perl
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
```

## Description

Prevents direct instantiation of a class while still allowing concrete
subclasses to call `$class->SUPER::new(...)` through the normal
inheritance chain.

A class becomes abstract by listing `Class::Abstract` as a direct parent:

```perl
package Animal;
use parent 'Class::Abstract';   # Animal is abstract
```

or equivalently via `use`:

```perl
use Class::Abstract;            # also adds to @ISA
```

Only the class that has `Class::Abstract` directly in its `@ISA` is
abstract.  Subclasses of that class are **not** automatically abstract; each
abstract class in a hierarchy must opt in explicitly.

The enforcement check is performed at runtime inside `new()`.  When a
concrete subclass calls `$class->SUPER::new(...)`, `$class` is the
concrete subclass, not the abstract base, so the check passes.

### Usage Forms

- Inheritance form (preferred)

    ```perl
    package Animal;
    use parent 'Class::Abstract';
    ```

    `parent.pm` adds `Class::Abstract` to `@Animal::ISA`, making
    `Class::Abstract::new` available via MRO.  No `import()` call is made.
    `Animal->new` will croak; `Dog->new` (where Dog inherits Animal)
    will not.

- Import form

    ```perl
    package Vehicle;
    use Class::Abstract;
    ```

    Calls `import()`, which pushes `Class::Abstract` onto `@Vehicle::ISA`
    if not already present.  Functionally identical to the inheritance form.

### Multiple Abstract Levels in a Hierarchy

Each abstract class must opt in:

```perl
package Animal;   use parent 'Class::Abstract';           # abstract
package Mammal;   use parent 'Class::Abstract', 'Animal'; # also abstract
package Dog;      use parent 'Mammal';                    # concrete
```

### Integration With Sub::Abstract

The two modules complement each other:

```perl
use parent 'Class::Abstract';          # cannot instantiate directly
use Sub::Abstract qw(speak eat);       # subclasses must implement speak + eat
```

### Bypass for Testing

Enforcement is **on** by default, including under a test harness, so your
test suite will catch an accidental `Animal->new`.  Either condition
alone (OR logic) suppresses the croak:

- `$Class::Abstract::BYPASS` set to a true value.  Use `local` in tests.
Checked first; short-circuits the second condition.
- `$ENV{HARNESS_ACTIVE}` set (the convention used by [Test::Harness](https://metacpan.org/pod/Test%3A%3AHarness)/prove)
**and** `$config{harness_bypass}` is true.  It is false by default.

To build an abstract instance in a test (for example to exercise a method
of the abstract class itself), localise the bypass:

```perl
my $animal = do { local $Class::Abstract::BYPASS = 1; Animal->new };
```

To get the pre-0.03 behaviour back for a whole test suite, where
enforcement was off whenever `HARNESS_ACTIVE` was set:

```
$Class::Abstract::config{harness_bypass} = 1;
```

**Important:** `$BYPASS` takes full precedence.  Setting
`harness_bypass = 0` does not re-enable enforcement when `$BYPASS` is
true.

### Error Messages

Every message the module can raise is listed below.  The routine-specific
["MESSAGES"](#messages) sections say which routine raises which.

```
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
```

## Methods/Subroutines

### Import

```perl
use Class::Abstract;
```

Called automatically by `use Class::Abstract`.  Makes the calling package
abstract by adding `Class::Abstract` to its `@ISA`, exactly as
`use parent 'Class::Abstract'` would.

#### Arguments

- `$class` (required, implicit)

    Always `'Class::Abstract'` in normal usage.  Any import list is ignored.

#### Returns

The class name (`'Class::Abstract'`) as a plain string.  `use` discards
it; the value is only visible to code that calls `import()` directly.

#### Side Effects

Appends `'Class::Abstract'` to the caller's `@ISA`, unless:

- it is already there (so repeated `use` lines are harmless),
- the caller _is_ `Class::Abstract` (that would be circular), or
- the caller is undef or the empty string, which can happen in unusual
contexts such as `BEGIN` blocks inside a string `eval`.  The empty string
would otherwise resolve to `@main::ISA`.

#### Example

```perl
package Vehicle;
use Class::Abstract;          # @Vehicle::ISA is now ('Class::Abstract')
use Class::Abstract;          # no change: already present

package Car;
our @ISA = ('Vehicle');       # Car is concrete

package main;
Car->new;                     # ok
Vehicle->new;                 # croaks (outside a test harness)
```

#### Api Specification

##### Input

```perl
# Positional; no named parameters.
{
    class => { type => 'string', position => 0, optional => 0 },
}
```

##### Output

```perl
{ type => 'string' }    # always the invocant, normally 'Class::Abstract'
```

#### Messages

None.  `import()` never croaks or warns.

#### Formal Specification

```
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
```

### New

```perl
my $obj = ConcreteChild->new;
my $obj = ConcreteChild->new(%initial_attrs);
my $copy = $obj->new;
```

Base constructor with abstract-class enforcement.  Croaks when called on an
abstract class (one with `Class::Abstract` directly in its `@ISA`, or
`Class::Abstract` itself).  Succeeds for concrete subclasses, including
via `$class->SUPER::new(...)` from a child's own `new()`, and returns
a blessed empty hashref.

The check uses the **original invocant** (`$class`), not the package where
`new()` is defined.  That is why `SUPER::new` works: `$class` is still
the concrete subclass, so the check passes.

#### Arguments

- `$class` (required)

    The invocant: a class name or a blessed object.  An object stands in for
    its class, so `$obj->new` builds a new, empty object of the same
    class.  Unblessed references, `undef` and the empty string are rejected.

- `%initial_attrs` (optional, ignored)

    Extra arguments are accepted and discarded, so subclass `new()` methods
    can pass their arguments through `SUPER::new` safely.  Subclasses
    populate their own attributes after calling `SUPER::new`.

#### Returns

A new blessed empty hashref of class `$class`.

#### Side Effects

None beyond the allocation.  Asking about a class name that has never
been loaded does not create that package in the symbol table (`bless`
itself will, as it always does, once the check passes).

#### Example

```perl
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
```

#### Api Specification

##### Input

```perl
# Positional: ($class, @ignored)
{
    class => {
        type     => [ 'string', 'object' ],  # non-empty name or blessed ref
        position => 0,
        optional => 0,
        min      => 1,                       # length, when a string
    },
}
```

##### Output

```perl
{ type => 'object', isa => $class }    # blessed empty hashref
```

#### Messages

```
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
```

#### Formal Specification

```
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
```

### Check\_Abstract

```
Class::Abstract::check_abstract($class);
$class->Class::Abstract::check_abstract;
```

Enforces the abstract-class contract from inside a user-defined `new()`.

If your abstract class defines its own `new()` and that `new()` creates
the object itself (via `bless`) instead of calling
`$class->SUPER::new`, the check in `Class::Abstract::new` is never
reached.  Call `check_abstract()` first to restore it.

#### Arguments

- `$class` (required)

    A class name string or a blessed object.  Unblessed references, `undef`
    and the empty string are rejected.

#### Returns

`undef` when `$class` is concrete or a bypass is active.  Croaks
otherwise.

#### Side Effects

None.  Respects `$BYPASS` and `harness_bypass` exactly as `new()` does.

#### Example

```perl
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
```

#### Api Specification

##### Input

```perl
# Positional: ($class)
{
    class => {
        type     => [ 'string', 'object' ],
        position => 0,
        optional => 0,
        min      => 1,
    },
}
```

##### Output

```perl
{ type => 'undef' }
```

#### Messages

```perl
Message                                    Meaning / Resolution
-------                                    --------------------
Cannot instantiate abstract class CLASS    As for new().
  directly
check_abstract() requires a class name     Argument was an unblessed reference.
  or blessed object, got REFTYPE           Pass $class (or $self).
check_abstract() requires a defined        Argument was undef or ''.  Usually
  class name                               a missing 'my $class = shift'.
```

#### Formal Specification

```
┌─ CheckAbstract ───────────────────────────────────────
│ ΞRegistry
│ inv?    : Package ∪ Object
│ result! : {⊥}
├───────────────────────────────────────────────────────
│ ¬is_direct_abstract(resolve(inv?)) ∨ bypass_active
│ result! = ⊥
└───────────────────────────────────────────────────────

CheckAbstractOp ≙ CheckAbstract ∨ NewAbstract ∨ BadInvocant
```

### Is\_Abstract

```perl
my $bool = SomeClass->is_abstract;
my $bool = $obj->is_abstract;
my $bool = Class::Abstract->is_abstract('SomeClass');
my $bool = Class::Abstract->is_abstract($obj);
```

Returns `1` if the class is **directly** abstract: it has
`Class::Abstract` in its own `@ISA`, or it is `Class::Abstract`.
Returns `0` for concrete subclasses, even though they inherit from an
abstract base.

Any class with `Class::Abstract` in its ancestry inherits this method, so
it works as a class method or an instance method.

#### Arguments

- `$self_or_class` (required)

    The invocant: a class name or a blessed object (whose class is used).

- `$target` (optional)

    A class name or blessed object to check instead of the invocant.  This is
    the form `Class::Abstract->is_abstract('SomeClass')`.  `undef` means
    "not given", so the invocant is checked.

#### Returns

`1` if directly abstract, `0` otherwise, as a plain integer.

#### Side Effects

None.  In particular, asking about a package that does not exist does not
create it.

#### Example

```perl
Animal->is_abstract;                        # 1 (Class::Abstract in @Animal::ISA)
Dog->is_abstract;                           # 0 (@Dog::ISA is ('Animal'))

my $dog = Dog->new(name => 'Rex');
$dog->is_abstract;                          # 0 (checks 'Dog')

Class::Abstract->is_abstract('Animal');     # 1
Class::Abstract->is_abstract($dog);         # 0 (checks ref($dog))
Class::Abstract->is_abstract('No::Such');   # 0, and No::Such is not created
```

#### Api Specification

##### Input

```perl
# Positional: ($self_or_class, $target)
{
    self_or_class => { type => [ 'string', 'object' ], position => 0, optional => 0, min => 1 },
    target        => { type => [ 'string', 'object' ], position => 1, optional => 1, min => 1 },
}
```

##### Output

```perl
{ type => 'integer', min => 0, max => 1 }
```

#### Messages

```
Message                                    Meaning / Resolution
-------                                    --------------------
is_abstract() requires a class name or     The class to check was an unblessed
  object invocant, got REFTYPE             reference.  Pass a name or object.
is_abstract() requires a class name or     The class to check was undef or ''.
  object invocant
```

#### Formal Specification

```
┌─ IsAbstract ──────────────────────────────────────────
│ ΞRegistry
│ self?   : Package ∪ Object
│ target? : Package ∪ Object ∪ {⊥}
│ result! : {0, 1}
├───────────────────────────────────────────────────────
│ c = resolve(if target? = ⊥ then self? else target?)
│ result! = 1 ⇔ is_direct_abstract(c)
└───────────────────────────────────────────────────────
```

## Limitations

- Incompatible change in 0.03: enforcement is on under a test harness

    Up to 0.02, `harness_bypass` defaulted to 1, so `Animal->new`
    silently succeeded whenever `$ENV{HARNESS_ACTIVE}` was set.  That hid
    mistakes in the test suite of every distribution using Class::Abstract,
    which is exactly where an accidental instantiation of an abstract class
    ought to be caught.  The default is now 0.  A test suite that relied on
    the old behaviour will now croak with "Cannot instantiate abstract class
    ... directly".  Either fix the test to instantiate a concrete subclass,
    wrap the call in `local $Class::Abstract::BYPASS = 1`, or restore the
    old default with `$Class::Abstract::config{harness_bypass} = 1`.

- Only constructors that reach new() or check\_abstract() are guarded

    `bless {}, 'Animal'`, ["dclone" in Storable](https://metacpan.org/pod/Storable#dclone), `thaw`, and any `new()`
    override that forgets to call `check_abstract()` all produce abstract
    instances without complaint.  Enforcement is a runtime convention, not a
    language guarantee.

- Only direct @ISA is checked

    `_is_direct_abstract` looks only at the invocant's own `@ISA`.  If
    `Class::Abstract` appears higher in the MRO (e.g. `Dog` inherits
    `Animal`, which is abstract), `Dog` is **not** abstract, which is the
    intended behaviour.  It also means a subclass must opt in explicitly to be
    abstract:

    ```perl
    package Mammal;
    use parent 'Class::Abstract', 'Animal';   # both in @ISA; Mammal is abstract
    ```

- `isa()` cannot distinguish abstract from concrete

    `Dog->isa('Class::Abstract')` is true because Dog inherits from
    Class::Abstract transitively.  Use `is_abstract()` to tell a class that
    is itself abstract apart from one that merely descends from an abstract
    class.

- `can('new')` returns the croak-stub

    `Animal->can('new')` returns `\&Class::Abstract::new`, a true CODE
    ref.  The method is callable; it just croaks.

- new() discards constructor arguments

    The base constructor ignores everything after `$class` and returns an
    empty blessed hashref.  Subclasses populate their own attributes after
    calling `SUPER::new`, or override `new()` (and call `check_abstract()`).

- Bypass is global and loosely typed

    `$BYPASS` switches enforcement off for _every_ class, not just the one
    under test, and any true value counts (including `"false"` and
    `"0E0"`).  Always use `local`.  `$BYPASS` also short-circuits the
    harness check, so `harness_bypass = 0` does **not** re-enable enforcement
    while `$BYPASS` is true.  To be sure enforcement is on regardless of
    what the surrounding code has set, clear both:

    ```
    local $Class::Abstract::BYPASS = 0;
    local $Class::Abstract::config{harness_bypass} = 0;
    ```

- Old-style package separator

    Class names written with the obsolete `'` separator (`Foo'Bar`) are not
    translated to `Foo::Bar` when looking up `@ISA`, so they report as
    concrete.

- Thread safety

    No shared mutable state exists beyond `$BYPASS` and `%config`, which
    are read-only in normal operation.  `import()` writes to the caller's
    `@ISA`, normally at compile time; that is safe as long as modules are not
    `require`d concurrently from several threads.

- Not for Moo/Moose

    Moo's `requires` and Moose's abstract-class extensions give similar
    guarantees within their own object systems.  This module is for plain-Perl
    OO only.

## Formal Specification

Shared definitions used by the per-routine specifications above.

```
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
```

## Public Variables

### `$Bypass`

Set to a true value to disable the abstract-class croak.  Use `local`:

```
local $Class::Abstract::BYPASS = 1;
```

**Warning:** any true value (including `"false"` and `"0E0"`) enables
the bypass.

### `%Config`

- `harness_bypass` (default: 0)

    When true, the abstract-class croak is suppressed whenever
    `$ENV{HARNESS_ACTIVE}` is set.  The default was 1 up to version 0.02;
    set it to 1 to get that behaviour back.  `$BYPASS` takes precedence
    (see ["LIMITATIONS"](#limitations)).

## Dependencies

[Carp](https://metacpan.org/pod/Carp) (core),
[Scalar::Util](https://metacpan.org/pod/Scalar%3A%3AUtil) (core),
[Readonly](https://metacpan.org/pod/Readonly),
[Return::Set](https://metacpan.org/pod/Return%3A%3ASet).

## See Also

- [Test Dashboard](https://nigelhorne.github.io/Class-Abstract/coverage/)
- [Sub::Abstract](https://metacpan.org/pod/Sub%3A%3AAbstract)

    Sister module: enforces abstract (pure-virtual) method contracts.
    Pair with `Class::Abstract` to create fully enforced abstract base classes.

- [Sub::Private](https://metacpan.org/pod/Sub%3A%3APrivate)

    Sister module: enforces strictly private (owner-only) access.

- [Sub::Protected](https://metacpan.org/pod/Sub%3A%3AProtected)

    Sister module: enforces protected (owner + subclass) access.

## Author

Nigel Horne, `<njh at nigelhorne.com>`

## Licence and Copyright

Copyright 2026 Nigel Horne.

Usage is subject to the GPL2 licence terms.
If you use it, please let me know.
