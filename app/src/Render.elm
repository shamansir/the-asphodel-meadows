module Render exposing (Layout, layout, scene)

{-| Canvas rendering for the clock spike.

Two things here are load-bearing rather than decorative:

  - **Rubber-hose limbs.** Arms and legs are quadratic curves with round caps,
    so a pose is a handful of angles rather than a drawn frame. That is what
    lets a closed verb vocabulary (§4.3) cover a whole performance.

  - **Stepped sampling.** Poses are sampled at 12fps while the canvas runs at
    60. Smooth interpolation reads as a slideshow of tweens; stepping reads as
    animation. Camera and text reveal stay smooth.

Everything below that is character-specific — rigs, poses, faces — belongs in
`rig.json` in the data repo once the engine goes world-agnostic (§4.3). It is
hardcoded here only because the spike has no asset pipeline yet.

-}

import Canvas exposing (Renderable, Shape)
import Canvas.Settings exposing (fill, stroke)
import Canvas.Settings.Advanced exposing (alpha, rotate, scale, transform, translate)
import Canvas.Settings.Line exposing (LineCap(..), LineJoin(..), lineCap, lineJoin, lineWidth)
import Canvas.Settings.Text exposing (TextAlign(..), TextBaseLine(..), align, baseLine, font)
import Color exposing (Color)
import Dict
import Fold exposing (ActorState, Bubble, State)
import Rng



-- LAYOUT


{-| The stage is a 16:9 box letterboxed into the canvas. Stage coordinates are
0..1 on both axes, so the script never mentions pixels.
-}
type alias Layout =
    { w : Float
    , h : Float
    , ox : Float
    , oy : Float
    , boxW : Float
    , boxH : Float
    , camX : Float
    , camY : Float
    , zoom : Float
    }


layout : ( Float, Float ) -> State -> Layout
layout ( w, h ) st =
    let
        boxW =
            min w (h * 16 / 9)

        boxH =
            boxW * 9 / 16

        ( cx, cy ) =
            st.camAt
    in
    { w = w
    , h = h
    , ox = (w - boxW) / 2
    , oy = (h - boxH) / 2
    , boxW = boxW
    , boxH = boxH
    , camX = cx
    , camY = cy
    , zoom = st.camZoom
    }


toScreen : Layout -> ( Float, Float ) -> ( Float, Float )
toScreen l ( sx, sy ) =
    ( l.ox + l.boxW / 2 + (sx - l.camX) * l.boxW * l.zoom
    , l.oy + l.boxH / 2 + (sy - l.camY) * l.boxH * l.zoom
    )


{-| Pixels per stage-y unit. All character geometry is expressed against this.
-}
unit : Layout -> Float
unit l =
    l.boxH * l.zoom



-- SCENE


scene : Layout -> String -> State -> Float -> Bool -> List Renderable
scene l loc st t stepped =
    let
        ts =
            if stepped then
                toFloat (floor (t * 12)) / 12

            else
                t

        actors =
            Dict.toList st.actors
                -- painter's algorithm: whoever is further down the stage is nearer
                |> List.sortBy (\( _, a ) -> Tuple.second a.pos)
    in
    List.concat
        [ background l loc st.shot ts
        , List.concatMap (\( id, a ) -> drawActor l id a ts) actors
        , List.concatMap (drawBubble l st) st.bubbles

        -- ink goes over everything except the letterbox
        , List.concatMap (drawMark l loc) st.marks
        , letterbox l
        ]



-- BACKGROUND


{-| Three palettes that must not blend (style.md). The House is cold and
administrative, the Fields are a pleasant endless grey-green, London is
over-warm and always slightly wrong because it is remembered.
-}
type alias Palette =
    { sky : Color
    , band1 : Color
    , band2 : Color
    , far : Color
    , mid : Color
    , ground : Color
    , prop : Color
    , propTrim : Color
    , lamp : Color
    }


palette : String -> Palette
palette loc =
    case loc of
        -- Charon's terminal: wet slate, one sour lamp
        "loc.bank" ->
            { sky = Color.rgb255 42 48 58
            , band1 = Color.rgb255 50 57 68
            , band2 = Color.rgb255 58 66 78
            , far = Color.rgb255 38 44 54
            , mid = Color.rgb255 46 54 64
            , ground = Color.rgb255 62 70 78
            , prop = Color.rgb255 34 40 48
            , propTrim = Color.rgb255 176 150 62
            , lamp = Color.rgb255 226 186 92
            }

        -- the filing halls: crimson order, too many verticals
        "loc.ledgers" ->
            { sky = Color.rgb255 58 38 42
            , band1 = Color.rgb255 68 44 48
            , band2 = Color.rgb255 78 50 54
            , far = Color.rgb255 52 34 38
            , mid = Color.rgb255 64 40 44
            , ground = Color.rgb255 84 56 58
            , prop = Color.rgb255 44 28 32
            , propTrim = Color.rgb255 168 78 76
            , lamp = Color.rgb255 226 150 110
            }

        -- Asphodel: pleasant, endless, and that is the problem with it
        _ ->
            { sky = Color.rgb255 168 176 168
            , band1 = Color.rgb255 158 168 158
            , band2 = Color.rgb255 148 160 150
            , far = Color.rgb255 132 146 136
            , mid = Color.rgb255 142 156 144
            , ground = Color.rgb255 154 168 152
            , prop = Color.rgb255 118 134 122
            , propTrim = Color.rgb255 138 152 138
            , lamp = Color.rgb255 210 214 198
            }


background : Layout -> String -> String -> Float -> List Renderable
background l loc shot t =
    let
        p =
            palette loc
    in
    if shot == "insert" then
        -- a hard cut to the clue, filling frame, on a flat ground. The clue is
        -- the only thing in the world for a moment.
        [ Canvas.shapes [ fill p.band2 ] [ Canvas.rect ( l.ox, l.oy ) l.boxW l.boxH ] ]

    else
        List.concat
            [ [ Canvas.shapes [ fill p.sky ] [ Canvas.rect ( l.ox, l.oy ) l.boxW l.boxH ]
              , Canvas.shapes [ fill p.band1 ] [ stageRect l ( 0, 0.2 ) 1 0.25 ]
              , Canvas.shapes [ fill p.band2 ] [ stageRect l ( 0, 0.4 ) 1 0.25 ]
              ]
            , lamps l p loc t
            , [ hills l p.far 0.52 0.05 (Rng.float01 (loc ++ "far"))
              , hills l p.mid 0.63 0.07 (Rng.float01 (loc ++ "mid"))
              , Canvas.shapes [ fill p.ground ] [ stageRect l ( 0, 0.74 ) 1 0.3 ]
              ]
            , scatter l p loc
            ]


{-| The only warm thing in the House, and always slightly too orange.
-}
lamps : Layout -> Palette -> String -> Float -> List Renderable
lamps l p loc t =
    let
        one i =
            let
                seed =
                    loc ++ "lamp" ++ String.fromInt i

                ( x, y ) =
                    toScreen l ( 0.1 + Rng.float01 seed * 0.85, 0.2 + Rng.float01 (seed ++ "y") * 0.2 )

                -- guttering, deterministically
                flicker =
                    0.9 + 0.1 * sin (t * 3 + Rng.phase seed)

                r =
                    unit l * 0.02 * flicker
            in
            Canvas.shapes [ fill p.lamp, alpha 0.85 ]
                [ Canvas.circle ( x, y ) r ]
    in
    List.map one (List.range 0 3)


hills : Layout -> Color -> Float -> Float -> Float -> Renderable
hills l color baseY amp seed =
    let
        n =
            7

        pointAt i =
            let
                x =
                    toFloat i / toFloat n

                y =
                    baseY - amp * (0.4 + Rng.float01 (String.fromFloat seed ++ String.fromInt i))
            in
            toScreen l ( x, y )

        start =
            toScreen l ( -0.05, baseY + 0.4 )

        segs =
            List.range 0 n
                |> List.concatMap
                    (\i ->
                        let
                            ( px, py ) =
                                pointAt i

                            ( nx, _ ) =
                                toScreen l ( (toFloat i + 0.5) / toFloat n, 0 )
                        in
                        [ Canvas.quadraticCurveTo ( nx, py - unit l * amp * 0.5 ) ( px, py ) ]
                    )

        endPt =
            toScreen l ( 1.05, baseY + 0.4 )
    in
    Canvas.shapes [ fill color ]
        [ Canvas.path start (segs ++ [ Canvas.lineTo endPt ]) ]


{-| Set dressing, placed by hash. Same spot for everyone, forever, without
being listed in the script.

The House gets filing stacks — the horror here is procedural, so the props are
furniture, never fire. Asphodel gets the low pale stalks it is named for.

-}
scatter : Layout -> Palette -> String -> List Renderable
scatter l p loc =
    let
        u =
            unit l

        isHouse =
            loc == "loc.bank" || loc == "loc.ledgers"

        item i =
            let
                seed =
                    loc ++ "prop" ++ String.fromInt i

                x =
                    Rng.float01 seed

                y =
                    0.75 + Rng.float01 (seed ++ "y") * 0.05

                sizeS =
                    (0.05 + Rng.float01 (seed ++ "s") * 0.05) * u

                ( px, py ) =
                    toScreen l ( x, y )
            in
            if isHouse then
                -- a stack of ledgers, leaning slightly, as they have for
                -- several thousand years
                let
                    shelf j =
                        Canvas.rect
                            ( px - sizeS * 0.5 + Rng.float01 (seed ++ String.fromInt j) * sizeS * 0.12
                            , py - sizeS * (0.35 * toFloat (j + 1))
                            )
                            sizeS
                            (sizeS * 0.28)
                in
                [ Canvas.shapes [ fill p.prop ] (List.map shelf (List.range 0 3))
                , Canvas.shapes [ fill p.propTrim, alpha 0.5 ]
                    [ Canvas.rect ( px - sizeS * 0.5, py - sizeS * 0.35 ) sizeS (sizeS * 0.05) ]
                ]

            else
                [ Canvas.shapes [ stroke p.prop, lineWidth (sizeS * 0.07), lineCap RoundCap ]
                    [ Canvas.path ( px, py )
                        [ Canvas.quadraticCurveTo ( px + sizeS * 0.18, py - sizeS * 0.6 ) ( px, py - sizeS * 1.1 ) ]
                    ]
                , Canvas.shapes [ fill p.propTrim ]
                    [ Canvas.circle ( px, py - sizeS * 1.15 ) (sizeS * 0.1) ]
                ]
    in
    List.concatMap item (List.range 0 5)



-- INK


{-| The `annotate` primitive. Reasoning made visible: circles, arrows and link
lines drawn over the stage in one accent colour, hand-inked with a scratchy
draw-on, holding until the next cut.

The jitter is seeded from the mark itself, so the same wobble appears for every
viewer — the ink is deterministic like everything else.

-}
drawMark : Layout -> String -> Fold.Mark -> List Renderable
drawMark l loc m =
    let
        u =
            unit l

        accent =
            if loc == "loc.ledgers" then
                Color.rgb255 250 214 120

            else
                Color.rgb255 246 128 92

        pen =
            [ stroke accent, lineWidth (u * 0.006), lineCap RoundCap, lineJoin RoundJoin ]

        -- deterministic hand-wobble
        jit i amp =
            (Rng.float01 (m.seed ++ String.fromInt i) - 0.5) * amp * u

        ( ax, ay ) =
            toScreen l m.at

        ( bx, by ) =
            toScreen l m.to

        labelAt x y =
            if m.label == "" then
                []

            else
                [ Canvas.text
                    [ font { size = round (u * 0.026), family = "'Comic Sans MS', 'Chalkboard SE', cursive" }
                    , align Center
                    , baseLine Middle
                    , fill accent
                    ]
                    ( x, y )
                    m.label
                ]

        shape =
            case m.kind of
                "arrow" ->
                    let
                        hx =
                            ax + (bx - ax) * m.drawn

                        hy =
                            ay + (by - ay) * m.drawn

                        ang =
                            atan2 (by - ay) (bx - ax)

                        head d =
                            Canvas.path ( hx, hy )
                                [ Canvas.lineTo
                                    ( hx - cos (ang + d) * u * 0.03
                                    , hy - sin (ang + d) * u * 0.03
                                    )
                                ]
                    in
                    [ Canvas.path ( ax, ay )
                        [ Canvas.quadraticCurveTo
                            ( (ax + bx) / 2 + jit 1 0.05, (ay + by) / 2 + jit 2 0.05 )
                            ( hx, hy )
                        ]
                    ]
                        ++ (if m.drawn > 0.85 then
                                [ head 0.5, head -0.5 ]

                            else
                                []
                           )

                "link" ->
                    [ Canvas.path ( ax, ay )
                        [ Canvas.lineTo
                            ( ax + (bx - ax) * m.drawn + jit 3 0.02
                            , ay + (by - ay) * m.drawn + jit 4 0.02
                            )
                        ]
                    ]

                "strike" ->
                    [ Canvas.path ( ax - u * m.r, ay )
                        [ Canvas.lineTo ( ax - u * m.r + 2 * u * m.r * m.drawn, ay + jit 5 0.02 ) ]
                    ]

                "label" ->
                    [ Canvas.path ( ax, ay ) [ Canvas.lineTo ( ax, ay - u * 0.05 * m.drawn ) ] ]

                _ ->
                    -- circle: an overrun ellipse, drawn a little past its own
                    -- start the way a person does it
                    let
                        n =
                            18

                        sweep =
                            m.drawn * 2 * pi * 1.12

                        pt i =
                            let
                                a =
                                    sweep * toFloat i / toFloat n
                            in
                            ( ax + cos a * u * m.r * 1.25 + jit i 0.012
                            , ay + sin a * u * m.r + jit (i + 40) 0.012
                            )
                    in
                    [ Canvas.path (pt 0) (List.map (pt >> Canvas.lineTo) (List.range 1 n)) ]
    in
    Canvas.shapes pen shape
        :: (if m.drawn > 0.9 then
                case m.kind of
                    "label" ->
                        labelAt ax (ay - u * 0.085)

                    "circle" ->
                        labelAt ax (ay - u * (m.r + 0.05))

                    _ ->
                        labelAt ((ax + bx) / 2) ((ay + by) / 2 - u * 0.035)

            else
                []
           )


letterbox : Layout -> List Renderable
letterbox l =
    Canvas.shapes [ fill (Color.rgb255 22 20 28) ]
        [ Canvas.rect ( 0, 0 ) l.w l.oy
        , Canvas.rect ( 0, l.oy + l.boxH ) l.w (l.h - l.oy - l.boxH)
        , Canvas.rect ( 0, 0 ) l.ox l.h
        , Canvas.rect ( l.ox + l.boxW, 0 ) (l.w - l.ox - l.boxW) l.h
        ]
        |> List.singleton



-- CHARACTERS
-- Everything from here to `drawBubble` is what moves into rig.json.


type alias CharDef =
    { body : Color
    , trim : Color
    , height : Float -- in stage-y units
    , girth : Float -- body width as a fraction of height
    , limb : Float -- limb thickness as a fraction of height
    , topper : String
    }


charDef : String -> CharDef
charDef id =
    case id of
        -- All verticals in a world of curves. The only unsaturated figure in
        -- the cast, which is the composition of the whole season.
        "ch.holmes" ->
            { body = Color.rgb255 96 100 112
            , trim = Color.rgb255 54 58 70
            , height = 0.30
            , girth = 0.26
            , limb = 0.034
            , topper = "none"
            }

        -- The noodliest rig. Even his idle has motion.
        "ch.hermes" ->
            { body = Color.rgb255 234 206 138
            , trim = Color.rgb255 186 150 74
            , height = 0.19
            , girth = 0.42
            , limb = 0.052
            , topper = "wings"
            }

        -- Tallest, and never straightened. Everything about him is damp.
        "ch.charon" ->
            { body = Color.rgb255 86 96 100
            , trim = Color.rgb255 178 156 66
            , height = 0.34
            , girth = 0.30
            , limb = 0.038
            , topper = "hood"
            }

        -- Tight where the others are loose: permanently braced.
        "ch.minos" ->
            { body = Color.rgb255 164 66 72
            , trim = Color.rgb255 104 36 44
            , height = 0.25
            , girth = 0.46
            , limb = 0.046
            , topper = "none"
            }

        "ch.persephone" ->
            { body = Color.rgb255 120 172 112
            , trim = Color.rgb255 206 172 76
            , height = 0.26
            , girth = 0.34
            , limb = 0.040
            , topper = "tuft"
            }

        _ ->
            { body = Color.rgb255 200 200 210
            , trim = Color.rgb255 140 140 150
            , height = 0.24
            , girth = 0.5
            , limb = 0.05
            , topper = "none"
            }


{-| A pose is angles, not artwork. Blending two poses is a per-field lerp,
which is the whole reason the agent can choreograph from a closed list.
-}
type alias Pose =
    { armL : Float -- degrees from hanging-straight-down, + swings outward
    , armR : Float
    , bendL : Float -- how far the hose bows
    , bendR : Float
    , spread : Float
    , tilt : Float -- whole-body lean, degrees
    , squash : Float -- 1 = neutral, <1 squat, >1 stretch
    }


poseOf : String -> Pose
poseOf name =
    case name of
        "shrug" ->
            { armL = 118, armR = 118, bendL = -0.5, bendR = 0.5, spread = 0.5, tilt = 0, squash = 0.94 }

        "armsCrossed" ->
            { armL = 52, armR = 52, bendL = 1.4, bendR = -1.4, spread = 0.45, tilt = 0, squash = 1 }

        "handsUp" ->
            { armL = 165, armR = 165, bendL = -0.2, bendR = 0.2, spread = 0.6, tilt = 0, squash = 1.06 }

        "slump" ->
            { armL = 8, armR = 8, bendL = 0.3, bendR = -0.3, spread = 0.35, tilt = 6, squash = 0.86 }

        "point" ->
            { armL = 14, armR = 96, bendL = 0.2, bendR = -0.1, spread = 0.5, tilt = -3, squash = 1.02 }

        "lean" ->
            { armL = 26, armR = 40, bendL = 0.4, bendR = -0.3, spread = 0.7, tilt = 11, squash = 0.98 }

        "crouch" ->
            { armL = 60, armR = 60, bendL = 0.8, bendR = -0.8, spread = 0.9, tilt = 0, squash = 0.7 }

        -- Holmes thinking. Fingertips together, elbows out, nothing else moving.
        "steeple" ->
            { armL = 44, armR = 44, bendL = 1.8, bendR = -1.8, spread = 0.4, tilt = 0, squash = 1.02 }

        -- Hades behind a desk that is too large, at the end of a very long day.
        "lounge" ->
            { armL = 74, armR = 58, bendL = 0.9, bendR = -0.6, spread = 1.3, tilt = 4, squash = 0.72 }

        "seated" ->
            { armL = 30, armR = 30, bendL = 0.5, bendR = -0.5, spread = 1.5, tilt = 0, squash = 0.66 }

        -- bent to the evidence
        "stoop" ->
            { armL = 34, armR = 62, bendL = 0.5, bendR = -0.9, spread = 0.6, tilt = 22, squash = 0.9 }

        "loom" ->
            { armL = 40, armR = 40, bendL = 0.7, bendR = -0.7, spread = 0.75, tilt = 9, squash = 1.12 }

        "reach" ->
            { armL = 12, armR = 92, bendL = 0.2, bendR = -0.2, spread = 0.5, tilt = -4, squash = 1.03 }

        "hide" ->
            { armL = 150, armR = 150, bendL = -1.1, bendR = 1.1, spread = 0.3, tilt = 0, squash = 0.82 }

        "flail" ->
            { armL = 120, armR = 120, bendL = 1.2, bendR = -1.2, spread = 0.9, tilt = 0, squash = 1.05 }

        _ ->
            -- idle
            { armL = 22, armR = 22, bendL = 0.35, bendR = -0.35, spread = 0.5, tilt = 0, squash = 1 }


blendPose : Pose -> Pose -> Float -> Pose
blendPose a b p =
    { armL = lerp a.armL b.armL p
    , armR = lerp a.armR b.armR p
    , bendL = lerp a.bendL b.bendL p
    , bendR = lerp a.bendR b.bendR p
    , spread = lerp a.spread b.spread p
    , tilt = lerp a.tilt b.tilt p
    , squash = lerp a.squash b.squash p
    }


drawActor : Layout -> String -> ActorState -> Float -> List Renderable
drawActor l id a t =
    let
        def =
            charDef id

        u =
            unit l

        ph =
            Rng.phase id

        ( fx, fy ) =
            toScreen l a.pos

        h =
            def.height * u

        basePose =
            blendPose (poseOf a.prevPose) (poseOf a.pose) a.poseP

        -- Act overrides: this is where the noodly business lives. An act only
        -- runs while its beat is in flight, so it stops on its own — no beat
        -- needs to say "stop dancing".
        ( pose, bob, stretch ) =
            if not a.moving then
                -- breathing, so nobody ever stands perfectly still
                ( basePose, sin (t * 1.4 + ph) * h * 0.006, 1 + sin (t * 1.4 + ph) * 0.014 )

            else
                case a.act of
                    "walk" ->
                        let
                            k =
                                t * 7
                        in
                        ( { basePose
                            | armL = basePose.armL + sin k * 26
                            , armR = basePose.armR - sin k * 26
                          }
                        , abs (sin (k * 2)) * h * 0.035
                          -- squash on the down-beat, stretch on the up: the
                          -- single cheapest thing that reads as "cartoon"
                        , 1 + sin (k * 2) * 0.06
                        )

                    "dance" ->
                        let
                            k =
                                t * 5.5
                        in
                        ( { basePose
                            | armL = 100 + sin (k * 1.7) * 85
                            , armR = 100 + sin (k * 1.7 + 2.4) * 85
                            , bendL = sin k * 1.6
                            , bendR = cos (k * 1.3) * 1.6
                            , spread = 0.5 + abs (sin k) * 0.75
                            , tilt = sin (k * 0.8) * 16
                          }
                        , abs (sin k) * h * 0.08
                        , 1 + sin (k * 2) * 0.13
                        )

                    "hop" ->
                        ( basePose, abs (sin (t * 9)) * h * 0.22, 1 + sin (t * 9) * 0.1 )

                    _ ->
                        ( basePose, 0, 1 )

        sy =
            pose.squash * stretch

        sx =
            1 / sy

        parts =
            body l def pose h a.facing
                ++ face l def pose h a.facing a.expr id t
    in
    [ Canvas.group
        [ transform
            [ translate fx (fy - bob)
            , scale (sx * a.facing) sy
            , rotate (degrees pose.tilt)
            ]
        ]
        parts
    ]


body : Layout -> CharDef -> Pose -> Float -> Float -> List Renderable
body l def pose h _ =
    let
        girth =
            h * def.girth

        limb =
            h * def.limb

        hipY =
            -h * 0.42

        shoulderY =
            -h * 0.7

        legLen =
            h * 0.42

        armLen =
            h * 0.36

        leg dir =
            let
                hipX =
                    dir * girth * 0.26

                footX =
                    dir * (girth * 0.26 + pose.spread * girth * 0.35)

                ctrl =
                    ( hipX + dir * limb * 0.7, hipY + legLen * 0.55 )
            in
            Canvas.path ( hipX, hipY ) [ Canvas.quadraticCurveTo ctrl ( footX, 0 ) ]

        arm dir angle bend =
            let
                shX =
                    dir * girth * 0.45

                handX =
                    shX + dir * sin (degrees angle) * armLen

                handY =
                    shoulderY + cos (degrees angle) * armLen

                mx =
                    (shX + handX) / 2

                my =
                    (shoulderY + handY) / 2

                -- push the control point perpendicular to the arm so the limb
                -- bows like a hose instead of hinging like a joint
                nx =
                    -(handY - shoulderY)

                ny =
                    handX - shX

                len =
                    max 0.001 (sqrt (nx * nx + ny * ny))
            in
            Canvas.path ( shX, shoulderY )
                [ Canvas.quadraticCurveTo
                    ( mx + nx / len * bend * armLen * 0.3
                    , my + ny / len * bend * armLen * 0.3
                    )
                    ( handX, handY )
                ]

        hand dir angle =
            let
                shX =
                    dir * girth * 0.45
            in
            Canvas.circle
                ( shX + dir * sin (degrees angle) * armLen
                , shoulderY + cos (degrees angle) * armLen
                )
                (limb * 0.72)

        hose =
            [ stroke def.body, lineWidth limb, lineCap RoundCap, lineJoin RoundJoin ]
    in
    [ Canvas.shapes hose [ leg -1, leg 1 ]
    , Canvas.shapes hose [ arm -1 pose.armL pose.bendL, arm 1 pose.armR pose.bendR ]
    , Canvas.shapes [ fill def.body ]
        [ Canvas.circle ( 0, hipY ) (girth * 0.5)
        , Canvas.circle ( 0, shoulderY ) (girth * 0.44)
        , Canvas.rect ( -girth * 0.5, shoulderY ) girth (hipY - shoulderY)
        ]
    , Canvas.shapes [ fill def.body ] [ hand -1 pose.armL, hand 1 pose.armR ]
    , topper l def h
    ]


topper : Layout -> CharDef -> Float -> Renderable
topper _ def h =
    let
        headR =
            h * 0.19

        headY =
            -h * 0.85
    in
    case def.topper of
        "antenna" ->
            Canvas.group []
                [ Canvas.shapes [ stroke def.trim, lineWidth (h * 0.018), lineCap RoundCap ]
                    [ Canvas.path ( 0, headY - headR * 0.9 )
                        [ Canvas.quadraticCurveTo ( h * 0.05, headY - headR * 1.7 ) ( h * 0.02, headY - headR * 2.1 ) ]
                    ]
                , Canvas.shapes [ fill def.trim ]
                    [ Canvas.circle ( h * 0.02, headY - headR * 2.1 ) (h * 0.026) ]
                ]

        "tuft" ->
            Canvas.shapes [ stroke def.trim, lineWidth (h * 0.022), lineCap RoundCap ]
                [ Canvas.path ( -headR * 0.3, headY - headR * 0.85 )
                    [ Canvas.quadraticCurveTo ( -headR * 0.1, headY - headR * 1.6 ) ( headR * 0.35, headY - headR * 1.25 ) ]
                ]

        -- two restless scribbles, one either side of the head
        "wings" ->
            let
                wing dir =
                    Canvas.path ( dir * headR * 0.85, headY - headR * 0.1 )
                        [ Canvas.quadraticCurveTo
                            ( dir * headR * 2.1, headY - headR * 1.0 )
                            ( dir * headR * 1.5, headY - headR * 0.55 )
                        , Canvas.quadraticCurveTo
                            ( dir * headR * 2.2, headY - headR * 0.2 )
                            ( dir * headR * 1.3, headY + headR * 0.05 )
                        ]
            in
            Canvas.shapes [ stroke def.trim, lineWidth (h * 0.016), lineCap RoundCap ]
                [ wing -1, wing 1 ]

        -- sits behind the head and larger than it, so the silhouette reads as
        -- a cowl framing a face rather than as a hat sitting on one
        "hood" ->
            Canvas.shapes [ fill (Color.rgb255 44 52 56) ]
                [ Canvas.path ( -headR * 1.15, headY + headR * 0.5 )
                    [ Canvas.quadraticCurveTo ( -headR * 1.3, headY - headR * 1.6 ) ( 0, headY - headR * 1.45 )
                    , Canvas.quadraticCurveTo ( headR * 1.3, headY - headR * 1.6 ) ( headR * 1.15, headY + headR * 0.5 )
                    , Canvas.quadraticCurveTo ( 0, headY + headR * 0.1 ) ( -headR * 1.15, headY + headR * 0.5 )
                    ]
                ]

        _ ->
            Canvas.shapes [] []



-- FACES


type alias Face =
    { eyeOpen : Float
    , eyeR : Float
    , pupilX : Float
    , pupilY : Float
    , brow : Float
    , browY : Float
    , curve : Float -- + smile, - frown
    , mouthW : Float
    , open : Float
    }


faceOf : String -> Face
faceOf expr =
    case expr of
        "happy" ->
            { eyeOpen = 0.55, eyeR = 1, pupilX = 0, pupilY = 0, brow = -6, browY = 0.1, curve = 0.9, mouthW = 1.2, open = 0.2 }

        "sad" ->
            { eyeOpen = 0.8, eyeR = 1, pupilX = 0, pupilY = 0.2, brow = 16, browY = 0.22, curve = -0.8, mouthW = 0.9, open = 0 }

        "angry" ->
            { eyeOpen = 0.75, eyeR = 0.9, pupilX = 0, pupilY = 0, brow = -26, browY = 0.05, curve = -0.6, mouthW = 1, open = 0.1 }

        "shocked" ->
            { eyeOpen = 1.35, eyeR = 1.25, pupilX = 0, pupilY = 0, brow = 6, browY = 0.34, curve = 0, mouthW = 0.7, open = 1 }

        "smug" ->
            { eyeOpen = 0.4, eyeR = 1, pupilX = 0.25, pupilY = 0, brow = -10, browY = 0.16, curve = 0.5, mouthW = 0.8, open = 0 }

        "confused" ->
            { eyeOpen = 1.05, eyeR = 1, pupilX = 0.15, pupilY = -0.1, brow = 18, browY = 0.3, curve = -0.15, mouthW = 0.75, open = 0.15 }

        "tired" ->
            { eyeOpen = 0.3, eyeR = 1, pupilX = 0, pupilY = 0.1, brow = 8, browY = 0.12, curve = -0.2, mouthW = 0.9, open = 0 }

        -- looking anywhere else
        "bored" ->
            { eyeOpen = 0.45, eyeR = 1, pupilX = 0.35, pupilY = 0.2, brow = 4, browY = 0.14, curve = -0.1, mouthW = 0.85, open = 0 }

        -- the punctuation at the end of a chain: it lands on a face, not in a
        -- bubble
        "dawning" ->
            { eyeOpen = 1.3, eyeR = 1.15, pupilX = 0, pupilY = 0, brow = 14, browY = 0.36, curve = 0.2, mouthW = 0.65, open = 0.35 }

        "withering" ->
            { eyeOpen = 0.35, eyeR = 1, pupilX = 0.2, pupilY = 0, brow = -14, browY = 0.1, curve = -0.35, mouthW = 0.8, open = 0 }

        _ ->
            { eyeOpen = 1, eyeR = 1, pupilX = 0, pupilY = 0, brow = 0, browY = 0.18, curve = 0.15, mouthW = 1, open = 0 }


face : Layout -> CharDef -> Pose -> Float -> Float -> String -> String -> Float -> List Renderable
face _ def _ h _ expr id t =
    let
        f =
            faceOf expr

        headR =
            h * 0.19

        headY =
            -h * 0.85

        -- deterministic blink: same instant for every viewer
        blink =
            if fmod (t * 0.37 + Rng.float01 (id ++ "blink")) 1 > 0.965 then
                0.06

            else
                1

        eyeOpen =
            f.eyeOpen * blink

        eyeR =
            headR * 0.3 * f.eyeR

        eyeX =
            headR * 0.42

        eyeY =
            headY - headR * 0.12

        eye dir =
            Canvas.group
                [ transform [ translate (dir * eyeX) eyeY, scale 1 eyeOpen ] ]
                [ Canvas.shapes [ fill Color.white ] [ Canvas.circle ( 0, 0 ) eyeR ]
                , Canvas.shapes [ fill (Color.rgb255 30 26 34) ]
                    [ Canvas.circle ( f.pupilX * eyeR * dir, f.pupilY * eyeR ) (eyeR * 0.46) ]
                ]

        brow dir =
            Canvas.shapes
                [ stroke (Color.rgb255 30 26 34), lineWidth (headR * 0.11), lineCap RoundCap ]
                [ Canvas.path
                    ( dir * eyeX - eyeR * 0.8, eyeY - headR * f.browY - dir * tan (degrees f.brow) * eyeR * 0.8 )
                    [ Canvas.lineTo
                        ( dir * eyeX + eyeR * 0.8, eyeY - headR * f.browY + dir * tan (degrees f.brow) * eyeR * 0.8 )
                    ]
                ]

        mouthY =
            headY + headR * 0.42

        mouthW =
            headR * 0.5 * f.mouthW

        mouth =
            if f.open > 0.5 then
                Canvas.shapes [ fill (Color.rgb255 60 30 40) ]
                    [ Canvas.circle ( 0, mouthY ) (headR * 0.22) ]

            else
                Canvas.shapes
                    [ stroke (Color.rgb255 30 26 34), lineWidth (headR * 0.1), lineCap RoundCap ]
                    [ Canvas.path ( -mouthW, mouthY )
                        [ Canvas.quadraticCurveTo ( 0, mouthY + f.curve * headR * 0.45 ) ( mouthW, mouthY ) ]
                    ]
    in
    [ Canvas.shapes [ fill def.body ] [ Canvas.circle ( 0, headY ) headR ]
    , eye -1
    , eye 1
    , brow -1
    , brow 1
    , mouth
    ]



-- BUBBLES


{-| Balloon geometry comes straight from the script — the compiler measured the
text with real font metrics and shipped `lines`, `w` and `h` (§4.2). The
browser never calls measureText, so bubbles are identical everywhere.
-}
drawBubble : Layout -> State -> Bubble -> List Renderable
drawBubble l st b =
    if b.kind == "narration" then
        -- Hermes only, and it belongs to the frame rather than to him
        narration l b

    else if b.kind == "deduction" then
        -- Also frame-anchored, for two reasons. It is a different register of
        -- speech — the machine running, not a person talking. And a deduction
        -- almost always plays over an `insert`, where the speaker is not in
        -- shot at all.
        deduction l b

    else
        case Dict.get b.who st.actors of
            Nothing ->
                []

            Just a ->
                speech l b a


ink : Color
ink =
    Color.rgb255 26 22 30


{-| A hard rectangle at the top of the frame, no tail. It is the chronicle
speaking, not a person in the room.
-}
narration : Layout -> Bubble -> List Renderable
narration l b =
    let
        s =
            unit l / 720

        bw =
            min (l.boxW * 0.72) (b.w * s * 1.15)

        bh =
            b.h * s

        x =
            l.ox + (l.boxW - bw) / 2

        y =
            l.oy + l.boxH * 0.045

        lineH =
            26 * s
    in
    [ Canvas.shapes [ fill (Color.rgb255 244 240 230), alpha 0.95 ]
        [ Canvas.rect ( x, y ) bw bh ]
    , Canvas.shapes [ stroke ink, lineWidth (2.5 * s) ]
        [ Canvas.rect ( x, y ) bw bh ]
    ]
        ++ List.indexedMap
            (\i str ->
                Canvas.text
                    [ font { size = round (20 * s), family = "'Comic Sans MS', 'Chalkboard SE', cursive" }
                    , align Left
                    , baseLine Middle
                    , fill ink
                    ]
                    ( x + 14 * s, y + bh / 2 - (toFloat (List.length b.lines) - 1) * lineH / 2 + toFloat i * lineH )
                    str
            )
            (Fold.revealed b)


{-| A ruled box, low and left, in a different typeface. Not a balloon: this is
the chain of inference, and it reveals a whole link at a time (Fold.revealed).
-}
deduction : Layout -> Bubble -> List Renderable
deduction l b =
    let
        s =
            unit l / 720

        bw =
            b.w * s

        bh =
            b.h * s

        x =
            l.ox + l.boxW * 0.055

        y =
            l.oy + l.boxH * 0.97 - bh

        lineH =
            26 * s
    in
    [ Canvas.shapes [ fill (Color.rgb255 250 248 242), alpha 0.97 ]
        [ Canvas.rect ( x, y ) bw bh ]
    , Canvas.shapes [ stroke ink, lineWidth (1.2 * s) ]
        [ Canvas.rect ( x, y ) bw bh ]

    -- the left margin rule, as on a ledger
    , Canvas.shapes [ stroke (Color.rgb255 190 120 96), lineWidth (1.2 * s) ]
        [ Canvas.path ( x + 16 * s, y ) [ Canvas.lineTo ( x + 16 * s, y + bh ) ] ]
    ]
        ++ List.indexedMap
            (\i str ->
                Canvas.text
                    [ font { size = round (19 * s), family = "'Courier New', ui-monospace, monospace" }
                    , align Left
                    , baseLine Middle
                    , fill ink
                    ]
                    ( x + 26 * s, y + 22 * s + toFloat i * lineH )
                    str
            )
            (Fold.revealed b)


speech : Layout -> Bubble -> Fold.ActorState -> List Renderable
speech l b a =
    let
        u =
            unit l

        -- authored against a 720px-high reference stage
        s =
            u / 720

        bw =
            b.w * s

        bh =
            b.h * s

        ( fx, fy ) =
            toScreen l a.pos

        headTop =
            fy - (charDef b.who).height * u * 1.08

        cx =
            fx + a.facing * bw * 0.22

        cy =
            headTop - bh * 0.6

        shown =
            Fold.revealed b

        lineH =
            26 * s

        tail =
            Canvas.path ( cx - bw * 0.1, cy + bh * 0.4 )
                [ Canvas.lineTo ( cx + bw * 0.06, cy + bh * 0.42 )
                , Canvas.lineTo ( fx + a.facing * u * 0.02, headTop - u * 0.01 )
                , Canvas.lineTo ( cx - bw * 0.1, cy + bh * 0.4 )
                ]

        centred fam size col =
            List.indexedMap
                (\i str ->
                    Canvas.text
                        [ font { size = round (size * s), family = fam }
                        , align Center
                        , baseLine Middle
                        , fill col
                        ]
                        ( cx, cy - (toFloat (List.length b.lines) - 1) * lineH / 2 + toFloat i * lineH )
                        str
                )
                shown

        comic =
            "'Comic Sans MS', 'Chalkboard SE', 'Marker Felt', cursive"

        balloon shape lw col =
            [ Canvas.shapes [ fill Color.white ] [ tail, shape ]
            , Canvas.shapes [ stroke col, lineWidth (lw * s), lineJoin RoundJoin ] [ shape ]
            , Canvas.shapes [ stroke col, lineWidth (lw * s), lineJoin RoundJoin ] [ tail ]
            , Canvas.shapes [ fill Color.white ] [ tail ]
            ]
    in
    case b.kind of
        "shout" ->
            balloon (spiked ( cx, cy ) (bw / 2) (bh / 2) b.who) 4 ink
                ++ centred comic 26 ink

        "whisper" ->
            [ Canvas.shapes [ fill Color.white, alpha 0.82 ]
                [ ellipse ( cx, cy ) (bw / 2) (bh / 2) ]
            , Canvas.shapes [ stroke (Color.rgb255 150 146 158), lineWidth (1.4 * s) ]
                [ ellipse ( cx, cy ) (bw / 2) (bh / 2) ]
            ]
                ++ centred comic 18 (Color.rgb255 90 86 98)

        "thought" ->
            let
                lobes =
                    List.range 0 8
                        |> List.map
                            (\i ->
                                let
                                    ang =
                                        2 * pi * toFloat i / 9
                                in
                                Canvas.circle
                                    ( cx + cos ang * bw * 0.47, cy + sin ang * bh * 0.47 )
                                    (bh * 0.2)
                            )

                trail =
                    [ Canvas.circle ( cx - bw * 0.18, cy + bh * 0.72 ) (bh * 0.1)
                    , Canvas.circle ( cx - bw * 0.28, cy + bh * 0.98 ) (bh * 0.06)
                    ]
            in
            [ Canvas.shapes [ fill Color.white ] (ellipse ( cx, cy ) (bw / 2) (bh / 2) :: lobes ++ trail)
            , Canvas.shapes [ stroke (Color.rgb255 120 116 130), lineWidth (2 * s) ] (lobes ++ trail)
            ]
                ++ centred comic 22 ink

        _ ->
            balloon (ellipse ( cx, cy ) (bw / 2) (bh / 2)) 3 ink
                ++ centred comic 22 ink


{-| A shout balloon: the same ellipse, spiked. Alternating radii, jittered
deterministically so no two shouts are quite the same shape.
-}
spiked : ( Float, Float ) -> Float -> Float -> String -> Shape
spiked ( cx, cy ) rx ry seed =
    let
        n =
            20

        pt i =
            let
                ang =
                    2 * pi * toFloat i / toFloat n

                k =
                    if modBy 2 i == 0 then
                        1.0

                    else
                        1.22 + Rng.float01 (seed ++ String.fromInt i) * 0.14
            in
            ( cx + cos ang * rx * k, cy + sin ang * ry * k )
    in
    Canvas.path (pt 0) (List.map (pt >> Canvas.lineTo) (List.range 1 n))


{-| Four beziers. `Canvas.circle` inside a scaled group would work too, but the
stroke would scale with it and go oval.
-}
ellipse : ( Float, Float ) -> Float -> Float -> Shape
ellipse ( cx, cy ) rx ry =
    let
        k =
            0.5522847
    in
    Canvas.path ( cx, cy - ry )
        [ Canvas.bezierCurveTo ( cx + rx * k, cy - ry ) ( cx + rx, cy - ry * k ) ( cx + rx, cy )
        , Canvas.bezierCurveTo ( cx + rx, cy + ry * k ) ( cx + rx * k, cy + ry ) ( cx, cy + ry )
        , Canvas.bezierCurveTo ( cx - rx * k, cy + ry ) ( cx - rx, cy + ry * k ) ( cx - rx, cy )
        , Canvas.bezierCurveTo ( cx - rx, cy - ry * k ) ( cx - rx * k, cy - ry ) ( cx, cy - ry )
        ]



-- MATH


stageRect : Layout -> ( Float, Float ) -> Float -> Float -> Shape
stageRect l ( x, y ) w h =
    let
        ( px, py ) =
            toScreen l ( x, y )

        ( qx, qy ) =
            toScreen l ( x + w, y + h )
    in
    Canvas.rect ( px, py ) (qx - px) (qy - py)


lerp : Float -> Float -> Float -> Float
lerp a b p =
    a + (b - a) * p


fmod : Float -> Float -> Float
fmod a b =
    a - b * toFloat (floor (a / b))
