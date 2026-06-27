# Integer-Tick Ideal Model

This page documents the first Lean model in `lean/HakoniwaTimeSpec/IdealModel.lean`.
It is intentionally narrow in scope: it formalizes an integer-tick ideal model of
Hakoniwa time synchronization. It does not yet formalize delayed observation,
federated hierarchy, scheduler fairness over wall-clock time, floating-point
execution, or conformance between the implementation and this abstract model.

## Scope of the model

The model uses natural-number ticks rather than real-valued or floating-point
time:

```lean
abbrev Tick := Nat
```

Mathematically, this means:

$$
\mathrm{Tick} = \mathbb{N}.
$$

This choice makes the first model close to executable simulation traces and CI
checks. In this model, time only moves forward by adding a configured number of
ticks. The core and each asset have their own step size:

```lean
structure Params (n : Nat) where
  dmax : Tick
  dCore : Tick
  dAsset : Fin n → Tick
```

For a system with `n` assets, a state contains one core clock and one local clock
per asset:

```lean
structure State (n : Nat) where
  core : Tick
  asset : Fin n → Tick
```

The informal mathematical names used below are:

- $T_c$ for `s.core`.
- $T_i$ for `s.asset i`.
- $D_{\max}$ for `p.dmax`.
- $\Delta T_c$ for `p.dCore`.
- $\Delta T_i$ for `p.dAsset i`.
- $s'$ for the state after one transition.

The initial state sets all clocks to zero:

```lean
def initial (n : Nat) : State n :=
  { core := 0, asset := fun _ => 0 }
```

In mathematical notation:

$$
T_c = 0 \quad\land\quad \forall i,\; T_i = 0.
$$

## Bounded-drift invariant

The central invariant is `Inv`. It states that every asset clock is no later than
the core clock, and that the core clock is at most `dmax` ticks ahead of every
asset clock:

```lean
def Inv {n : Nat} (p : Params n) (s : State n) : Prop :=
  (∀ i, s.asset i ≤ s.core) ∧
    (∀ i, s.core ≤ s.asset i + p.dmax)
```

In mathematical notation:

$$
\mathrm{Inv}_p(s) \;\Longleftrightarrow\;
\forall i,\; T_i \le T_c \land T_c \le T_i + D_{\max}.
$$

This is a local core-to-asset invariant. The pairwise asset skew bound is derived
from it rather than being taken as a primitive assumption.

## Enabled and blocked conditions

An asset may advance only when its next tick would not overtake the core:

```lean
def assetEnabled {n : Nat} (p : Params n) (s : State n) (i : Fin n) : Prop :=
  s.asset i + p.dAsset i ≤ s.core
```

That corresponds to:

$$
\mathrm{assetEnabled}_p(s,i) \;\Longleftrightarrow\;
T_i + \Delta T_i \le T_c.
$$

The core may advance only when the new core time would remain within `dmax` of
every asset:

```lean
def coreEnabled {n : Nat} (p : Params n) (s : State n) : Prop :=
  ∀ i, s.core + p.dCore ≤ s.asset i + p.dmax
```

That corresponds to:

$$
\mathrm{coreEnabled}_p(s) \;\Longleftrightarrow\;
\forall i,\; T_c + \Delta T_c \le T_i + D_{\max}.
$$

The model also gives explicit blocked predicates. An asset is blocked exactly
when its next step would overtake the core:

```lean
def assetBlocked {n : Nat} (p : Params n) (s : State n) (i : Fin n) : Prop :=
  s.core < s.asset i + p.dAsset i
```

In KaTeX form:

$$
\mathrm{assetBlocked}_p(s,i) \;\Longleftrightarrow\;
T_c < T_i + \Delta T_i.
$$

The core is blocked when at least one asset would become more than `dmax` ticks
behind after the core advance:

```lean
def coreBlocked {n : Nat} (p : Params n) (s : State n) : Prop :=
  ∃ i, s.asset i + p.dmax < s.core + p.dCore
```

In KaTeX form:

$$
\mathrm{coreBlocked}_p(s) \;\Longleftrightarrow\;
\exists i,\; T_i + D_{\max} < T_c + \Delta T_c.
$$

A global deadlock is defined as the combination of a blocked core and all assets
being blocked:

```lean
def Deadlocked {n : Nat} (p : Params n) (s : State n) : Prop :=
  coreBlocked p s ∧ ∀ i, assetBlocked p s i
```

In KaTeX form:

$$
\mathrm{Deadlocked}_p(s) \;\Longleftrightarrow\;
\mathrm{coreBlocked}_p(s) \land \forall i,\; \mathrm{assetBlocked}_p(s,i).
$$

Expanded into clock inequalities, this is:

$$
\mathrm{Deadlocked}_p(s) \;\Longleftrightarrow\;
\left(\exists k,\; T_k + D_{\max} < T_c + \Delta T_c\right)
\land
\left(\forall i,\; T_c < T_i + \Delta T_i\right).
$$

This is a state predicate over the integer-tick ideal model. It is not yet a full
wall-clock liveness theorem, because no fairness assumption over an external
scheduler is part of this first model.

## State transitions

The model defines separate state updates for advancing one asset and advancing
the core:

```lean
def assetAdvance {n : Nat} (p : Params n) (s : State n) (i : Fin n) : State n :=
  { s with asset := fun j => if j = i then s.asset i + p.dAsset i else s.asset j }


def coreAdvance {n : Nat} (p : Params n) (s : State n) : State n :=
  { s with core := s.core + p.dCore }
```

For asset advancement of asset $i$, the next state $s'$ is:

<div>
\[
\mathrm{assetAdvance}_p(s,i) = s'
\]
</div>

where

<div>
\[
T_c' = T_c
\]
</div>

and, for each asset $j$,

<div>
\[
T_j' =
\begin{cases}
T_i + \Delta T_i, & j = i, \\
T_j, & j \ne i.
\end{cases}
\]
</div>

For core advancement, the next state $s'$ is:

<div>
\[
\mathrm{coreAdvance}_p(s) = s'
\]
</div>

where

<div>
\[
T_c' = T_c + \Delta T_c
\]
</div>

and, for each asset $j$,

<div>
\[
T_j' = T_j.
\]
</div>

The transition relation is expressed as an inductive proposition:

```lean
inductive Step {n : Nat} (p : Params n) : State n → State n → Prop where
  | asset {s : State n} (i : Fin n) (h : assetEnabled p s i) :
      Step p s (assetAdvance p s i)
  | assetStutter {s : State n} (i : Fin n) (h : ¬ assetEnabled p s i) :
      Step p s s
  | core {s : State n} (h : coreEnabled p s) :
      Step p s (coreAdvance p s)
  | coreStutter {s : State n} (h : ¬ coreEnabled p s) :
      Step p s s
```

The four constructors correspond to the following inference rules.

Asset advance:

<div>
\[
\frac{\mathrm{assetEnabled}_p(s,i)}
     {\mathrm{Step}_p\!\left(s,\mathrm{assetAdvance}_p(s,i)\right)}.
\]
</div>

Asset stutter:

<div>
\[
\frac{\neg\,\mathrm{assetEnabled}_p(s,i)}
     {\mathrm{Step}_p(s,s)}.
\]
</div>

Core advance:

<div>
\[
\frac{\mathrm{coreEnabled}_p(s)}
     {\mathrm{Step}_p\!\left(s,\mathrm{coreAdvance}_p(s)\right)}.
\]
</div>

Core stutter:

<div>
\[
\frac{\neg\,\mathrm{coreEnabled}_p(s)}
     {\mathrm{Step}_p(s,s)}.
\]
</div>

Equivalently, the non-stuttering transitions can be expanded as:

<div>
\[
\begin{aligned}
&\mathrm{assetEnabled}_p(s,i)
  \Rightarrow
  \mathrm{Step}_p\!\left(s,\mathrm{assetAdvance}_p(s,i)\right), \\
&\mathrm{coreEnabled}_p(s)
  \Rightarrow
  \mathrm{Step}_p\!\left(s,\mathrm{coreAdvance}_p(s)\right).
\end{aligned}
\]
</div>

The stutter constructors model the blocked branch of the informal rule “advance
if enabled, otherwise stay.” This avoids requiring the Lean definition of `Step`
to compute a decision procedure for every guard.

Reachability is the finite reflexive-transitive closure of `Step` from the zero
state:

```lean
inductive Reachable {n : Nat} (p : Params n) : State n → Prop where
  | init : Reachable p (initial n)
  | step {s t : State n} : Reachable p s → Step p s t → Reachable p t
```

The two constructors are:

Initial reachability:

<div>
\[
\mathrm{Reachable}_p\!\left(\mathrm{initial}(n)\right).
\]
</div>

One-step closure:

<div>
\[
\frac{\mathrm{Reachable}_p(s) \qquad \mathrm{Step}_p(s,t)}
     {\mathrm{Reachable}_p(t)}.
\]
</div>

## Proved properties

### Initial invariant

The first theorem proves that the zero state satisfies the bounded-drift
invariant:

```lean
theorem initial_inv {n : Nat} (p : Params n) : Inv p (initial n)
```

Mathematically:

$$
\mathrm{Inv}_p\!\left(\mathrm{initial}(n)\right).
$$

Expanded at time zero:

$$
\forall i,\; 0 \le 0 \land 0 \le 0 + D_{\max}.
$$

### Invariant preservation

The next two theorems prove that enabled asset and core advances preserve the
bounded-drift invariant:

```lean
theorem asset_advance_preserves_inv {n : Nat} {p : Params n} {s : State n}
    (i : Fin n) :
    Inv p s → assetEnabled p s i → Inv p (assetAdvance p s i)
```

In KaTeX form:

$$
\mathrm{Inv}_p(s) \land \mathrm{assetEnabled}_p(s,i)
\Rightarrow
\mathrm{Inv}_p\!\left(\mathrm{assetAdvance}_p(s,i)\right).
$$

This theorem says that if the current state satisfies the invariant and asset
$i$ is allowed to advance, then the state produced by `assetAdvance` also
satisfies the invariant.

```lean
theorem core_advance_preserves_inv {n : Nat} {p : Params n} {s : State n} :
    Inv p s → coreEnabled p s → Inv p (coreAdvance p s)
```

In KaTeX form:

$$
\mathrm{Inv}_p(s) \land \mathrm{coreEnabled}_p(s)
\Rightarrow
\mathrm{Inv}_p\!\left(\mathrm{coreAdvance}_p(s)\right).
$$

This theorem says that if the current state satisfies the invariant and the core
is allowed to advance, then the state produced by `coreAdvance` also satisfies
the invariant.

The transition-level preservation theorem then covers all `Step` constructors,
including stutter transitions:

```lean
theorem step_preserves_inv {n : Nat} {p : Params n} {s t : State n} :
    Inv p s → Step p s t → Inv p t
```

In KaTeX form:

$$
\mathrm{Inv}_p(s) \land \mathrm{Step}_p(s,t)
\Rightarrow
\mathrm{Inv}_p(t).
$$

Finally, induction over finite reachability gives the invariant for every
reachable state:

```lean
theorem reachable_preserves_inv {n : Nat} {p : Params n} {s : State n} :
    Reachable p s → Inv p s
```

In KaTeX form:

$$
\mathrm{Reachable}_p(s) \Rightarrow \mathrm{Inv}_p(s).
$$

The proof structure is:

$$
\mathrm{Inv}_p(s_0)
\land
\left(\forall s,t,\; \mathrm{Inv}_p(s) \land \mathrm{Step}_p(s,t) \Rightarrow \mathrm{Inv}_p(t)\right)
\Rightarrow
\forall s,\; \mathrm{Reachable}_p(s) \Rightarrow \mathrm{Inv}_p(s).
$$

### Pairwise asset skew bound

The model derives the pairwise asset skew bound from `Inv`:

```lean
theorem asset_pair_skew_bound {n : Nat} {p : Params n} {s : State n} :
    Inv p s → ∀ i j, s.asset i ≤ s.asset j + p.dmax ∧ s.asset j ≤ s.asset i + p.dmax
```

In KaTeX form:

$$
\mathrm{Inv}_p(s)
\Rightarrow
\forall i,j,\; T_i \le T_j + D_{\max} \land T_j \le T_i + D_{\max}.
$$

Because the model uses `Nat`, the bound is written as two directional
inequalities rather than with signed absolute value:

$$
\forall i,j,\; T_i \le T_j + D_{\max} \land T_j \le T_i + D_{\max}.
$$

The reachable-state version follows by composing this theorem with
`reachable_preserves_inv`:

```lean
theorem reachable_asset_pair_skew_bound {n : Nat} {p : Params n} {s : State n}
    (hReach : Reachable p s) :
    ∀ i j, s.asset i ≤ s.asset j + p.dmax ∧ s.asset j ≤ s.asset i + p.dmax
```

In KaTeX form:

$$
\mathrm{Reachable}_p(s)
\Rightarrow
\forall i,j,\; T_i \le T_j + D_{\max} \land T_j \le T_i + D_{\max}.
$$

Equivalently, for every state that can be obtained by finitely many ideal
transitions from the zero state, any two asset clocks differ by at most
$D_{\max}$ in the two-sided natural-number sense:

$$
\forall s,\; \mathrm{Reachable}_p(s)
\Rightarrow
\forall i,j,\;
\left(T_i \le T_j + D_{\max}\right) \land
\left(T_j \le T_i + D_{\max}\right).
$$

### General no-deadlock condition

The first model also proves a general no-deadlock condition:

```lean
theorem no_deadlock_general {n : Nat} {p : Params n} {s : State n}
    (hProgress : ∀ i, p.dCore + p.dAsset i ≤ p.dmax) :
    ¬ Deadlocked p s
```

The sufficient condition is:

$$
\forall i,\; \Delta T_c + \Delta T_i \le D_{\max}.
$$

The theorem itself is:

$$
\left(\forall i,\; \Delta T_c + \Delta T_i \le D_{\max}\right)
\Rightarrow
\neg\,\mathrm{Deadlocked}_p(s).
$$

The contradiction argument is local to one asset selected by `coreBlocked`.
If the core is blocked by asset $i$, then:

$$
T_i + D_{\max} < T_c + \Delta T_c.
$$

If every asset is blocked, then the same asset $i$ also satisfies:

$$
T_c < T_i + \Delta T_i.
$$

Combining $T_c \le T_i + \Delta T_i$ with
$\Delta T_c + \Delta T_i \le D_{\max}$ gives:

$$
T_c + \Delta T_c \le T_i + D_{\max},
$$

which contradicts the core-blocked inequality. Therefore the ideal model has no
state satisfying `Deadlocked` under the general progress condition.

## What this page does not claim

This page documents only the current integer-tick ideal model. The following are
outside the scope of the present Lean file:

- delayed or stale observations;
- wall-clock scheduler fairness;
- runtime execution time and communication delay bounds;
- multi-level federated clock hierarchies;
- floating-point or real-valued time;
- proof that the production implementation conforms to this abstract transition
  relation.

Those topics can be added as later Lean modules once the corresponding abstract
semantics are fixed.
