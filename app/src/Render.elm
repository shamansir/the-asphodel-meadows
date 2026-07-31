module Render exposing (Layout, backgroundStatic, bgKey, cameraCss, layout, scene)

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
import Canvas.Settings exposing (Setting, fill, stroke)
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
        [ -- Wipe the frame. This used to happen for free: the background fill
          -- covered the whole canvas every frame. Once the background moved to
          -- its own layer nothing was painting over the previous frame, and
          -- the characters smeared across the stage.
          [ Canvas.clear ( 0, 0 ) l.w l.h ]

        -- The background lives on its own canvas underneath (see cameraCss).
        -- Only the lamps stay here, because they gutter.
        , if st.shot == "insert" then
            []

          else
            [ Canvas.group (cameraXf l) (lamps (identityLayout l) (palette loc) loc ts) ]
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
            { sky = Color.rgb255 208 213 220
            , band1 = Color.rgb255 197 202 209
            , band2 = Color.rgb255 186 190 196
            , far = Color.rgb255 163 168 175
            , mid = Color.rgb255 148 151 155
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
            { sky = Color.rgb255 193 196 203
            , band1 = Color.rgb255 181 184 191
            , band2 = Color.rgb255 170 172 178
            , far = Color.rgb255 144 147 154
            , mid = Color.rgb255 130 131 136
            , ground = Color.rgb255 162 160 160
            , prop = Color.rgb255 78 76 78
            , propTrim = Color.rgb255 48 46 48
            , lamp = Color.rgb255 244 234 216
            , hatch = Color.rgb255 22 22 26
            }

        -- Asphodel: pleasant, endless, and that is the problem with it
        -- Asphodel is the lightest place in the world and the emptiest
        _ ->
            { sky = Color.rgb255 229 232 236
            , band1 = Color.rgb255 222 225 229
            , band2 = Color.rgb255 214 217 222
            , far = Color.rgb255 194 198 203
            , mid = Color.rgb255 183 186 190
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


{-| A single hatch mark: a hard triangle, base across the light axis, apex
pointing toward the sun.

Straight edges and a real point, not the bowed lens this used to be — that read
as fingernails at density. Reference is sphere 3 of the standard shading chart:
bold wedges anchored on the dark rim, radiating toward the light.

-}
hatchStroke : ( Float, Float ) -> Float -> Float -> Shape
hatchStroke ( x, y ) len w0 =
    let
        ( dx, dy ) =
            ( cos sunAngle, sin sunAngle )

        ( nx, ny ) =
            ( -dy, dx )

        corner k =
            ( x + nx * w0 * k, y + ny * w0 * k )
    in
    Canvas.path (corner 0.5)
        [ Canvas.lineTo ( x + dx * len, y + dy * len )
        , Canvas.lineTo (corner -0.5)
        , Canvas.lineTo (corner 0.5)
        ]


{-| A hatchable area: a bounding box in stage coordinates plus a containment
test.

Every background shape we author is either a rectangle or "everything below a
curve", so containment is a couple of comparisons. That is what makes clipping
possible at all: `elm-canvas` exposes no `clip()`, and composite-op masking
would erase the background already painted, because composite modes apply to
the whole canvas rather than to a layer.

-}
type alias Region =
    { x0 : Float
    , x1 : Float
    , y0 : Float
    , y1 : Float
    , inside : ( Float, Float ) -> Bool

    -- where row `t` (0 at the lit edge, 1 at the far edge) sits at a given x.
    -- Flat for a rectangle; for a ridge it follows the skyline, so a row of
    -- marks curves with the surface it is shading.
    , rowY : Float -> Float -> Float
    }


rectRegion : Float -> Float -> Float -> Float -> Region
rectRegion x0 y0 x1 y1 =
    { x0 = x0
    , x1 = x1
    , y0 = y0
    , y1 = y1
    , inside = \( x, y ) -> x >= x0 && x <= x1 && y >= y0 && y <= y1
    , rowY = \_ t -> y0 + t * (y1 - y0)
    }


{-| The band between two skylines.

A ridge must stop where the ridge in front of it begins, not run on underneath.
Otherwise the whole dark half of its gradient is painted over by the nearer
hill, and only its palest rows are ever seen — which is exactly why the distant
hills looked *less* shaded than the near ones despite carrying more ink.

Bounding the region by the ridge in front means the full ramp fits in the strip
the viewer can actually see.

-}
bandRegion : (Float -> Float) -> (Float -> Float) -> Float -> Float -> Region
bandRegion topFn botFn yLo yHi =
    { x0 = -0.18
    , x1 = 1.2
    , y0 = yLo
    , y1 = yHi
    , inside = \( x, y ) -> y >= topFn x && y <= botFn x
    , rowY = \x t -> topFn x + t * (botFn x - topFn x)
    }


{-| Screen point back to stage coordinates: the inverse of `toScreen`, so a
stroke can be marched in screen space and tested in stage space.
-}
toStage : Layout -> ( Float, Float ) -> ( Float, Float )
toStage l ( px, py ) =
    ( (px - l.ox - l.boxW / 2) / (l.boxW * l.zoom) + l.camX
    , (py - l.oy - l.boxH / 2) / (l.boxH * l.zoom) + l.camY
    )


{-| Rule a region with triangular hatch marks, anchored to its edge and clipped
to its outline.

Three things happen per mark. Placement is a **jittered lattice** — pure
randomness clumps and leaves bald patches, and ruling has to cover evenly to
read as shading rather than debris. The base is then **snapped backwards onto
the shadow-side boundary** when one is within reach, which is what produces the
row of wedges standing on the rim in sphere 3 rather than marks floating near
it. Finally the length is **marched forward and cut at the far boundary**, so
nothing crosses an edge in either direction, drawn or not.

-}
hatchRegion : Layout -> Color -> Color -> String -> Region -> Int -> Int -> Float -> Float -> Float -> List Renderable
hatchRegion l surface col seed region cols rows shade ramp offset =
    let
        u =
            unit l

        step =
            u * 0.006

        ( dx, dy ) =
            ( cos sunAngle, sin sunAngle )

        at ( sx, sy ) d =
            ( sx + dx * d, sy + dy * d )

        -- march until the region ends, up to `want`
        run sign want from =
            let
                walk n =
                    let
                        travelled =
                            toFloat n * step
                    in
                    if travelled >= want then
                        want

                    else if region.inside (toStage l (at from (sign * travelled))) then
                        walk (n + 1)

                    else
                        travelled - step
            in
            max 0 (walk 1)

        -- Rows thin out toward the light: the bottom row carries twice the
        -- marks of a uniform lattice, the top row under half. Combined with
        -- the size curve this is what makes the descent read as a gradient
        -- rather than as a change of scale.
        -- `ramp` is how strongly this shape reads as receding: how much
        -- longer, thicker, denser and darker its shadowed rows get relative to
        -- its lit ones. Low for the flat sky bands, high for a ridge standing
        -- behind another.
        countAt t =
            max 1 (round (toFloat cols * (1 - 0.5 * ramp + 1.5 * ramp * t)))

        one r t n c =
            let
                sd =
                    seed ++ String.fromInt r ++ "x" ++ String.fromInt c

                x =
                    region.x0
                        + ((toFloat c + 0.5 + (Rng.float01 sd - 0.5) * 0.8) / toFloat n)
                        * (region.x1 - region.x0)

                stage =
                    ( x, region.rowY x t )

                -- Pushed away from the light — down and back — so a mark sits
                -- behind the surface in front of it. Escaping the region is
                -- the point: whatever draws next paints over the overhang,
                -- which is what "behind" looks like.
                --
                -- Per-region, because a distant band is shallow and the offset
                -- eats a visible fraction of its row spacing. Near surfaces
                -- take the full shift; the sky takes none.
                --
                -- Containment and length are still measured from the unshifted
                -- anchor, so the lattice stays inside the shape and only the
                -- drawing slides.
                base =
                    toScreen l ( x - offset, Tuple.second stage + offset )

                -- How thick the band is at this x. Where two ridges converge
                -- the band pinches to nothing, and every row lands within a
                -- few pixels — which piles into a black smear unless the marks
                -- shrink with the space available to them.
                localScale =
                    clamp 0 1 ((region.rowY x 1 - region.rowY x 0) / 0.13)

                -- Weight climbs with the square-ish of depth, not linearly.
                -- A straight ramp reads as one flat texture that happens to
                -- get bigger; the curve keeps the lit rows delicate and lets
                -- the shadowed ones go properly heavy.
                weight =
                    t ^ 1.9

                len =
                    run 1
                        (u * (0.006 + 0.052 * ramp * weight) * shade * localScale)
                        (toScreen l stage)
            in
            if not (region.inside stage) || len < u * 0.004 || localScale < 0.12 then
                Nothing

            else
                Just
                    (hatchStroke base
                        len
                        (u * (0.0010 + 0.0066 * ramp * weight) * shade * localScale)
                    )
    in
    -- One draw per row, so the ink can darken as it descends. Fully opaque:
    -- the row's colour is mixed from the surface toward the hatch ink, so a
    -- mark never lightens where another crosses it.
    List.range 0 (rows - 1)
        |> List.map
            (\r ->
                let
                    t =
                        (toFloat r + 0.5) / toFloat rows
                in
                Canvas.shapes
                    [ fill (mixColor surface col (min 0.95 (0.34 + 0.52 * ramp * (t ^ 1.9)))) ]
                    (List.filterMap (one r t (countAt t)) (List.range 0 (countAt t - 1)))
            )


{-| The camera as an affine transform, so cached geometry can be baked once at
an identity camera and merely moved each frame.

Deriving it: a point baked at `zoom = 1, cam = (0.5, 0.5)` lands at
`P0 = ox + boxW/2 + (sx - 0.5) * boxW`, and the same point under a real camera
lands at `P = ox + boxW/2 + (sx - camX) * boxW * zoom`. Eliminating `sx` gives
`P = zoom * P0 + t`, which is exactly a translate followed by a scale.

This is the whole reason the cache survives a camera move. Keying the cache on
the camera would invalidate it every frame of a pan — precisely when the
background is most expensive and least changed.

-}
cameraOffset : Layout -> ( Float, Float )
cameraOffset l =
    let
        anchor c len camN =
            c - l.zoom * c + l.zoom * len * 0.5 - l.zoom * len * camN
    in
    ( anchor (l.ox + l.boxW / 2) l.boxW l.camX
    , anchor (l.oy + l.boxH / 2) l.boxH l.camY
    )


cameraXf : Layout -> List Setting
cameraXf l =
    let
        ( tx, ty ) =
            cameraOffset l
    in
    [ transform [ translate tx ty, scale l.zoom l.zoom ] ]


{-| The same camera as a CSS transform, for the stacked background canvas.

`transform-origin: 0 0` plus `translate(...) scale(...)` composes right-to-left
as `p -> t + s * p`, which is exactly what `cameraXf` does on the context. So
the background can be rasterised once and then moved by the compositor instead
of being re-issued to the canvas sixty times a second.

-}
cameraCss : Layout -> String
cameraCss l =
    let
        ( tx, ty ) =
            cameraOffset l

        px v =
            String.fromFloat v ++ "px"
    in
    "translate(" ++ px tx ++ "," ++ px ty ++ ") scale(" ++ String.fromFloat l.zoom ++ ")"


identityLayout : Layout -> Layout
identityLayout l =
    { l | camX = 0.5, camY = 0.5, zoom = 1 }


{-| What the cached background depends on. Deliberately excludes the camera.
-}
bgKey : Layout -> String -> String -> Bool -> String
bgKey l loc shot hatched =
    String.join "|"
        [ loc
        , shot
        , String.fromInt (round l.boxW)
        , String.fromInt (round l.boxH)
        , if hatched then
            "h"

          else
            "flat"
        ]


{-| Everything in the background that does not move: bands, ridges, hatching,
set dressing. Built at an identity camera and cached by `bgKey`; the lamps are
the only live part and are drawn separately because they gutter.
-}
backgroundStatic : Layout -> String -> String -> Bool -> List Renderable
backgroundStatic l0 loc shot hatched =
    background (identityLayout l0) loc shot hatched


background : Layout -> String -> String -> Bool -> List Renderable
background l loc shot hatched =
    let
        p =
            palette loc

        hatch surface region cols rows shade ramp offset =
            if hatched then
                hatchRegion l surface p.hatch loc region cols rows shade ramp offset

            else
                []

        farRidge =
            hillY farSeed 0.52 0.05

        midRidge =
            hillY midSeed 0.63 0.07

        farSeed =
            loc ++ "far"

        midSeed =
            loc ++ "mid"
    in
    if shot == "insert" then
        -- a hard cut to the clue, filling frame, on a flat ground. The clue is
        -- the only thing in the world for a moment.
        [ Canvas.shapes [ fill p.band2 ] [ Canvas.rect ( l.ox, l.oy ) l.boxW l.boxH ] ]

    else
        -- Each shape is hatched immediately after it is filled, inside its own
        -- region. Strokes are clipped to the shape, and anything that strays
        -- over a boundary is painted out by the next shape anyway.
        --
        -- Depth reads through weight: the far ridge is dense and dark, the
        -- floor nearest the viewer is sparse and diffuse.
        List.concat
            [ [ Canvas.shapes [ fill p.sky ] [ Canvas.rect ( l.ox, l.oy ) l.boxW l.boxH ] ]

            -- Sky bands: low ramp. They are flat air, not receding surfaces,
            -- and they already read correctly.
            , hatch p.sky (rectRegion -0.18 -0.05 1.2 0.22) 112 7 0.4 0.55 0
            , [ moon l p loc
              , Canvas.shapes [ fill p.band1 ] [ stageRect l ( 0, 0.2 ) 1 0.25 ]
              ]
            , hatch p.band1 (rectRegion -0.18 0.2 1.2 0.45) 132 11 0.6 0.6 0.004
            , [ Canvas.shapes [ fill p.band2 ] [ stageRect l ( 0, 0.4 ) 1 0.25 ] ]
            , hatch p.band2 (rectRegion -0.18 0.4 1.2 0.65) 146 11 0.8 0.7 0.008

            -- The far ridge is bounded by the near one and ramps hardest: its
            -- visible strip is thin, so the whole gradient has to happen there.
            , [ hills l p.far 0.52 0.05 farSeed ]
            , hatch p.far (bandRegion farRidge midRidge 0.46 0.72) 158 9 0.8 1.35 0.014
            -- Between the two ridges: the far hill is behind them, the near
            -- hill covers their feet.
            , colonnade l p loc midRidge
            , [ hills l p.mid 0.63 0.07 midSeed ]
            , hatch p.mid (bandRegion midRidge (always 0.742) 0.55 0.75) 144 10 0.66 1.0 0.014
            , [ Canvas.shapes [ fill p.ground ] [ stageRect l ( 0, 0.74 ) 1 0.3 ]
              , Canvas.shapes [ stroke ink, lineWidth (unit l * 0.0035), alpha 0.45 ]
                    [ Canvas.path (toScreen l ( -0.05, 0.74 ))
                        [ Canvas.lineTo (toScreen l ( 1.05, 0.74 )) ]
                    ]
              ]
            , hatch p.ground (rectRegion -0.18 0.74 1.2 1.02) 125 16 0.8 1.05 0.016
            , props l p loc
            ]


{-| There is a moon over the House. Nothing in the myth says there is not, and
the hatching needs a light source the viewer can actually point at.
-}
moon : Layout -> Palette -> String -> Renderable
moon l p loc =
    let
        u =
            unit l

        ( mx, my ) =
            toScreen l ( 0.80, 0.19 )

        r =
            u * 0.055
    in
    Canvas.group []
        [ Canvas.shapes [ fill p.lamp ] [ Canvas.circle ( mx, my ) r ]
        , Canvas.shapes [ stroke ink, lineWidth (u * 0.003), alpha 0.4 ]
            [ Canvas.circle ( mx, my ) r ]

        -- one crater, so it is a moon rather than a hole in the sky
        , Canvas.shapes [ fill p.far, alpha 0.18 ]
            [ Canvas.circle ( mx - r * 0.3, my - r * 0.25 ) (r * 0.26)
            , Canvas.circle ( mx + r * 0.35, my + r * 0.2 ) (r * 0.17)
            ]
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
                    unit l * 0.012 * flicker
            in
            Canvas.shapes [ fill p.lamp, alpha 0.6 ]
                [ Canvas.circle ( x, y ) r ]
    in
    List.map one (List.range 0 3)


{-| The skyline of a ridge, as a plain function of x.

It has to be analytic, not a hashed control polygon, because the hatcher needs
to ask "is this point inside the hill" thousands of times a frame. Two summed
sines with hashed phases give a smooth ridge that is cheap to evaluate anywhere
— and, incidentally, fixes the stepped slabs the old control-point version drew.

-}
hillY : String -> Float -> Float -> Float -> Float
hillY seed baseY amp =
    let
        -- hashed ONCE per ridge, not once per sample. The hatcher asks
        -- "is this inside the hill" tens of thousands of times per rebuild,
        -- and hashing a string in that loop was costing seconds.
        p1 =
            Rng.phase seed

        p2 =
            Rng.phase (seed ++ "b")
    in
    \x ->
        baseY - amp * (0.45 + 0.32 * sin (x * 6.1 + p1) + 0.23 * sin (x * 11.7 + p2))


hills : Layout -> Color -> Float -> Float -> String -> Renderable
hills l color baseY amp seed =
    let
        n =
            48

        ridge =
            hillY seed baseY amp

        pt i =
            let
                x =
                    -0.2 + (toFloat i / toFloat n) * 1.42
            in
            toScreen l ( x, ridge x )
    in
    Canvas.group []
        [ Canvas.shapes [ fill color ]
            [ Canvas.path (toScreen l ( -0.2, 1.1 ))
                (List.map (pt >> Canvas.lineTo) (List.range 0 n)
                    ++ [ Canvas.lineTo (toScreen l ( 1.22, 1.1 )) ]
                )
            ]

        -- Only the skyline is stroked, not the whole silhouette: the sides and
        -- base run off frame, and outlining those would draw a box around the
        -- landscape.
        , Canvas.shapes [ stroke ink, lineWidth (unit l * 0.0035), alpha 0.5 ]
            [ Canvas.path (pt 0) (List.map (pt >> Canvas.lineTo) (List.range 1 n)) ]
        ]


{-| Set dressing. All of it is hashed from the location name, so it is in the
same spot for everyone forever without being listed in the script — and all of
it lives on the cached layer, so detail is close to free.

Each location gets its own furniture rather than the one generic prop they used
to share.

-}
props : Layout -> Palette -> String -> List Renderable
props l p loc =
    let
        u =
            unit l

        pick i lo hi seed =
            lo + Rng.float01 (loc ++ seed ++ String.fromInt i) * (hi - lo)
    in
    List.concat
        [ flagstones l p
        , case loc of
            "loc.bank" ->
                mooring l p loc

            "loc.ledgers" ->
                shelving l p loc

            _ ->
                List.range 0 13
                    |> List.concatMap
                        (\i ->
                            let
                                ( px, py ) =
                                    toScreen l ( pick i -0.05 1.05 "st", pick i 0.76 0.99 "sty" )

                                sz =
                                    u * pick i 0.02 0.05 "stz"
                            in
                            -- asphodel: pale stalks, and nothing else, forever
                            [ Canvas.shapes [ stroke p.prop, lineWidth (u * 0.0035), lineCap RoundCap ]
                                [ Canvas.path ( px, py )
                                    [ Canvas.quadraticCurveTo ( px + sz * 0.3, py - sz ) ( px, py - sz * 1.8 ) ]
                                ]
                            , Canvas.shapes [ fill p.propTrim ]
                                [ Canvas.circle ( px, py - sz * 1.9 ) (u * 0.006) ]
                            ]
                        )
        , [ frameEdge l p ]
        ]


{-| A receding row of columns, standing on the near ridge.

Each column's foot follows the skyline it stands on, so the row rises and falls
with the ground instead of sitting on an invisible flat shelf. The feet are set
slightly *below* that line and the colonnade is drawn before the ridge itself,
so the hill buries them — which is what puts the row behind the near hill and
in front of the far one.

-}
colonnade : Layout -> Palette -> String -> (Float -> Float) -> List Renderable
colonnade l p loc ridge =
    if loc == "loc.asphodel" then
        []

    else
        let
            u =
                unit l

            col i =
                let
                    x =
                        -0.06 + toFloat i * 0.072

                    ( px, py ) =
                        toScreen l ( x, ridge x + 0.03 )

                    hgt =
                        u * (0.14 + Rng.float01 (loc ++ "col" ++ String.fromInt i) * 0.05)

                    wid =
                        u * 0.018
                in
                [ Canvas.rect ( px - wid, py - hgt ) (wid * 2) hgt
                , Canvas.rect ( px - wid * 1.5, py - hgt - u * 0.012 ) (wid * 3) (u * 0.012)
                ]
        in
        [ Canvas.shapes [ fill p.far ]
            (List.concatMap col (List.range 0 16))
        , Canvas.shapes [ stroke ink, lineWidth (u * 0.0025), alpha 0.35 ]
            (List.concatMap col (List.range 0 16))
        ]


{-| Perspective lines on the floor. Cheap depth, and it gives the hatching
something to sit against.
-}
flagstones : Layout -> Palette -> List Renderable
flagstones l p =
    let
        u =
            unit l

        horizonY =
            0.74

        row i =
            let
                k =
                    toFloat i / 7

                y =
                    horizonY + (1.06 - horizonY) * (k * k)
            in
            Canvas.path (toScreen l ( -0.05, y )) [ Canvas.lineTo (toScreen l ( 1.05, y )) ]

        seam i =
            let
                x =
                    -0.4 + toFloat i * 0.2
            in
            Canvas.path (toScreen l ( 0.5 + (x - 0.5) * 0.35, horizonY ))
                [ Canvas.lineTo (toScreen l ( x, 1.06 )) ]
    in
    [ Canvas.shapes [ stroke p.prop, lineWidth (u * 0.0022), alpha 0.35 ]
        (List.map row (List.range 1 7) ++ List.map seam (List.range 0 9))
    ]


{-| Charon's terminal: mooring posts, a rope line, and the fare box.
-}
mooring : Layout -> Palette -> String -> List Renderable
mooring l p loc =
    let
        u =
            unit l

        post i =
            let
                x =
                    0.04 + toFloat i * 0.23

                ( px, py ) =
                    toScreen l ( x, 0.79 + Rng.float01 (loc ++ "po" ++ String.fromInt i) * 0.03 )

                hgt =
                    u * 0.1
            in
            [ Canvas.rect ( px - u * 0.011, py - hgt ) (u * 0.022) hgt
            , Canvas.circle ( px, py - hgt ) (u * 0.016)
            ]

        rope =
            List.range 0 3
                |> List.map
                    (\i ->
                        let
                            a =
                                toScreen l ( 0.04 + toFloat i * 0.23, 0.79 - 0.1 )

                            b =
                                toScreen l ( 0.04 + toFloat (i + 1) * 0.23, 0.79 - 0.1 )
                        in
                        Canvas.path a
                            [ Canvas.quadraticCurveTo
                                ( (Tuple.first a + Tuple.first b) / 2, Tuple.second a + u * 0.035 )
                                b
                            ]
                    )
    in
    [ Canvas.shapes [ fill p.prop ] (List.concatMap post (List.range 0 4))
    , Canvas.shapes [ stroke p.prop, lineWidth (u * 0.004), lineCap RoundCap ] rope
    ]


{-| The filing halls: stacks receding, and a ladder nobody has moved in an age.
-}
shelving : Layout -> Palette -> String -> List Renderable
shelving l p loc =
    let
        u =
            unit l

        stack i =
            let
                x =
                    0.02 + toFloat i * 0.14

                ( px, py ) =
                    toScreen l ( x, 0.8 )

                w =
                    u * 0.075

                shelf j =
                    Canvas.rect
                        ( px - w / 2 + u * 0.004 * Rng.float01 (loc ++ String.fromInt i ++ String.fromInt j)
                        , py - u * 0.036 * toFloat (j + 1)
                        )
                        w
                        (u * 0.028)
            in
            List.map shelf (List.range 0 (2 + modBy 4 i))

        ladder =
            let
                ( lx, ly ) =
                    toScreen l ( 0.62, 0.8 )

                hgt =
                    u * 0.19
            in
            [ Canvas.path ( lx, ly ) [ Canvas.lineTo ( lx + u * 0.03, ly - hgt ) ]
            , Canvas.path ( lx + u * 0.05, ly ) [ Canvas.lineTo ( lx + u * 0.07, ly - hgt ) ]
            ]
                ++ (List.range 1 5
                        |> List.map
                            (\j ->
                                let
                                    k =
                                        toFloat j / 6
                                in
                                Canvas.path ( lx + u * 0.03 * k + u * 0.001, ly - hgt * k )
                                    [ Canvas.lineTo ( lx + u * 0.05 + u * 0.02 * k, ly - hgt * k ) ]
                            )
                   )
    in
    [ Canvas.shapes [ fill p.prop ] (List.concatMap stack (List.range 0 6))
    , Canvas.shapes [ stroke p.prop, lineWidth (u * 0.005), lineCap RoundCap ] ladder
    ]


{-| A dark mass at the frame edge, out of the action. Costs one rectangle and
buys the whole shot a foreground plane.
-}
frameEdge : Layout -> Palette -> Renderable
frameEdge l p =
    let
        u =
            unit l

        ( px, py ) =
            toScreen l ( -0.02, 0 )
    in
    Canvas.shapes [ fill p.prop, alpha 0.55 ]
        [ Canvas.rect ( px - u * 0.1, py - u * 0.2 ) (u * 0.12) (u * 1.6) ]


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


{-| Limbs draw out to ~1.8x before a wobble and settle back after it.
-}
reachOf : ActorState -> Float
reachOf a =
    if a.moving && a.act == "noodle" then
        1 + 0.8 * stretchEnv a.actP

    else
        1


{-| Legs that extend must push the body up, not the feet down: the character
stays planted and gets taller. Drawn by moving the ground line down in local
space and lifting the whole group by the same amount, so the two cancel exactly
at the sole.

Bubbles need this too — anchoring them to the resting head height means a
character who stretches grows straight up into their own dialogue.

-}
liftOf : CharDef -> Float -> ActorState -> Float
liftOf def h a =
    -(rigOf def h).hipY * (reachOf a - 1)


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

        mode =
            if a.moving then
                a.act

            else
                ""

        reach =
            reachOf a

        lift =
            liftOf def h a

        -- halo underneath the whole figure, then the figure itself
        parts =
            body l def pose h id t mode reach lift "halo"
                ++ face l def pose h a.facing a.expr id t "halo"
                ++ body l def pose h id t mode reach lift "art"
                ++ face l def pose h a.facing a.expr id t "art"
    in
    [ Canvas.group
        [ transform
            [ translate fx (fy - bob - lift)
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


{-| Stretch envelope for a noodle: limbs draw out over the first fifth of the
act, hold long, then snap back over the last fifth. 0 at both ends, 1 through
the middle.

Rubber hose stretches *into* the wobble and settles *out* of it. Waving at a
constant length reads as a flag; extending first reads as a limb made of hose.

-}
stretchEnv : Float -> Float
stretchEnv p =
    let
        ramp x =
            let
                c =
                    clamp 0 1 x
            in
            c * c * (3 - 2 * c)
    in
    min (ramp (p / 0.18)) (ramp ((1 - p) / 0.18))


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


body : Layout -> CharDef -> Pose -> Float -> String -> Float -> String -> Float -> Float -> String -> List Renderable
body _ def pose h id t mode reach footY layer =
    let
        r =
            rigOf def h

        -- how far arms and legs are drawn out beyond their resting length
        armLen =
            r.armLen * reach

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
                    ( hipX + dir * r.limb * 0.8 + bo 1, r.hipY + (footY - r.hipY) * 0.55 + bo 2 )
            in
            if mode == "noodle" then
                wavePath ( hipX, r.hipY ) ( footX, footY ) (h * 0.05 * reach) 7.5 (t * 6 + dir * 1.7)

            else
                Canvas.path ( hipX, r.hipY ) [ Canvas.quadraticCurveTo ctrl ( footX, footY ) ]

        footAt dir =
            ( dir * (r.hipR * 0.5 + pose.spread * h * 0.11), footY )

        handAt dir angle =
            ( dir * r.shoulderR * 0.9 + dir * sin (degrees angle) * armLen
            , r.shoulderY + cos (degrees angle) * armLen
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
                    (armLen * 0.34)
                    9.5
                    (t * 7 + toFloat i)

            else
                -- control point pushed perpendicular to the arm, so the limb
                -- bows like a hose instead of hinging like a joint
                Canvas.path ( shX, r.shoulderY )
                    [ Canvas.quadraticCurveTo
                        ( (shX + handX) / 2 + nx / len * bend * armLen * 0.32 + bo i
                        , (r.shoulderY + handY) / 2 + ny / len * bend * armLen * 0.32 + bo (i + 1)
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
            Canvas.path ( fxx - h * 0.028, footY )
                [ Canvas.quadraticCurveTo ( fxx - h * 0.03, footY + h * 0.05 )
                    ( fxx + h * 0.02, footY + h * 0.048 )
                , Canvas.quadraticCurveTo ( fxx + h * 0.085, footY + h * 0.046 )
                    ( fxx + h * 0.082, footY )
                , Canvas.lineTo ( fxx - h * 0.028, footY )
                ]

        stroked w c =
            [ stroke c, lineWidth w, lineCap RoundCap, lineJoin RoundJoin ]

        halo =
            r.outline * 3.2
    in
    if layer == "halo" then
        -- Comic Chat never shades its characters; it lifts them off the
        -- hatching with a thick white keyline instead. Drawn as a pass under
        -- the whole figure so limbs, torso and head share one silhouette
        -- rather than each getting its own outline.
        [ Canvas.shapes (stroked (r.limb + halo * 2) paper) limbs
        , Canvas.shapes (stroked (halo * 2) paper) (torso ++ gloves ++ [ shoe -1, shoe 1 ])
        ]

    else
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


face : Layout -> CharDef -> Pose -> Float -> Float -> String -> String -> Float -> String -> List Renderable
face _ def _ h _ expr id t layer =
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
    if layer == "halo" then
        [ Canvas.shapes [ stroke paper, lineWidth (r.outline * 6.4), lineJoin RoundJoin ]
            [ Canvas.circle ( 0, headY ) headR ]
        ]

    else
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


{-| Blend two colours. Used so hatch rows can darken by changing paint rather
than by stacking transparency — overlapping translucent marks compound, so an
alpha ramp makes density and darkness impossible to control separately.
-}
mixColor : Color -> Color -> Float -> Color
mixColor a b k =
    let
        ca =
            Color.toRgba a

        cb =
            Color.toRgba b

        at v w =
            v + (w - v) * k
    in
    Color.rgb (at ca.red cb.red) (at ca.green cb.green) (at ca.blue cb.blue)


{-| The keyline that lifts characters off the hatching.
-}
paper : Color
paper =
    Color.rgb255 250 249 245


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


{-| Round the corners of a closed polygon, each vertex carrying its own radius.

Trim that radius back along both edges of the vertex and bridge them with a
quadratic through the corner itself. Radius `0` collapses both trim points onto
the vertex, so the curve degenerates and the corner stays sharp — which is how
the tail keeps its point while every other corner in the same path is rounded.

General enough for the balloon staircase, where corners alternate between
convex and concave and edge lengths vary line by line. Degenerate points are
dropped first: a zero-length step, which happens whenever two lines are the
same width, would otherwise ask for the direction of a zero vector.

-}
roundedPolygon : List ( ( Float, Float ), Float ) -> Shape
roundedPolygon pts0 =
    let
        far ( ( ax, ay ), _ ) ( ( bx, by ), _ ) =
            abs (ax - bx) + abs (ay - by) > 0.01

        pts =
            List.foldr
                (\p acc ->
                    case acc of
                        q :: _ ->
                            if far p q then
                                p :: acc

                            else
                                acc

                        [] ->
                            [ p ]
                )
                []
                pts0

        n =
            List.length pts

        rotate k xs =
            List.drop k xs ++ List.take k xs

        toward r ( vx, vy ) ( tx, ty ) =
            let
                ( dx, dy ) =
                    ( tx - vx, ty - vy )

                d =
                    max 0.001 (sqrt (dx * dx + dy * dy))

                k =
                    min r (d / 2) / d
            in
            ( vx + dx * k, vy + dy * k )

        corner ( prev, _ ) ( cur, r ) ( next, _ ) =
            ( toward r cur prev, cur, toward r cur next )

        corners =
            List.map3 corner (rotate (n - 1) pts) pts (rotate 1 pts)
    in
    case corners of
        ( a0, _, _ ) :: _ ->
            Canvas.path a0
                (List.concatMap
                    (\( a, c, b ) -> [ Canvas.lineTo a, Canvas.quadraticCurveTo c b ])
                    corners
                    -- close the ring. Without this the last edge is never
                    -- stroked: fill auto-closes a path, stroke does not, so the
                    -- shape looked right but the top border was simply absent.
                    ++ [ Canvas.lineTo a0 ]
                )

        [] ->
            Canvas.path ( 0, 0 ) []


{-| A Comic Chat balloon: one box per line, stacked.

Each line gets a white box sized to that line, so the balloon's silhouette
steps in and out as the lines change length. Drawn as the **outline of the
union** rather than as separate rectangles — walk the right edge down, stepping
across wherever the width changes, then back up the left. That is what gives
interior lines no top or bottom border while the outermost edges keep theirs,
without any per-edge bookkeeping.

-}
lineStack : Float -> Float -> Float -> Float -> List Float -> List ( ( Float, Float ), Float ) -> Shape
lineStack cx top rowH radius halfWidths tail =
    let
        rowY i =
            top + toFloat i * rowH

        soft p =
            ( p, radius )

        indexed =
            List.indexedMap Tuple.pair halfWidths

        downRight =
            indexed
                |> List.concatMap
                    (\( i, hw ) -> [ soft ( cx + hw, rowY i ), soft ( cx + hw, rowY (i + 1) ) ])

        upLeft =
            indexed
                |> List.reverse
                |> List.concatMap
                    (\( i, hw ) -> [ soft ( cx - hw, rowY (i + 1) ), soft ( cx - hw, rowY i ) ])
    in
    -- The tail is spliced into the bottom edge rather than drawn as its own
    -- shape, so balloon and pointer share one continuous outline. Drawing them
    -- separately meant the tail's edges were stroked from roots inside the
    -- balloon, crossing the bottom border and running up into the white —
    -- which no amount of fill-over-stroke ordering can hide.
    roundedPolygon (downRight ++ tail ++ upLeft)


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
            fy
                - (charDef b.who).height * u
                - liftOf (charDef b.who) ((charDef b.who).height * u) a

        cx =
            fx + a.facing * bw * 0.22

        rowH =
            bh / toFloat (max 1 (List.length b.lines))

        shown =
            Fold.revealed b

        -- The balloon grows a line at a time. Only lines that have started
        -- revealing get a box, so there is never a stretch of empty white
        -- waiting to be filled.
        visible =
            shown |> List.filter (not << String.isEmpty) |> List.length |> max 1

        -- Bottom edge is fixed and the top rises: the balloon opens upward,
        -- away from the speaker, so the tail never has to move while the
        -- balloon is still growing.
        bottom =
            headTop - bh * 0.9

        top =
            bottom - toFloat visible * rowH

        longest =
            b.lines |> List.map String.length |> List.maximum |> Maybe.withDefault 1 |> max 1

        -- per-line width, proportional to the line's length. The compiler
        -- measures only the longest line today (§4.2); when it emits per-line
        -- widths this can use them directly.
        halfWidths =
            b.lines
                |> List.take visible
                |> List.map
                    (\line ->
                        bw / 2 * max 0.34 (toFloat (String.length line) / toFloat longest)
                    )

        lastHalf =
            List.reverse halfWidths |> List.head |> Maybe.withDefault (bw / 2)

        shape =
            lineStack cx top rowH (rowH * 0.34) halfWidths tail

        -- overshoot slightly into the head, so the spike lands on the speaker
        -- instead of stopping in mid-air near them
        tailTip =
            ( fx + a.facing * u * 0.03, headTop + u * 0.02 )

        -- Roots sit on the bottom edge itself, leaning toward the speaker.
        throatCentre =
            cx - a.facing * lastHalf * 0.3

        -- Cap the wedge by ANGLE, not by width. A fixed fraction of the
        -- balloon looked fine on a long tail and splayed open on a short one,
        -- because the same base subtends a much wider angle when the speaker
        -- is close. Half the base may not exceed `drop * tan(10°)`, so the
        -- pointer is never blunter than 20° however near the head sits.
        drop =
            max 1 (Tuple.second tailTip - bottom)

        throatHalf =
            clamp (rowH * 0.1) (lastHalf * 0.25) (drop * tan (degrees 10))

        rootA =
            throatCentre - throatHalf

        rootB =
            throatCentre + throatHalf

        -- The throat corners soften like every other join; the tip alone
        -- stays sharp, because a pointer that has been rounded off is no
        -- longer pointing at anything.
        tail =
            [ ( ( max rootA rootB, bottom ), rowH * 0.34 )
            , ( tailTip, 0 )
            , ( ( min rootA rootB, bottom ), rowH * 0.34 )
            ]

        rowText fam size col =
            List.indexedMap
                (\i str ->
                    Canvas.text
                        [ font { size = round (size * s), family = fam }
                        , align Center
                        , baseLine Middle
                        , fill col
                        ]
                        ( cx, top + (toFloat i + 0.5) * rowH )
                        str
                )
                (List.take visible shown)

        comic =
            "'Comic Sans MS', 'Chalkboard SE', 'Marker Felt', cursive"

        -- One shape now: fill it, stroke it. No ordering tricks left to get
        -- wrong.
        balloon shp lw col =
            [ Canvas.shapes [ fill Color.white ] [ shp ]
            , Canvas.shapes [ stroke col, lineWidth (lw * s), lineJoin RoundJoin ] [ shp ]
            ]
    in
    case b.kind of
        "shout" ->
            balloon shape 4.5 ink ++ rowText comic 26 ink

        "whisper" ->
            balloon shape 1.4 (Color.rgb255 150 146 158)
                ++ rowText comic 18 (Color.rgb255 90 86 98)

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
                                    ( cx + cos ang * bw * 0.47, bottom - bh / 2 + sin ang * bh * 0.47 )
                                    (bh * 0.2)
                            )

                trail =
                    [ Canvas.circle ( cx - bw * 0.18, bottom + bh * 0.22 ) (bh * 0.1)
                    , Canvas.circle ( cx - bw * 0.28, bottom + bh * 0.48 ) (bh * 0.06)
                    ]
            in
            -- Stroke the lobes first, then fill the union over them. Only the
            -- outer arcs survive, so the silhouette reads as one cloud instead
            -- of a heap of circles drawn on top of the balloon. The stroke is
            -- doubled because filling eats its inner half.
            [ Canvas.shapes
                [ stroke (Color.rgb255 120 116 130), lineWidth (4 * s), lineJoin RoundJoin ]
                lobes
            , Canvas.shapes [ fill Color.white ]
                (ellipse ( cx, bottom - bh / 2 ) (bw / 2) (bh / 2) :: lobes)
            , Canvas.shapes [ fill Color.white ] trail
            , Canvas.shapes [ stroke (Color.rgb255 120 116 130), lineWidth (2 * s) ] trail
            ]
                ++ rowText comic 22 ink

        _ ->
            balloon shape 3 ink ++ rowText comic 22 ink


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
