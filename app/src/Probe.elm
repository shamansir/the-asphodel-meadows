port module Probe exposing (main)

{-| Headless harness for the clock spike — the numeric half of §12 step 1.

Renders nothing. It exercises `Fold` directly and checks the three properties
the whole architecture rests on:

1.  **Seek-anywhere.** State at an arbitrary `t` is well-defined and sane.
2.  **Determinism.** `t` and `t + cycle` produce byte-identical state, which is
    the same guarantee that makes two browsers agree at the same wall clock.
3.  **Continuity.** Within a scene, nothing teleports between adjacent frames —
    the failure mode you get if a beat is ever treated as a delta.

Run with `node probe.js` from `app/`.

-}

import Dict
import Fold
import Json.Decode as D
import Platform
import Script exposing (Chunk)


port out : String -> Cmd msg


main : Program String () ()
main =
    Platform.worker
        { init = init
        , update = \_ m -> ( m, Cmd.none )
        , subscriptions = \_ -> Sub.none
        }


init : String -> ( (), Cmd () )
init raw =
    case D.decodeString Script.decoder raw of
        Err err ->
            ( (), out ("DECODE FAILED\n" ++ D.errorToString err) )

        Ok chunk ->
            ( (), out (String.join "\n" (report chunk)) )


report : Chunk -> List String
report chunk =
    List.concat
        [ [ "== samples (seek-anywhere)" ]
        , List.map (sample chunk) [ 0, 5, 8.5, 13, 22.5, 36, 41.5, 65, 78, 95, 130, 143, 178 ]
        , [ "", "== determinism: state(t) == state(t + cycle)" ]
        , [ cycleCheck chunk [ 3, 17.25, 44, 61, 88.5, 121, 159.75 ] ]
        , [ "", "== continuity: largest per-frame move inside a scene" ]
        , [ continuityCheck chunk ]
        ]



-- SAMPLES


sample : Chunk -> Float -> String
sample chunk t =
    case Fold.seek chunk t of
        Nothing ->
            pad 8 (fmt t) ++ "  NO SCENE"

        Just found ->
            let
                st =
                    Fold.stateAt found.scene found.localT

                actors =
                    Dict.toList st.actors
                        |> List.map
                            (\( id, a ) ->
                                String.dropLeft 3 id
                                    ++ "["
                                    ++ fmt (Tuple.first a.pos)
                                    ++ ","
                                    ++ fmt (Tuple.second a.pos)
                                    ++ " "
                                    ++ a.pose
                                    ++ "/"
                                    ++ a.expr
                                    ++ (if a.moving then
                                            "/" ++ a.act

                                        else
                                            ""
                                       )
                                    ++ "]"
                            )
                        |> String.join " "

                bubbles =
                    st.bubbles
                        |> List.map
                            (\b ->
                                "\""
                                    ++ String.join " " (Fold.revealed b)
                                    ++ "\""
                            )
                        |> String.join " "
            in
            pad 8 (fmt t)
                ++ pad 7 found.scene.id
                ++ pad 8 (fmt found.localT)
                ++ pad 62 actors
                ++ bubbles



-- DETERMINISM


cycleCheck : Chunk -> List Float -> String
cycleCheck chunk ts =
    let
        bad =
            ts
                |> List.filter (\t -> digest chunk t /= digest chunk (t + chunk.cycle))
    in
    if List.isEmpty bad then
        "  ok — all " ++ String.fromInt (List.length ts) ++ " samples identical one cycle later"

    else
        "  FAILED at " ++ String.join ", " (List.map fmt bad)


digest : Chunk -> Float -> String
digest chunk t =
    case Fold.seek chunk t of
        Nothing ->
            "none"

        Just found ->
            let
                st =
                    Fold.stateAt found.scene found.localT
            in
            Dict.toList st.actors
                |> List.map
                    (\( id, a ) ->
                        id
                            ++ fmt (Tuple.first a.pos)
                            ++ fmt (Tuple.second a.pos)
                            ++ a.pose
                            ++ a.expr
                            ++ fmt a.poseP
                    )
                |> String.join "|"
                |> (\s -> s ++ fmt (Tuple.first st.camAt) ++ fmt st.camZoom)



-- CONTINUITY


continuityCheck : Chunk -> String
continuityCheck chunk =
    let
        step =
            1 / 60

        n =
            floor (chunk.cycle / step)

        positions t =
            Fold.seek chunk t
                |> Maybe.map
                    (\f ->
                        ( f.scene.id
                        , Fold.stateAt f.scene f.localT
                            |> .actors
                            |> Dict.toList
                            |> List.map (Tuple.second >> .pos)
                        )
                    )

        worst i ( best, bestT ) =
            let
                t =
                    toFloat i * step
            in
            case ( positions t, positions (t + step) ) of
                ( Just ( sa, pa ), Just ( sb, pb ) ) ->
                    -- a cut between scenes is allowed to teleport; a frame
                    -- inside one is not
                    if sa /= sb then
                        ( best, bestT )

                    else
                        let
                            d =
                                List.map2 dist pa pb |> List.maximum |> Maybe.withDefault 0
                        in
                        if d > best then
                            ( d, t )

                        else
                            ( best, bestT )

                _ ->
                    ( best, bestT )

        ( maxMove, atT ) =
            List.foldl worst ( 0, 0 ) (List.range 0 (n - 1))
    in
    "  max "
        ++ fmt (maxMove * 1000)
        ++ " milli-stage-units per frame at t="
        ++ fmt atT
        ++ (if maxMove < 0.01 then
                "  (ok — no teleports)"

            else
                "  (SUSPICIOUS — something is behaving like a delta)"
           )


dist : ( Float, Float ) -> ( Float, Float ) -> Float
dist ( ax, ay ) ( bx, by ) =
    sqrt ((bx - ax) ^ 2 + (by - ay) ^ 2)



-- FORMATTING


fmt : Float -> String
fmt f =
    let
        r =
            round (f * 100)
    in
    String.fromInt (r // 100)
        ++ "."
        ++ String.padLeft 2 '0' (String.fromInt (modBy 100 (abs r)))


pad : Int -> String -> String
pad n s =
    String.padRight n ' ' s
