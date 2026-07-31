module Main exposing (main)

{-| Clock spike — ARCHITECTURE.md §12 step 1.

What this is here to prove, and nothing more:

1.  State is a pure function of the script and the wall clock. Open the page at
    any moment and you are correctly mid-scene, mid-gesture, mid-sentence.
2.  Two browsers opened at the same instant show the same frame.
3.  A throttled or backgrounded tab resumes correct with no catch-up.
4.  Rewind (§13) is a clock offset and costs nothing.

The art, the rig, the vocabulary and the fixture are all placeholders. The
clock is not.

-}

import Browser
import Browser.Dom
import Browser.Events
import Canvas
import Dict
import Fold
import Html exposing (Html, div, span, text)
import Html.Attributes exposing (style)
import Html.Lazy
import Http
import HttpDate
import Json.Decode as D
import Render
import Script exposing (Chunk)
import Task
import Time



-- MODEL


type alias Model =
    { chunk : Maybe Chunk
    , error : Maybe String
    , now : Time.Posix
    , skewMs : Float
    , clock : Clock
    , size : ( Float, Float )
    , debug : Bool
    , stepped : Bool
    , plates : Bool

    -- Cached background geometry. Roughly 1,200 hatch paths plus the ridges
    -- and set dressing, all of which are static for as long as the location,
    -- the shot type and the viewport hold still — which is most of the time.
    -- Baked at an identity camera, so panning and zooming do not invalidate it
    -- (see Render.cameraXf).
    , bgKey : String
    , bg : List Canvas.Renderable

    -- smoothed, so the hatch density can be judged on real hardware rather
    -- than from headless captures, which rasterise in software
    , fps : Float
    }


{-| Rewind is not a scrubber over a video, it is a DVR offset from live (§13).
-}
type Clock
    = Live
    | Paused Float
    | Rewound Float


type Msg
    = Frame Time.Posix
    | Resized Float Float
    | GotChunk (Result String ( Chunk, Maybe Int ))
    | Key String


main : Program D.Value Model Msg
main =
    Browser.element
        { init = init
        , update = update
        , view = view
        , subscriptions = subscriptions
        }


{-| Query-string flags, for the screenshot harness (`tools/shots.sh`).

`?t=` pins the clock to a fixed cycle-time so a capture is reproducible —
without it every screenshot lands wherever the wall clock happens to be, and
two runs can never be compared. `?hud=0` strips the overlay for a clean frame.

-}
init : D.Value -> ( Model, Cmd Msg )
init flags =
    let
        num key fallback =
            D.decodeValue (D.field key D.float) flags |> Result.withDefault fallback

        pinned =
            num "t" -1
    in
    ( { chunk = Nothing
      , error = Nothing
      , now = Time.millisToPosix 0
      , skewMs = 0
      , clock =
            if pinned >= 0 then
                Paused pinned

            else
                Live
      , size = ( 1280, 720 )
      , debug = num "hud" 1 /= 0
      , stepped = num "stepped" 1 /= 0
      , plates = num "plates" 1 /= 0
      , bgKey = ""
      , bg = []
      , fps = 0
      }
    , Cmd.batch
        [ fetchChunk
        , Task.perform (\v -> Resized v.viewport.width v.viewport.height) Browser.Dom.getViewport
        , Task.perform Frame Time.now
        ]
    )



-- TIME


{-| World time, in seconds since the chunk's epoch, corrected for however wrong
this machine's clock happens to be.
-}
liveT : Model -> Chunk -> Float
liveT model chunk =
    (toFloat (Time.posixToMillis model.now) + model.skewMs - toFloat chunk.epoch) / 1000


worldT : Model -> Chunk -> Float
worldT model chunk =
    case model.clock of
        Live ->
            liveT model chunk

        Paused t ->
            t

        Rewound offset ->
            liveT model chunk - offset



-- UPDATE


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        Frame posix ->
            let
                dt =
                    toFloat (Time.posixToMillis posix - Time.posixToMillis model.now)

                fps =
                    if dt > 0 && dt < 1000 then
                        model.fps * 0.9 + (1000 / dt) * 0.1

                    else
                        model.fps
            in
            ( refreshBackground { model | now = posix, fps = fps }, Cmd.none )

        Resized w h ->
            ( refreshBackground { model | size = ( w, h ) }, Cmd.none )

        GotChunk (Ok ( chunk, serverMs )) ->
            ( { model
                | chunk = Just chunk
                , skewMs =
                    case serverMs of
                        -- one sample, so it carries the request latency with
                        -- it; good to a second, which is all we need
                        Just ms ->
                            toFloat (ms - Time.posixToMillis model.now)

                        Nothing ->
                            0
              }
                |> refreshBackground
            , Cmd.none
            )

        GotChunk (Err e) ->
            ( { model | error = Just e }, Cmd.none )

        Key key ->
            ( applyKey key model, Cmd.none )


{-| Rebuild the cached background when — and only when — the thing it depends
on changes. Cheap to check every frame: one fold and a string compare.

The fold runs again in `view`, which is mild duplication, but folding a scene is
microseconds by design (§1) and the point of the cache is the thousand-odd hatch
paths, not the arithmetic.

-}
refreshBackground : Model -> Model
refreshBackground model =
    case model.chunk |> Maybe.andThen (\c -> Fold.seek c (worldT model c) |> Maybe.map (Tuple.pair c)) of
        Nothing ->
            model

        Just ( _, found ) ->
            let
                st =
                    Fold.stateAt found.scene found.localT

                l =
                    Render.layout model.size st

                key =
                    Render.bgKey l found.scene.loc st.shot
            in
            if key == model.bgKey then
                model

            else
                { model
                    | bgKey = key
                    , bg = Render.backgroundStatic l found.scene.loc st.shot
                }


applyKey : String -> Model -> Model
applyKey key model =
    let
        -- where we are right now, whatever mode we are in
        current =
            model.chunk |> Maybe.map (worldT model) |> Maybe.withDefault 0
    in
    case String.toLower key of
        " " ->
            case model.clock of
                Paused _ ->
                    { model | clock = Live }

                _ ->
                    { model | clock = Paused current }

        "arrowleft" ->
            seekTo (current - 10) model

        "arrowright" ->
            seekTo (current + 10) model

        "r" ->
            jumpScene 0 model

        "[" ->
            jumpScene -1 model

        "]" ->
            jumpScene 1 model

        "l" ->
            { model | clock = Live }

        "d" ->
            { model | debug = not model.debug }

        "s" ->
            { model | stepped = not model.stepped }

        "n" ->
            { model | plates = not model.plates }

        _ ->
            model


{-| Move the clock to an absolute world time, preserving pause state.
-}
seekTo : Float -> Model -> Model
seekTo target model =
    case model.chunk of
        Nothing ->
            model

        Just chunk ->
            let
                live =
                    liveT model chunk
            in
            case model.clock of
                Paused _ ->
                    { model | clock = Paused target }

                _ ->
                    if target >= live - 0.5 then
                        { model | clock = Live }

                    else
                        { model | clock = Rewound (live - target) }


{-| Rewind to the start of a scene `step` scenes from the one playing now: `0`
restarts the current scene, `-1` the previous, `1` the next.

It always rewinds and never fast-forwards, because in a live show the future
does not exist yet. "Next scene" therefore means that scene's most recent
occurrence, which for the looping demo fixture is one cycle back.

Unlike the arrow keys this resumes playback when paused — the point of the key
is to watch the scene, not to sit at its first frame.

-}
jumpScene : Int -> Model -> Model
jumpScene step model =
    case model.chunk of
        Nothing ->
            model

        Just chunk ->
            let
                now =
                    worldT model chunk
            in
            case Fold.seek chunk now of
                Nothing ->
                    model

                Just found ->
                    let
                        starts =
                            List.map .t0 chunk.scenes

                        n =
                            max 1 (List.length starts)

                        idx =
                            starts
                                |> List.indexedMap Tuple.pair
                                |> List.filter (\( _, t0 ) -> t0 == found.scene.t0)
                                |> List.head
                                |> Maybe.map Tuple.first
                                |> Maybe.withDefault 0

                        target =
                            starts
                                |> List.drop (modBy n (idx + step))
                                |> List.head
                                |> Maybe.withDefault 0

                        delta =
                            if step == 0 then
                                -found.localT

                            else
                                let
                                    raw =
                                        target - fmod now chunk.cycle
                                in
                                if raw >= 0 then
                                    raw - chunk.cycle

                                else
                                    raw

                        wanted =
                            now + delta

                        live =
                            liveT model chunk
                    in
                    { model
                        | clock =
                            if wanted >= live - 0.5 then
                                Live

                            else
                                Rewound (live - wanted)
                    }



-- HTTP


fetchChunk : Cmd Msg
fetchChunk =
    Http.request
        { method = "GET"
        , headers = []
        , url = "/demo-world/chunk.json"
        , body = Http.emptyBody
        , expect = Http.expectStringResponse GotChunk handleResponse
        , timeout = Nothing
        , tracker = Nothing
        }


{-| We want the body *and* the `Date` header — the header is the clock
authority, so a viewer with a wrong system clock still sees what everyone else
sees (§1).
-}
handleResponse : Http.Response String -> Result String ( Chunk, Maybe Int )
handleResponse response =
    case response of
        Http.GoodStatus_ meta body ->
            case D.decodeString Script.decoder body of
                Ok chunk ->
                    Ok ( chunk, Dict.get "date" meta.headers |> Maybe.andThen HttpDate.parse )

                Err err ->
                    Err (D.errorToString err)

        Http.BadStatus_ meta _ ->
            Err ("HTTP " ++ String.fromInt meta.statusCode ++ " for " ++ meta.url)

        Http.BadUrl_ url ->
            Err ("bad url: " ++ url)

        Http.Timeout_ ->
            Err "timeout"

        Http.NetworkError_ ->
            Err "network error — is the static server running from the repo root?"



-- SUBSCRIPTIONS


subscriptions : Model -> Sub Msg
subscriptions _ =
    Sub.batch
        [ -- absolute Posix, never a delta: deltas accumulate, and accumulation
          -- is drift
          Browser.Events.onAnimationFrame Frame
        , Browser.Events.onResize (\w h -> Resized (toFloat w) (toFloat h))
        , Browser.Events.onKeyDown (D.map Key (D.field "key" D.string))
        ]



-- VIEW


view : Model -> Html Msg
view model =
    let
        ( w, h ) =
            model.size
    in
    div
        [ style "position" "fixed"
        , style "inset" "0"
        , style "background" "#16141c"
        , style "overflow" "hidden"
        ]
        (case ( model.chunk, model.error ) of
            ( _, Just err ) ->
                [ notice ("error: " ++ err) ]

            ( Nothing, Nothing ) ->
                [ notice "loading the world…" ]

            ( Just chunk, Nothing ) ->
                let
                    t =
                        worldT model chunk
                in
                case Fold.seek chunk t of
                    Nothing ->
                        [ notice "no scene at this time — the world is idling" ]

                    Just found ->
                        let
                            st =
                                Fold.stateAt found.scene found.localT

                            l =
                                Render.layout ( w, h ) st
                        in
                        [ -- Background: rasterised once per location onto its
                          -- own canvas, then moved by the compositor. `lazy3`
                          -- is what keeps elm-canvas from re-issuing every
                          -- hatch path each frame — the whole point of the
                          -- split.
                          div
                            [ style "position" "absolute"
                            , style "inset" "0"
                            , style "overflow" "hidden"
                            ]
                            [ div
                                [ style "transform-origin" "0 0"
                                , style "transform" (Render.cameraCss l)
                                ]
                                [ Html.Lazy.lazy3 backdrop (round w) (round h) model.bg ]
                            ]
                        , div [ style "position" "absolute", style "inset" "0" ]
                            [ Canvas.toHtml ( round w, round h )
                                [ style "display" "block" ]
                                (Render.scene l
                                    found.scene.loc
                                    st
                                    found.localT
                                    { stepped = model.stepped, plates = model.plates }
                                )
                            ]
                        , hud model chunk t found
                        ]
        )


{-| The background canvas. Kept behind `lazy3` so Elm skips it entirely while
its inputs are unchanged, which is most frames.
-}
backdrop : Int -> Int -> List Canvas.Renderable -> Html msg
backdrop w h items =
    Canvas.toHtml ( w, h ) [ style "display" "block" ] items


notice : String -> Html msg
notice msg =
    div
        [ style "position" "absolute"
        , style "inset" "0"
        , style "display" "flex"
        , style "align-items" "center"
        , style "justify-content" "center"
        , style "color" "#8f8a9c"
        , style "font" "15px ui-monospace, monospace"
        ]
        [ text msg ]


hud : Model -> Chunk -> Float -> Fold.Seek -> Html msg
hud model chunk t found =
    let
        mode =
            case model.clock of
                Live ->
                    ( "● LIVE", "#5ad07a" )

                Paused _ ->
                    ( "❚❚ PAUSED", "#e0c060" )

                Rewound off ->
                    ( "◀ REWOUND −" ++ secs off, "#7ab6e0" )

        sceneNo =
            chunk.scenes
                |> List.indexedMap Tuple.pair
                |> List.filter (\( _, s ) -> s.id == found.scene.id)
                |> List.head
                |> Maybe.map (\( i, _ ) -> String.fromInt (i + 1))
                |> Maybe.withDefault "?"

        rows =
            [ ( "world t", secs t )
            , ( "cycle t", secs (fmod t chunk.cycle) )
            , ( "scene"
              , found.scene.id
                    ++ " ("
                    ++ sceneNo
                    ++ "/"
                    ++ String.fromInt (List.length chunk.scenes)
                    ++ ")  @ "
                    ++ secs found.localT
                    ++ " / "
                    ++ secs found.scene.dur
              )
            , ( "skew", String.fromInt (round model.skewMs) ++ " ms" )
            , ( "sampling", ifElse model.stepped "12 fps stepped" "smooth" )
            , ( "plates", ifElse model.plates "on" "off" )
            , ( "fps", String.fromInt (round model.fps) )
            ]

        row ( k, v ) =
            div [ style "display" "flex", style "gap" "10px" ]
                [ span [ style "color" "#6f6a7c", style "width" "70px" ] [ text k ]
                , span [] [ text v ]
                ]
    in
    div
        [ style "position" "absolute"
        , style "left" "16px"
        , style "top" "16px"
        , style "padding" "12px 14px"
        , style "border-radius" "10px"
        , style "background" "rgba(18,16,24,.78)"
        , style "color" "#d8d4e0"
        , style "font" "12px/1.7 ui-monospace, SFMono-Regular, monospace"
        , style "pointer-events" "none"
        , style "backdrop-filter" "blur(6px)"
        ]
        (div
            [ style "color" (Tuple.second mode)
            , style "font-weight" "700"
            , style "margin-bottom" "6px"
            ]
            [ text (Tuple.first mode) ]
            :: (if model.debug then
                    List.map row rows
                        ++ [ div
                                [ style "margin-top" "8px", style "color" "#6f6a7c" ]
                                [ text "R restart scene · [ ] prev/next · N plates · space pause · ←/→ ±10s · L live · S sampling · D details" ]
                           ]

                else
                    []
               )
        )


secs : Float -> String
secs t =
    let
        whole =
            floor (abs t)

        frac =
            floor ((abs t - toFloat whole) * 10)
    in
    (if t < 0 then
        "-"

     else
        ""
    )
        ++ String.fromInt (whole // 60)
        ++ ":"
        ++ String.padLeft 2 '0' (String.fromInt (modBy 60 whole))
        ++ "."
        ++ String.fromInt frac


ifElse : Bool -> a -> a -> a
ifElse c a b =
    if c then
        a

    else
        b


fmod : Float -> Float -> Float
fmod a b =
    if b <= 0 then
        a

    else
        a - b * toFloat (floor (a / b))
