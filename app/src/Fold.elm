module Fold exposing
    ( ActorState
    , Bubble
    , Mark
    , Seek
    , State
    , revealed
    , seek
    , stateAt
    )

{-| The heart of the whole design (ARCHITECTURE.md §1).

    render (timeline, wallClock) -> frame

State at any moment is computed from scratch, by folding every beat that has
already started. No frame-to-frame simulation, no accumulated delta, so:

  - a backgrounded tab resumes correct with no catch-up logic
  - opening the page late is the same operation as playing
  - rewind is free

The invariant worth property-testing: folding from scratch at `localT` must
equal folding incrementally up to `localT`.

-}

import Dict exposing (Dict)
import Script exposing (Beat, Chunk, Scene)



-- TYPES


type alias Seek =
    { scene : Scene
    , localT : Float
    }


type alias State =
    { actors : Dict String ActorState
    , bubbles : List Bubble
    , marks : List Mark
    , camAt : ( Float, Float )
    , camZoom : Float
    , shot : String
    }


{-| An ink annotation currently on screen. `drawn` is the scratchy draw-on
progress; a mark holds at 1 until its beat expires, and is never faded out.
-}
type alias Mark =
    { kind : String
    , at : ( Float, Float )
    , to : ( Float, Float )
    , r : Float
    , label : String
    , drawn : Float
    , seed : String
    }


type alias ActorState =
    { pos : ( Float, Float )
    , facing : Float
    , pose : String
    , prevPose : String
    , poseP : Float -- 0..1 blend from prevPose to pose
    , expr : String
    , act : String -- "", "walk", "dance", "hop"
    , actP : Float -- progress through the current act
    , moving : Bool
    }


type alias Bubble =
    { who : String
    , kind : String
    , lines : List String
    , w : Float
    , h : Float
    , reveal : Float -- 0..1 typewriter progress
    }



-- SEEK


{-| Find the scene containing world-time `t`.

The spike loops its fixture; the real client walks the manifest instead and
this becomes a binary search over a chunk's scenes.

-}
seek : Chunk -> Float -> Maybe Seek
seek chunk t =
    let
        wrapped =
            if chunk.cycle > 0 then
                fmod t chunk.cycle

            else
                t
    in
    chunk.scenes
        |> List.filter (\s -> wrapped >= s.t0 && wrapped < s.t0 + s.dur)
        |> List.head
        |> Maybe.map (\s -> { scene = s, localT = wrapped - s.t0 })


fmod : Float -> Float -> Float
fmod a b =
    a - b * toFloat (floor (a / b))



-- FOLD


stateAt : Scene -> Float -> State
stateAt scene localT =
    let
        initial =
            { actors =
                scene.cast
                    |> List.map (\a -> ( a.id, initActor a ))
                    |> Dict.fromList
            , bubbles = []
            , marks = []
            , camAt = ( 0.5, 0.5 )
            , camZoom = 1
            , shot = "mid"
            }
    in
    scene.beats
        |> List.filter (\b -> b.t <= localT)
        |> List.foldl (applyBeat localT) initial
        |> (\st -> { st | bubbles = List.reverse st.bubbles, marks = List.reverse st.marks })


initActor : Script.Actor -> ActorState
initActor a =
    { pos = a.at
    , facing = a.facing
    , pose = a.pose
    , prevPose = a.pose
    , poseP = 1
    , expr = a.expr
    , act = ""
    , actP = 0
    , moving = False
    }


applyBeat : Float -> Beat -> State -> State
applyBeat localT b st0 =
    let
        -- progress through this beat, saturating at 1 once it has finished
        p =
            if b.dur <= 0 then
                1

            else
                clamp 0 1 ((localT - b.t) / b.dur)

        st1 =
            case b.cam of
                Just c ->
                    { st0
                        | camAt = lerp2 st0.camAt c.to p
                        , camZoom = lerp st0.camZoom c.zoom p

                        -- the shot type snaps rather than tweens; a cut is
                        -- a cut
                        , shot = c.shot
                    }

                Nothing ->
                    st0

        st1b =
            case b.ann of
                Just a ->
                    if localT < b.t + b.dur then
                        { st1 | marks = markFrom a (localT - b.t) :: st1.marks }

                    else
                        st1

                Nothing ->
                    st1
    in
    case b.who of
        Nothing ->
            st1b

        Just who ->
            let
                st2 =
                    { st1b | actors = Dict.update who (Maybe.map (applyActor b p)) st1b.actors }
            in
            case b.say of
                Just s ->
                    if localT < b.t + b.dur then
                        { st2 | bubbles = bubbleFrom who s b.dur (localT - b.t) :: st2.bubbles }

                    else
                        st2

                Nothing ->
                    st2


applyActor : Beat -> Float -> ActorState -> ActorState
applyActor b p a0 =
    let
        a1 =
            case b.to of
                Just target ->
                    { a0 | pos = lerp2 a0.pos target (ease p) }

                Nothing ->
                    a0

        a2 =
            case b.pose of
                Just newPose ->
                    if newPose == a1.pose then
                        a1

                    else
                        { a1 | prevPose = a1.pose, pose = newPose, poseP = ease p }

                Nothing ->
                    a1

        a3 =
            case b.act of
                Just act ->
                    { a2 | act = act, actP = p, moving = p < 1 }

                Nothing ->
                    a2
    in
    { a3
        | expr = Maybe.withDefault a3.expr b.expr
        , facing = Maybe.withDefault a3.facing b.face
    }


{-| Marks draw on in 0.45s and then hold. No fade — see style.md.
-}
markFrom : Script.Ann -> Float -> Mark
markFrom a elapsed =
    { kind = a.kind
    , at = a.at
    , to = a.to
    , r = a.r
    , label = a.label
    , drawn = clamp 0 1 (elapsed / 0.45)
    , seed = a.kind ++ String.fromFloat (Tuple.first a.at) ++ a.label
    }


{-| Typewriter reveal. Text finishes well before the bubble goes away, so a
line has time to be read after it lands.
-}
bubbleFrom : String -> Script.Say -> Float -> Float -> Bubble
bubbleFrom who s dur elapsed =
    let
        chars =
            s.lines |> List.map String.length |> List.sum |> toFloat

        revealDur =
            min (dur * 0.55) (chars * 0.045)
    in
    { who = who
    , kind = s.kind
    , lines = s.lines
    , w = s.w
    , h = s.h
    , reveal =
        if revealDur <= 0 then
            1

        else
            clamp 0 1 (elapsed / revealDur)
    }



{-| The visible prefix of a bubble's pre-wrapped lines. Script semantics, not
rendering — the probe checks it without a canvas.
-}
revealed : Bubble -> List String
revealed b =
    if b.kind == "deduction" then
        -- inference arrives a whole link at a time, not letter by letter
        List.take (ceiling (b.reveal * toFloat (List.length b.lines))) b.lines

    else
        let
            total =
                b.lines |> List.map String.length |> List.sum |> toFloat

            step str ( left, acc ) =
                ( left - String.length str, String.left left str :: acc )
        in
        List.foldl step ( round (b.reveal * total), [] ) b.lines
            |> Tuple.second
            |> List.reverse



-- MATH


lerp : Float -> Float -> Float -> Float
lerp a b p =
    a + (b - a) * p


lerp2 : ( Float, Float ) -> ( Float, Float ) -> Float -> ( Float, Float )
lerp2 ( ax, ay ) ( bx, by ) p =
    ( lerp ax bx p, lerp ay by p )


{-| smoothstep — nothing in this world starts or stops abruptly
-}
ease : Float -> Float
ease p =
    p * p * (3 - 2 * p)
