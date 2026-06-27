import Std

namespace HakoniwaTimeSpec
namespace IdealModel

/-- Integer ticks for the first ideal model.

This first formalization deliberately uses `Nat` rather than floating-point
or real-valued time. The intent is to capture the discrete tick model that is
closest to executable traces and CI checks.
-/
abbrev Tick := Nat

/-- Time synchronization parameters for `n` assets. -/
structure Params (n : Nat) where
  dmax : Tick
  dCore : Tick
  dAsset : Fin n → Tick

/-- Core time and per-asset times. -/
structure State (n : Nat) where
  core : Tick
  asset : Fin n → Tick

/-- Initial state: every clock starts at zero. -/
def initial (n : Nat) : State n :=
  { core := 0, asset := fun _ => 0 }

/-- The ideal bounded-drift invariant.

For every asset `i`, its local time is not ahead of the core time, and the
core time is not more than `dmax` ticks ahead of the asset time.
-/
def Inv {n : Nat} (p : Params n) (s : State n) : Prop :=
  (∀ i, s.asset i ≤ s.core) ∧
    (∀ i, s.core ≤ s.asset i + p.dmax)

/-- Asset `i` may advance exactly when it does not overtake the core. -/
def assetEnabled {n : Nat} (p : Params n) (s : State n) (i : Fin n) : Prop :=
  s.asset i + p.dAsset i ≤ s.core

/-- The core may advance exactly when it will remain within `dmax` of every asset. -/
def coreEnabled {n : Nat} (p : Params n) (s : State n) : Prop :=
  ∀ i, s.core + p.dCore ≤ s.asset i + p.dmax

/-- The state obtained by advancing one asset. -/
def assetAdvance {n : Nat} (p : Params n) (s : State n) (i : Fin n) : State n :=
  { s with asset := fun j => if j = i then s.asset i + p.dAsset i else s.asset j }

/-- The state obtained by advancing the core. -/
def coreAdvance {n : Nat} (p : Params n) (s : State n) : State n :=
  { s with core := s.core + p.dCore }

/-- A single ideal transition.

The `assetStutter` and `coreStutter` constructors model the blocked branch of
the informal "if enabled, advance; otherwise stay" rule without requiring a
computable decision procedure for every guard.
-/
inductive Step {n : Nat} (p : Params n) : State n → State n → Prop where
  | asset {s : State n} (i : Fin n) (h : assetEnabled p s i) :
      Step p s (assetAdvance p s i)
  | assetStutter {s : State n} (i : Fin n) (h : ¬ assetEnabled p s i) :
      Step p s s
  | core {s : State n} (h : coreEnabled p s) :
      Step p s (coreAdvance p s)
  | coreStutter {s : State n} (h : ¬ coreEnabled p s) :
      Step p s s

/-- States reachable by finitely many ideal transitions from the zero state. -/
inductive Reachable {n : Nat} (p : Params n) : State n → Prop where
  | init : Reachable p (initial n)
  | step {s t : State n} : Reachable p s → Step p s t → Reachable p t

/-- No component is enabled.

For assets, the blocked condition is written as a strict inequality. Over
natural-number ticks this is equivalent to `¬ assetEnabled p s i`, and it keeps
the progress proof independent of theorem names for converting `¬ a ≤ b`.
-/
def Deadlocked {n : Nat} (p : Params n) (s : State n) : Prop :=
  ¬ coreEnabled p s ∧ ∀ i, s.core < s.asset i + p.dAsset i

/-- The zero state satisfies the bounded-drift invariant. -/
theorem initial_inv {n : Nat} (p : Params n) : Inv p (initial n) := by
  constructor
  · intro i
    simp [initial]
  · intro i
    simp [initial]

/-- Advancing an enabled asset preserves the bounded-drift invariant. -/
theorem asset_advance_preserves_inv {n : Nat} {p : Params n} {s : State n}
    (i : Fin n) :
    Inv p s → assetEnabled p s i → Inv p (assetAdvance p s i) := by
  intro hInv hEnabled
  constructor
  · intro j
    by_cases hji : j = i
    · subst j
      simp [assetAdvance]
      exact hEnabled
    · simp [assetAdvance, hji]
      exact hInv.1 j
  · intro j
    by_cases hji : j = i
    · subst j
      simp [assetAdvance]
      exact Nat.le_trans (hInv.2 i)
        (Nat.add_le_add_right (Nat.le_add_right (s.asset i) (p.dAsset i)) p.dmax)
    · simp [assetAdvance, hji]
      exact hInv.2 j

/-- Advancing the enabled core preserves the bounded-drift invariant. -/
theorem core_advance_preserves_inv {n : Nat} {p : Params n} {s : State n} :
    Inv p s → coreEnabled p s → Inv p (coreAdvance p s) := by
  intro hInv hEnabled
  constructor
  · intro i
    simp [coreAdvance]
    exact Nat.le_trans (hInv.1 i) (Nat.le_add_right s.core p.dCore)
  · intro i
    simp [coreAdvance]
    exact hEnabled i

/-- Every ideal transition preserves the bounded-drift invariant. -/
theorem step_preserves_inv {n : Nat} {p : Params n} {s t : State n} :
    Inv p s → Step p s t → Inv p t := by
  intro hInv hStep
  cases hStep with
  | asset i hEnabled =>
      exact asset_advance_preserves_inv (p := p) (s := s) i hInv hEnabled
  | assetStutter _ _ =>
      simpa using hInv
  | core hEnabled =>
      exact core_advance_preserves_inv (p := p) (s := s) hInv hEnabled
  | coreStutter _ =>
      simpa using hInv

/-- Every reachable state satisfies the bounded-drift invariant. -/
theorem reachable_preserves_inv {n : Nat} {p : Params n} {s : State n} :
    Reachable p s → Inv p s := by
  intro hReach
  induction hReach with
  | init =>
      exact initial_inv p
  | step hReach hStep ih =>
      exact step_preserves_inv ih hStep

/-- Any two assets are within `dmax` ticks of each other in either direction. -/
theorem asset_pair_skew_bound {n : Nat} {p : Params n} {s : State n} :
    Inv p s → ∀ i j, s.asset i ≤ s.asset j + p.dmax ∧ s.asset j ≤ s.asset i + p.dmax := by
  intro hInv i j
  constructor
  · exact Nat.le_trans (hInv.1 i) (hInv.2 j)
  · exact Nat.le_trans (hInv.1 j) (hInv.2 i)

/-- Pairwise asset skew is bounded in every reachable state. -/
theorem reachable_asset_pair_skew_bound {n : Nat} {p : Params n} {s : State n}
    (hReach : Reachable p s) :
    ∀ i j, s.asset i ≤ s.asset j + p.dmax ∧ s.asset j ≤ s.asset i + p.dmax := by
  exact asset_pair_skew_bound (reachable_preserves_inv hReach)

/--
General progress condition: if each asset/core step pair fits within `dmax`,
then the ideal model has no global deadlock.
-/
theorem no_deadlock_general {n : Nat} {p : Params n} {s : State n}
    (hProgress : ∀ i, p.dCore + p.dAsset i ≤ p.dmax) :
    ¬ Deadlocked p s := by
  intro hDead
  have hCoreEnabled : coreEnabled p s := by
    intro i
    have hCoreLeAsset : s.core ≤ s.asset i + p.dAsset i :=
      Nat.le_of_lt (hDead.2 i)
    calc
      s.core + p.dCore ≤ (s.asset i + p.dAsset i) + p.dCore :=
        Nat.add_le_add_right hCoreLeAsset p.dCore
      _ = s.asset i + (p.dAsset i + p.dCore) := by
        rw [Nat.add_assoc]
      _ = s.asset i + (p.dCore + p.dAsset i) := by
        rw [Nat.add_comm (p.dAsset i) p.dCore]
      _ ≤ s.asset i + p.dmax :=
        Nat.add_le_add_left (hProgress i) (s.asset i)
  exact hDead.1 hCoreEnabled

end IdealModel
end HakoniwaTimeSpec
