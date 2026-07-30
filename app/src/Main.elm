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


main : Program () Model Msg
main =
    Browser.element
        { init = init
        , update = update
        , view = view
        , subscriptions = subscriptions
        }


init : () -> ( Model, Cmd Msg )
init _ =
    ( { chunk = Nothing
      , error = Nothing
      , now = Time.millisToPosix 0
      , skewMs = 0
      , clock = Live
      , size = ( 1280, 720 )
      , debug = True
      , stepped = True
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
            ( { model | now = posix }, Cmd.none )

        Resized w h ->
            ( { model | size = ( w, h ) }, Cmd.none )

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
            , Cmd.none
            )

        GotChunk (Err e) ->
            ( { model | error = Just e }, Cmd.none )

        Key key ->
            ( applyKey key model, Cmd.none )


applyKey : String -> Model -> Model
applyKey key model =
    let
        -- where we are right now, whatever mode we are in
        current =
            model.chunk |> Maybe.map (worldT model) |> Maybe.withDefault 0

        live =
            model.chunk |> Maybe.map (liveT model) |> Maybe.withDefault 0

        seekBy delta =
            let
                target =
                    current + delta
            in
            case model.clock of
                Paused _ ->
                    { model | clock = Paused target }

                _ ->
                    if target >= live - 0.5 then
                        { model | clock = Live }

                    else
                        { model | clock = Rewound (live - target) }
    in
    case key of
        " " ->
            case model.clock of
                Paused _ ->
                    { model | clock = Live }

                _ ->
                    { model | clock = Paused current }

        "ArrowLeft" ->
            seekBy -10

        "ArrowRight" ->
            seekBy 10

        "l" ->
            { model | clock = Live }

        "d" ->
            { model | debug = not model.debug }

        "s" ->
            { model | stepped = not model.stepped }

        _ ->
            model



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
                        [ Canvas.toHtml ( round w, round h )
                            [ style "display" "block" ]
                            (Render.scene l found.scene.loc st found.localT model.stepped)
                        , hud model chunk t found
                        ]
        )


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

        rows =
            [ ( "world t", secs t )
            , ( "cycle t", secs (fmod t chunk.cycle) )
            , ( "scene", found.scene.id ++ " @ " ++ secs found.localT )
            , ( "skew", String.fromInt (round model.skewMs) ++ " ms" )
            , ( "sampling", ifElse model.stepped "12 fps stepped" "smooth" )
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
                                [ text "space pause · ←/→ ±10s · L live · S sampling · D details" ]
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
