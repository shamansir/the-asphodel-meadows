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
        [ background l loc ts
        , List.concatMap (\( id, a ) -> drawActor l id a ts) actors
        , List.concatMap (drawBubble l st) st.bubbles
        , letterbox l
        ]



-- BACKGROUND


background : Layout -> String -> Float -> List Renderable
background l loc t =
    let
        sky =
            [ ( 0.0, Color.rgb255 250 214 165 )
            , ( 0.28, Color.rgb255 246 186 156 )
            , ( 0.46, Color.rgb255 226 158 158 )
            ]

        band ( y0, c ) =
            Canvas.shapes [ fill c ]
                [ stageRect l ( 0, y0 ) 1 0.25 ]
    in
    List.concat
        [ [ Canvas.shapes [ fill (Color.rgb255 250 214 165) ]
                [ Canvas.rect ( l.ox, l.oy ) l.boxW l.boxH ]
          ]
        , List.map band sky
        , [ sun l ]
        , clouds l loc t
        , [ hills l (Color.rgb255 176 142 168) 0.5 0.055 (Rng.float01 (loc ++ "far"))
          , hills l (Color.rgb255 138 176 140) 0.62 0.075 (Rng.float01 (loc ++ "mid"))
          , Canvas.shapes [ fill (Color.rgb255 158 200 148) ]
                [ stageRect l ( 0, 0.74 ) 1 0.3 ]
          ]
        , scatter l loc
        ]


sun : Layout -> Renderable
sun l =
    let
        ( x, y ) =
            toScreen l ( 0.82, 0.16 )
    in
    Canvas.shapes [ fill (Color.rgb255 255 246 214) ]
        [ Canvas.circle ( x, y ) (unit l * 0.075) ]


clouds : Layout -> String -> Float -> List Renderable
clouds l loc t =
    let
        one i =
            let
                seed =
                    loc ++ "cloud" ++ String.fromInt i

                y =
                    0.08 + Rng.float01 seed * 0.18

                sizeS =
                    0.03 + Rng.float01 (seed ++ "s") * 0.03

                -- drift is a pure function of world time, so every viewer's
                -- clouds sit in exactly the same place
                x =
                    fmod (Rng.float01 (seed ++ "x") + t * 0.004) 1.25 - 0.12

                ( px, py ) =
                    toScreen l ( x, y )

                u =
                    unit l
            in
            Canvas.shapes [ fill (Color.rgb255 255 252 244) ]
                [ Canvas.circle ( px, py ) (u * sizeS)
                , Canvas.circle ( px + u * sizeS * 0.9, py + u * sizeS * 0.15 ) (u * sizeS * 0.75)
                , Canvas.circle ( px - u * sizeS * 0.85, py + u * sizeS * 0.2 ) (u * sizeS * 0.6)
                ]
    in
    List.map one (List.range 0 4)


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


{-| Lollipop trees and boulders. Placed by hash, so they are in the same spot
for everyone, forever, without being listed in the script.
-}
scatter : Layout -> String -> List Renderable
scatter l loc =
    let
        u =
            unit l

        tree i =
            let
                seed =
                    loc ++ "tree" ++ String.fromInt i

                x =
                    Rng.float01 seed

                y =
                    0.76 + Rng.float01 (seed ++ "y") * 0.06

                sizeS =
                    (0.05 + Rng.float01 (seed ++ "s") * 0.04) * u

                ( px, py ) =
                    toScreen l ( x, y )
            in
            [ Canvas.shapes
                [ stroke (Color.rgb255 150 106 84), lineWidth (sizeS * 0.22), lineCap RoundCap ]
                [ Canvas.path ( px, py )
                    [ Canvas.quadraticCurveTo ( px + sizeS * 0.25, py - sizeS ) ( px, py - sizeS * 1.7 ) ]
                ]
            , Canvas.shapes [ fill (Color.rgb255 108 168 118) ]
                [ Canvas.circle ( px, py - sizeS * 2 ) (sizeS * 0.72) ]
            ]
    in
    List.concatMap tree (List.range 0 3)


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
        "ch.pib" ->
            { body = Color.rgb255 116 196 214
            , trim = Color.rgb255 64 142 168
            , height = 0.20
            , girth = 0.62
            , limb = 0.055
            , topper = "tuft"
            }

        "ch.wobb" ->
            { body = Color.rgb255 240 176 96
            , trim = Color.rgb255 196 122 58
            , height = 0.31
            , girth = 0.34
            , limb = 0.042
            , topper = "antenna"
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
    case Dict.get b.who st.actors of
        Nothing ->
            []

        Just a ->
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

                fontPx =
                    round (22 * s)

                shown =
                    Fold.revealed b

                lineH =
                    26 * s

                top =
                    cy - (toFloat (List.length b.lines) - 1) * lineH / 2

                textLine i str =
                    Canvas.text
                        [ font { size = fontPx, family = "'Comic Sans MS', 'Chalkboard SE', 'Marker Felt', cursive" }
                        , align Center
                        , baseLine Middle
                        , fill (Color.rgb255 26 22 30)
                        ]
                        ( cx, top + toFloat i * lineH )
                        str

                tail =
                    Canvas.path ( cx - bw * 0.1, cy + bh * 0.4 )
                        [ Canvas.lineTo ( cx + bw * 0.06, cy + bh * 0.42 )
                        , Canvas.lineTo ( fx + a.facing * u * 0.02, headTop - u * 0.01 )
                        , Canvas.lineTo ( cx - bw * 0.1, cy + bh * 0.4 )
                        ]

                outline =
                    if b.kind == "thought" then
                        Color.rgb255 120 116 130

                    else
                        Color.rgb255 26 22 30
            in
            [ Canvas.shapes [ fill Color.white ]
                [ tail, ellipse ( cx, cy ) (bw / 2) (bh / 2) ]
            , Canvas.shapes [ stroke outline, lineWidth (3 * s), lineJoin RoundJoin ]
                [ ellipse ( cx, cy ) (bw / 2) (bh / 2) ]
            , Canvas.shapes [ stroke outline, lineWidth (3 * s), lineJoin RoundJoin ] [ tail ]
            , Canvas.shapes [ fill Color.white ] [ tail ]
            ]
                ++ List.indexedMap textLine shown


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
