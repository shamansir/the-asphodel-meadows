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


{-| Display options that are the viewer's choice rather than the script's.
-}
type alias Opts =
    { stepped : Bool
    , plates : Bool
    }


scene : Layout -> String -> State -> Float -> Opts -> List Renderable
scene l loc st t opts =
    let
        ts =
            if opts.stepped then
                toFloat (floor (t * 12)) / 12

            else
                t

        actors =
            Dict.toList st.actors
                -- painter's algorithm: whoever is further down the stage is nearer
                |> List.sortBy (\( _, a ) -> Tuple.second a.pos)

        -- An `insert` is a hard cut to the clue and nothing else. Plates would
        -- be enormous, and they belong to people who are not in the shot.
        plates =
            if opts.plates && st.shot /= "insert" then
                drawPlates l actors

            else
                []
    in
    List.concat
        [ background l loc st.shot ts
        , List.concatMap (\( id, a ) -> drawActor l id a ts) actors
        , plates
        , List.concatMap (drawBubble l st) st.bubbles

        -- ink goes over everything except the letterbox
        , List.concatMap (drawMark l loc) st.marks
        , letterbox l
        ]



-- NAME PLATES


{-| A filing card under each character's feet.

Not only a debug aid. `bible/craft.md` §9 requires every scene to be legible
from its middle, because viewers arrive mid-sentence rather than at the start —
and "who are these people" is exactly what a late arrival lacks. A desk
nameplate is also the right object for a world whose horror is procedural.

Width is derived from character counts rather than measured, for the same
reason the compiler pre-wraps speech (§4.2): every viewer must get identical
geometry. These strings are engine-side constants, so a fixed per-character
advance is exact enough and stable across browsers.

-}
type alias PlateBox =
    { x : Float
    , y : Float
    , w : Float
    , h : Float
    , def : CharDef
    }


{-| Lay out every plate at once, then draw.

It has to be done for the whole cast together, because the only sane way to
handle two characters standing shoulder to shoulder is to push their plates
apart horizontally. Stacking them vertically was worse — near the bottom of the
frame there is no room below the feet, and the plates end up over faces.

-}
drawPlates : Layout -> List ( String, ActorState ) -> List Renderable
drawPlates l actors =
    let
        s =
            unit l / 720

        gap =
            8 * s

        placed =
            actors
                |> List.filterMap (plateBox l s)
                |> List.sortBy .x
                |> List.foldl
                    (\b acc ->
                        case acc of
                            prev :: _ ->
                                { b | x = max b.x (prev.x + prev.w + gap) } :: acc

                            [] ->
                                [ b ]
                    )
                    []

        -- the run may now hang off the right edge; slide the whole row back
        overflow =
            case placed of
                last :: _ ->
                    max 0 (last.x + last.w - (l.ox + l.boxW - 6 * s))

                [] ->
                    0
    in
    List.concatMap (\b -> plateShapes s { b | x = b.x - overflow }) placed


plateBox : Layout -> Float -> ( String, ActorState ) -> Maybe PlateBox
plateBox l s ( id, a ) =
    let
        def =
            charDef id

        ( fx, fy ) =
            toScreen l a.pos

        w =
            max (toFloat (String.length def.name) * 11 + 36)
                (toFloat (String.length def.sub) * 7.6 + 36)
                * s

        h =
            44 * s
    in
    -- cheap cull: skip anyone the camera has left behind
    if fx < l.ox - w || fx > l.ox + l.boxW + w then
        Nothing

    else
        Just
            { x = clamp (l.ox + 6 * s) (l.ox + l.boxW - w - 6 * s) (fx - w / 2)
            , y = min (fy + 14 * s) (l.oy + l.boxH - h - 6 * s)
            , w = w
            , h = h
            , def = def
            }


plateShapes : Float -> PlateBox -> List Renderable
plateShapes s b =
    [ Canvas.shapes [ fill (Color.rgb255 250 248 242), alpha 0.96 ]
        [ Canvas.rect ( b.x, b.y ) b.w b.h ]
    , Canvas.shapes [ stroke ink, lineWidth (1.4 * s) ]
        [ Canvas.rect ( b.x, b.y ) b.w b.h ]

    -- the file tab, in the character's own accent
    , Canvas.shapes [ fill b.def.trim ]
        [ Canvas.rect ( b.x, b.y ) (7 * s) b.h ]
    , Canvas.text
        [ font { size = round (17 * s), family = "'Comic Sans MS', 'Chalkboard SE', cursive" }
        , align Center
        , baseLine Middle
        , fill ink
        ]
        ( b.x + b.w / 2 + 3 * s, b.y + 15 * s )
        b.def.name
    , Canvas.text
        [ font { size = round (12 * s), family = "'Courier New', ui-monospace, monospace" }
        , align Center
        , baseLine Middle
        , fill (Color.rgb255 132 126 140)
        ]
        ( b.x + b.w / 2 + 3 * s, b.y + 31 * s )
        b.def.sub
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
    , hatch : Color
    }


palette : String -> Palette
palette loc =
    case loc of
        -- Charon's terminal: wet slate, one sour lamp
        "loc.bank" ->
            { sky = Color.rgb255 214 213 210
            , band1 = Color.rgb255 202 201 198
            , band2 = Color.rgb255 190 189 187
            , far = Color.rgb255 168 168 166
            , mid = Color.rgb255 150 150 148
            , ground = Color.rgb255 178 177 174
            , prop = Color.rgb255 92 92 94
            , propTrim = Color.rgb255 60 60 62
            , lamp = Color.rgb255 246 238 214
            , hatch = Color.rgb255 26 26 30
            }

        -- the filing halls: crimson order, too many verticals
        -- the filing halls take the most ink of anywhere: too many verticals,
        -- not enough light
        "loc.ledgers" ->
            { sky = Color.rgb255 198 196 196
            , band1 = Color.rgb255 186 184 184
            , band2 = Color.rgb255 174 172 172
            , far = Color.rgb255 148 146 148
            , mid = Color.rgb255 132 130 132
            , ground = Color.rgb255 162 160 160
            , prop = Color.rgb255 78 76 78
            , propTrim = Color.rgb255 48 46 48
            , lamp = Color.rgb255 244 234 216
            , hatch = Color.rgb255 22 22 26
            }

        -- Asphodel: pleasant, endless, and that is the problem with it
        -- Asphodel is the lightest place in the world and the emptiest
        _ ->
            { sky = Color.rgb255 234 234 231
            , band1 = Color.rgb255 226 226 223
            , band2 = Color.rgb255 218 218 215
            , far = Color.rgb255 198 199 196
            , mid = Color.rgb255 186 187 184
            , ground = Color.rgb255 208 209 205
            , prop = Color.rgb255 120 120 120
            , propTrim = Color.rgb255 88 88 88
            , lamp = Color.rgb255 250 248 242
            , hatch = Color.rgb255 40 40 44
            }


{-| One light for the whole world, from the upper right. Every hatch stroke in
every location runs along this axis — that is what stops the shading reading as
texture and makes it read as light.
-}
sunAngle : Float
sunAngle =
    degrees -58


{-| A single tapered brush stroke: wide at the shadow end, drawn to a point at
the end nearest the sun.

Canvas has no variable-width stroke, so this is a filled lens rather than a
stroked line — two quadratics bowed apart at the root, meeting at the tip. The
bow is what keeps it a brush rather than a ruler.

-}
hatchStroke : ( Float, Float ) -> Float -> Float -> Float -> Shape
hatchStroke ( x, y ) len w0 bow =
    let
        ( dx, dy ) =
            ( cos sunAngle, sin sunAngle )

        ( nx, ny ) =
            ( -dy, dx )

        ( mx, my ) =
            ( x + dx * len * 0.45 + nx * bow, y + dy * len * 0.45 + ny * bow )
    in
    Canvas.path ( x + nx * w0 * 0.5, y + ny * w0 * 0.5 )
        [ Canvas.quadraticCurveTo ( mx + nx * w0 * 0.3, my + ny * w0 * 0.3 )
            ( x + dx * len, y + dy * len )
        , Canvas.quadraticCurveTo ( mx - nx * w0 * 0.3, my - ny * w0 * 0.3 )
            ( x - nx * w0 * 0.5, y - ny * w0 * 0.5 )
        ]


{-| Scatter tapered strokes through a horizontal slice of the stage.

`shade` scales length and weight together, so a darker band gets longer heavier
strokes rather than merely more of them — which is how a pen actually darkens
an area.

Placement is hashed from the location name, so the hatching is identical for
every viewer and never crawls between frames.

-}
hatchBand : Layout -> Color -> String -> Float -> Float -> Int -> Int -> Float -> Renderable
hatchBand l col seed y0 y1 cols rows shade =
    let
        u =
            unit l

        -- A jittered lattice, not a random scatter. Pure randomness clumps and
        -- leaves bald patches; ruling has to cover evenly to read as shading
        -- rather than as debris. The jitter is what keeps it off a grid.
        one r c =
            let
                sd =
                    seed ++ String.fromInt r ++ "x" ++ String.fromInt c

                jx =
                    (Rng.float01 sd - 0.5) * 0.85

                jy =
                    (Rng.float01 (sd ++ "j") - 0.5) * 0.85
            in
            hatchStroke
                (toScreen l
                    ( ((toFloat c + 0.5 + jx) / toFloat cols) * 1.3 - 0.15
                    , y0 + ((toFloat r + 0.5 + jy) / toFloat rows) * (y1 - y0)
                    )
                )
                (u * (0.018 + Rng.float01 (sd ++ "l") * 0.022) * shade)
                (u * (0.002 + Rng.float01 (sd ++ "w") * 0.0035) * shade)
                (u * (Rng.float01 (sd ++ "b") - 0.5) * 0.02)
    in
    Canvas.shapes [ fill col, alpha 0.4 ]
        (List.range 0 (rows - 1)
            |> List.concatMap (\r -> List.map (one r) (List.range 0 (cols - 1)))
        )


background : Layout -> String -> String -> Float -> List Renderable
background l loc shot t =
    let
        p =
            palette loc

        hatch =
            hatchBand l p.hatch loc
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

              -- sky is lit, so it barely takes any ink at all
              , hatch 0.0 0.22 26 2 0.45
              , hatch 0.22 0.45 32 4 0.7
              ]
            , lamps l p loc t
            , [ hills l p.far 0.52 0.05 (Rng.float01 (loc ++ "far"))
              , hatch 0.45 0.6 38 4 0.9
              , hills l p.mid 0.63 0.07 (Rng.float01 (loc ++ "mid"))
              , hatch 0.6 0.74 42 5 1.05
              , Canvas.shapes [ fill p.ground ] [ stageRect l ( 0, 0.74 ) 1 0.3 ]

              -- the floor is furthest from the light and carries the most ink
              , hatch 0.74 1.04 48 8 1.2
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
    , name : String -- name plate, line 1
    , sub : String -- name plate, line 2: function, not title
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
            , limb = 0.043
            , topper = "none"
            , name = "SHERLOCK HOLMES"
            , sub = "CONSULTING DETECTIVE"
            }

        -- The noodliest rig. Even his idle has motion.
        "ch.hermes" ->
            { body = Color.rgb255 234 206 138
            , trim = Color.rgb255 186 150 74
            , height = 0.19
            , girth = 0.42
            , limb = 0.058
            , topper = "wings"
            , name = "HERMES"
            , sub = "MESSENGER · PSYCHOPOMP"
            }

        -- Tallest, and never straightened. Everything about him is damp.
        "ch.charon" ->
            { body = Color.rgb255 86 96 100
            , trim = Color.rgb255 178 156 66
            , height = 0.34
            , girth = 0.30
            , limb = 0.047
            , topper = "hood"
            , name = "CHARON"
            , sub = "FERRYMAN"
            }

        -- Tight where the others are loose: permanently braced.
        "ch.minos" ->
            { body = Color.rgb255 164 66 72
            , trim = Color.rgb255 104 36 44
            , height = 0.25
            , girth = 0.46
            , limb = 0.055
            , topper = "none"
            , name = "MINOS"
            , sub = "JUDGE OF THE DEAD"
            }

        "ch.persephone" ->
            { body = Color.rgb255 120 172 112
            , trim = Color.rgb255 206 172 76
            , height = 0.26
            , girth = 0.34
            , limb = 0.049
            , topper = "tuft"
            , name = "PERSEPHONE"
            , sub = "QUEEN · IN RESIDENCE"
            }

        _ ->
            { body = Color.rgb255 200 200 210
            , trim = Color.rgb255 140 140 150
            , height = 0.24
            , girth = 0.5
            , limb = 0.05
            , topper = "none"
            , name = "UNFILED"
            , sub = "NO RECORD"
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
            body l def pose h id t
                (if a.moving then
                    a.act

                 else
                    ""
                )
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


{-| Skeleton anchor points, as fractions of total height. Everything is derived
from these so proportions can be tuned in one place.

Head top lands at exactly -1.0h, so `def.height` means what it says.

-}
type alias Rig =
    { headY : Float
    , headR : Float
    , neckTop : Float
    , shoulderY : Float
    , hipY : Float
    , shoulderR : Float
    , hipR : Float
    , armLen : Float
    , limb : Float
    , outline : Float
    }


rigOf : CharDef -> Float -> Rig
rigOf def h =
    { headY = -h * 0.84
    , headR = h * 0.16
    , neckTop = -h * 0.71
    , shoulderY = -h * 0.58
    , hipY = -h * 0.34
    , shoulderR = h * def.girth * 0.42
    , hipR = h * def.girth * 0.46
    , armLen = h * 0.32
    , limb = h * def.limb
    , outline = h * 0.024
    }


{-| The boil: a hand-inked line never sits still. Resampled at 10fps so it
shimmers rather than vibrates, and seeded from the part rather than from a
runtime counter, so every viewer's wobble is identical.

Cuphead does this by hand across thousands of frames. We get it for one hash.

-}
boil : Float -> String -> Int -> Float -> Float
boil t seed i amp =
    (Rng.float01 (seed ++ String.fromInt i ++ String.fromInt (floor (t * 10))) - 0.5) * amp


{-| A limb as a travelling sine wave — the third of the three Adventure Time
limb modes, alongside the stiff arc and the hard right-angle bend.

Sampled as a polyline rather than a curve, because a sine needs more control
points than a quadratic has. `sin (u * pi)` tapers the amplitude to zero at
both ends, so the limb stays welded to the shoulder and the hand rather than
detaching and swimming away.

The mode matters more than the wobble: limbs are stiff almost all the time, and
the comedy is in the moment one of them goes rubber. Continuous wobble reads as
noise.

-}
wavePath : ( Float, Float ) -> ( Float, Float ) -> Float -> Float -> Float -> Shape
wavePath ( ax, ay ) ( bx, by ) amp freq phase =
    let
        n =
            14

        dx =
            bx - ax

        dy =
            by - ay

        len =
            max 0.001 (sqrt (dx * dx + dy * dy))

        pt i =
            let
                u =
                    toFloat i / toFloat n

                off =
                    sin (phase + u * freq) * amp * sin (u * pi)
            in
            ( ax + dx * u - dy / len * off
            , ay + dy * u + dx / len * off
            )
    in
    Canvas.path (pt 0) (List.map (pt >> Canvas.lineTo) (List.range 1 n))


body : Layout -> CharDef -> Pose -> Float -> String -> Float -> String -> List Renderable
body _ def pose h id t mode =
    let
        r =
            rigOf def h

        wob =
            h * 0.012

        bo i =
            boil t id i wob

        leg dir =
            let
                hipX =
                    dir * r.hipR * 0.5

                footX =
                    dir * (r.hipR * 0.5 + pose.spread * h * 0.11)

                ctrl =
                    ( hipX + dir * r.limb * 0.8 + bo 1, r.hipY + (0 - r.hipY) * 0.55 + bo 2 )
            in
            if mode == "noodle" then
                wavePath ( hipX, r.hipY ) ( footX, 0 ) (h * 0.05) 7.5 (t * 6 + dir * 1.7)

            else
                Canvas.path ( hipX, r.hipY ) [ Canvas.quadraticCurveTo ctrl ( footX, 0 ) ]

        footAt dir =
            ( dir * (r.hipR * 0.5 + pose.spread * h * 0.11), 0 )

        handAt dir angle =
            ( dir * r.shoulderR * 0.9 + dir * sin (degrees angle) * r.armLen
            , r.shoulderY + cos (degrees angle) * r.armLen
            )

        arm dir angle bend i =
            let
                shX =
                    dir * r.shoulderR * 0.9

                ( handX, handY ) =
                    handAt dir angle

                nx =
                    -(handY - r.shoulderY)

                ny =
                    handX - shX

                len =
                    max 0.001 (sqrt (nx * nx + ny * ny))
            in
            if mode == "noodle" then
                wavePath ( shX, r.shoulderY )
                    ( handX, handY )
                    (r.armLen * 0.34)
                    9.5
                    (t * 7 + toFloat i)

            else
                -- control point pushed perpendicular to the arm, so the limb
                -- bows like a hose instead of hinging like a joint
                Canvas.path ( shX, r.shoulderY )
                    [ Canvas.quadraticCurveTo
                        ( (shX + handX) / 2 + nx / len * bend * r.armLen * 0.32 + bo i
                        , (r.shoulderY + handY) / 2 + ny / len * bend * r.armLen * 0.32 + bo (i + 1)
                        )
                        ( handX, handY )
                    ]

        limbs =
            [ leg -1
            , leg 1
            , arm -1 pose.armL pose.bendL 10
            , arm 1 pose.armR pose.bendR 20
            ]

        torso =
            [ Canvas.circle ( 0, r.hipY ) r.hipR
            , Canvas.circle ( 0, r.shoulderY ) r.shoulderR
            , Canvas.rect ( -r.shoulderR, r.shoulderY ) (r.shoulderR * 2) (r.hipY - r.shoulderY)
            , Canvas.rect ( -h * 0.05, r.neckTop ) (h * 0.1) (r.shoulderY - r.neckTop)
            ]

        gloves =
            [ Canvas.circle (handAt -1 pose.armL) (r.limb * 0.85)
            , Canvas.circle (handAt 1 pose.armR) (r.limb * 0.85)
            ]

        shoe dir =
            let
                fxx =
                    Tuple.first (footAt dir)
            in
            -- toe leads forward, heel stays under the leg: without this the
            -- legs just stop, and the figure reads as an insect
            Canvas.path ( fxx - h * 0.028, 0 )
                [ Canvas.quadraticCurveTo ( fxx - h * 0.03, h * 0.05 ) ( fxx + h * 0.02, h * 0.048 )
                , Canvas.quadraticCurveTo ( fxx + h * 0.085, h * 0.046 ) ( fxx + h * 0.082, 0 )
                , Canvas.lineTo ( fxx - h * 0.028, 0 )
                ]

        stroked w c =
            [ stroke c, lineWidth w, lineCap RoundCap, lineJoin RoundJoin ]
    in
    -- Every part is drawn twice: a fat dark pass, then the fill inside it. The
    -- outline is what separates head from shoulders when both are the same
    -- colour — which is how Adventure Time gets away with it, and why Minos
    -- read as an egg before this existed.
    [ Canvas.shapes (stroked (r.limb + r.outline * 2) ink) limbs
    , Canvas.shapes (stroked r.limb def.body) limbs
    , Canvas.shapes [ stroke ink, lineWidth (r.outline * 2), lineJoin RoundJoin ] torso
    , Canvas.shapes [ fill def.body ] torso
    , Canvas.shapes [ stroke ink, lineWidth (r.outline * 2), lineJoin RoundJoin ]
        [ shoe -1, shoe 1 ]
    , Canvas.shapes [ fill ink ] [ shoe -1, shoe 1 ]
    , Canvas.shapes [ stroke ink, lineWidth (r.outline * 1.6) ] gloves
    , Canvas.shapes [ fill (Color.rgb255 248 246 240) ] gloves
    , topper def h
    ]


topper : CharDef -> Float -> Renderable
topper def h =
    let
        headR =
            h * 0.16

        headY =
            -h * 0.84
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

        r =
            rigOf def h

        headR =
            r.headR

        headY =
            r.headY

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
    [ Canvas.shapes [ stroke ink, lineWidth (r.outline * 2) ]
        [ Canvas.circle ( 0, headY ) headR ]
    , Canvas.shapes [ fill def.body ] [ Canvas.circle ( 0, headY ) headR ]
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
            fy - (charDef b.who).height * u * 1.0

        cx =
            fx + a.facing * bw * 0.22

        cy =
            headTop - bh * 0.6

        shown =
            Fold.revealed b

        lineH =
            26 * s

        -- The tail's throat sits well inside the balloon, so the two fill as a
        -- clean union. Two versions of it: closed for filling, open — no base
        -- edge — for stroking, because the base is the seam we never want to
        -- see.
        tailRoot1 =
            ( cx - bw * 0.24, cy + bh * 0.30 )

        tailRoot2 =
            ( cx + bw * 0.02, cy + bh * 0.36 )

        -- overshoot slightly into the head, so the spike lands on the speaker
        -- instead of stopping in mid-air near them
        tailTip =
            ( fx + a.facing * u * 0.03, headTop + u * 0.02 )

        tailFill =
            Canvas.path tailRoot1
                [ Canvas.lineTo tailRoot2, Canvas.lineTo tailTip, Canvas.lineTo tailRoot1 ]

        tailOutline =
            Canvas.path tailRoot1 [ Canvas.lineTo tailTip, Canvas.lineTo tailRoot2 ]

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

        -- Order is the whole trick. Fill the union first so there is no seam;
        -- stroke the balloon; then re-fill the tail to erase the balloon's
        -- outline where it crosses the throat; then stroke the tail's two free
        -- edges only. Nothing is ever drawn over the balloon body.
        balloon shape lw col =
            [ Canvas.shapes [ fill Color.white ] [ shape, tailFill ]
            , Canvas.shapes [ stroke col, lineWidth (lw * s), lineJoin RoundJoin ] [ shape ]
            , Canvas.shapes [ fill Color.white ] [ tailFill ]
            , Canvas.shapes
                [ stroke col, lineWidth (lw * s), lineJoin RoundJoin, lineCap RoundCap ]
                [ tailOutline ]
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
