module Rng exposing (float01, phase)

{-| Deterministic pseudo-randomness (ARCHITECTURE.md §1).

Idle sway, blinks and breathing are not in the script, but they still have to
match across viewers or the shared-moment promise leaks. Seeding from stable
ids instead of a runtime seed means every browser computes the same wiggle.

xorshift32, no multiplies — a 32-bit multiply would overflow JS float
precision before `Bitwise` could coerce it back.

-}

import Bitwise


hashString : String -> Int
hashString s =
    String.foldl
        (\c acc -> Bitwise.shiftRightZfBy 0 (xorshift (acc + Char.toCode c)))
        2166136261
        s


xorshift : Int -> Int
xorshift s0 =
    let
        a =
            Bitwise.shiftRightZfBy 0 (Bitwise.xor s0 (Bitwise.shiftLeftBy 13 s0))

        b =
            Bitwise.xor a (Bitwise.shiftRightZfBy 17 a)
    in
    Bitwise.shiftRightZfBy 0 (Bitwise.xor b (Bitwise.shiftLeftBy 5 b))


{-| Stable 0..1 for a seed string.
-}
float01 : String -> Float
float01 s =
    toFloat (hashString s) / 4294967296


{-| Stable 0..2π offset, so two characters never breathe in lockstep.
-}
phase : String -> Float
phase s =
    float01 s * 2 * pi
