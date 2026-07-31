module Lab exposing (main)

{-| Animation lab — a bench for one character at a time.

Pick a character, then fire poses, expressions and acts at them and watch what
the rig actually does. Nothing here is part of the show; it exists because
judging an animation by scrubbing a five-scene fixture is hopeless, and because
half the vocabulary had never been seen on screen at all.

The button lists are read from `bible/vocabulary.json` at runtime rather than
hardcoded, so anything the writer agent is allowed to emit is something you can
press here. If a verb appears in the lab and does nothing, that is a real gap
in the renderer, and the lab is how you find it.

Served at /app/lab.html.

-}

import Browser
import Browser.Dom
import Browser.Events
import Canvas
import Dict
import Fold
import Html exposing (Html, button, div, span, text)
import Html.Attributes exposing (style)
import Html.Lazy
import Html.Events exposing (onClick)
import Http
import Json.Decode as D
import Render
import Task



-- MODEL


type alias Vocab =
    { acts : List String
    , poses : List String
    , exprs : List String
    }


type alias Model =
    { vocab : Vocab
    , who : String
    , loc : String
    , pose : String
    , prevPose : String
    , poseAt : Float
    , expr : String
    , act : String
    , actUntil : Float
    , t : Float
    , size : ( Float, Float )
    , error : Maybe String
    , bgKey : String
    , bg : List Canvas.Renderable
    , hatched : Bool
    }


cast : List String
cast =
    [ "ch.holmes", "ch.hermes", "ch.charon", "ch.minos", "ch.persephone" ]


locations : List String
locations =
    [ "loc.bank", "loc.ledgers", "loc.asphodel" ]


type Msg
    = Tick Float
    | Resized Float Float
    | GotVocab (Result Http.Error Vocab)
    | Pick String
    | SetLoc String
    | SetPose String
    | SetExpr String
    | SetAct String


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
    ( { vocab = { acts = [], poses = [], exprs = [] }
      , who = "ch.holmes"
      , loc = "loc.bank"
      , pose = "idle"
      , prevPose = "idle"
      , poseAt = -99
      , expr = "neutral"
      , act = ""
      , actUntil = 0
      , t = 0
      , size = ( 1280, 720 )
      , error = Nothing
      , bgKey = ""
      , bg = []
      , hatched = True
      }
    , Cmd.batch
        [ Http.get { url = "/bible/vocabulary.json", expect = Http.expectJson GotVocab vocabDecoder }
        , Task.perform (\v -> Resized v.viewport.width v.viewport.height) Browser.Dom.getViewport
        ]
    )


{-| `acts` is an object keyed by verb; `poses` and `expr` are plain arrays.
-}
vocabDecoder : D.Decoder Vocab
vocabDecoder =
    D.map3 Vocab
        (D.field "acts" (D.keyValuePairs D.value) |> D.map (List.map Tuple.first >> List.sort))
        (D.field "poses" (D.list D.string))
        (D.field "expr" (D.list D.string))



-- UPDATE


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        Tick dt ->
            ( refreshBackground { model | t = model.t + dt }, Cmd.none )

        Resized w h ->
            ( refreshBackground { model | size = ( w, h ) }, Cmd.none )

        GotVocab (Ok v) ->
            ( { model | vocab = v }, Cmd.none )

        GotVocab (Err _) ->
            ( { model | error = Just "could not read /bible/vocabulary.json" }, Cmd.none )

        Pick id ->
            ( { model | who = id }, Cmd.none )

        SetLoc loc ->
            ( refreshBackground { model | loc = loc }, Cmd.none )

        SetPose p ->
            -- keep the old pose around so the blend is visible rather than a snap
            ( { model | prevPose = model.pose, pose = p, poseAt = model.t }, Cmd.none )

        SetExpr e ->
            ( { model | expr = e }, Cmd.none )

        SetAct a ->
            -- acts are momentary by design: they run, then the character
            -- settles back to its pose on its own
            ( { model | act = a, actUntil = model.t + 6 }, Cmd.none )


{-| Same background cache as the show: see Main.refreshBackground.
-}
refreshBackground : Model -> Model
refreshBackground model =
    let
        st =
            stateOf model

        l =
            Render.layout model.size st

        key =
            Render.bgKey l model.loc st.shot model.hatched
    in
    if key == model.bgKey then
        model

    else
        { model | bgKey = key, bg = Render.backgroundStatic l model.loc st.shot model.hatched }


subscriptions : Model -> Sub Msg
subscriptions _ =
    Sub.batch
        [ Browser.Events.onAnimationFrameDelta (\ms -> Tick (ms / 1000))
        , Browser.Events.onResize (\w h -> Resized (toFloat w) (toFloat h))
        ]



-- VIEW


{-| One actor, centre stage, in a real location so the hatching and palette are
judged in context rather than against a void.
-}
stateOf : Model -> Fold.State
stateOf model =
    { actors =
        Dict.singleton model.who
            { pos = ( 0.5, 0.82 )
            , facing = 1
            , pose = model.pose
            , prevPose = model.prevPose
            , poseP = clamp 0 1 ((model.t - model.poseAt) / 0.45)
            , expr = model.expr
            , act = model.act
            , actP = 0.5
            , moving = model.t < model.actUntil
            }
    , bubbles = []
    , marks = []
    , camAt = ( 0.5, 0.66 )
    , camZoom = 1.75
    , shot = "mid"
    }


view : Model -> Html Msg
view model =
    let
        ( w, h ) =
            model.size

        st =
            stateOf model

        l =
            Render.layout ( w, h ) st
    in
    div
        [ style "position" "fixed", style "inset" "0", style "background" "#16141c" ]
        [ div
            [ style "position" "absolute", style "inset" "0", style "overflow" "hidden" ]
            [ div
                [ style "transform-origin" "0 0", style "transform" (Render.cameraCss l) ]
                [ Html.Lazy.lazy3 backdrop (round w) (round h) model.bg ]
            ]
        , div [ style "position" "absolute", style "inset" "0" ]
            [ Canvas.toHtml ( round w, round h )
                [ style "display" "block" ]
                (Render.scene l model.loc st model.t { stepped = True, plates = True })
            ]
        , panel model
        ]


backdrop : Int -> Int -> List Canvas.Renderable -> Html msg
backdrop w h items =
    Canvas.toHtml ( w, h ) [ style "display" "block" ] items


panel : Model -> Html Msg
panel model =
    div
        [ style "position" "absolute"
        , style "left" "0"
        , style "top" "0"
        , style "bottom" "0"
        , style "width" "300px"
        , style "overflow-y" "auto"
        , style "padding" "14px"
        , style "box-sizing" "border-box"
        , style "background" "rgba(18,16,24,.9)"
        , style "backdrop-filter" "blur(8px)"
        , style "color" "#d8d4e0"
        , style "font" "12px ui-monospace, SFMono-Regular, monospace"
        ]
        (case model.error of
            Just e ->
                [ div [ style "color" "#e08080" ] [ text e ]
                , div [ style "margin-top" "8px", style "color" "#6f6a7c" ]
                    [ text "serve from the repo root so /bible is reachable" ]
                ]

            Nothing ->
                [ group "CAST" (List.map (chip model.who Pick) cast)
                , group "LOCATION" (List.map (chip model.loc SetLoc) locations)
                , group "POSE" (List.map (chip model.pose SetPose) model.vocab.poses)
                , group "EXPRESSION" (List.map (chip model.expr SetExpr) model.vocab.exprs)
                , group "ACT" (List.map (chip model.act SetAct) model.vocab.acts)
                , div [ style "color" "#6f6a7c", style "line-height" "1.6" ]
                    [ text "Acts run for 6s and settle back on their own. Poses blend over 0.45s."
                    ]
                ]
        )


group : String -> List (Html Msg) -> Html Msg
group title items =
    div [ style "margin-bottom" "16px" ]
        [ div
            [ style "color" "#6f6a7c"
            , style "letter-spacing" "0.1em"
            , style "margin-bottom" "6px"
            ]
            [ text title ]
        , div [ style "display" "flex", style "flex-wrap" "wrap", style "gap" "4px" ] items
        ]


chip : String -> (String -> Msg) -> String -> Html Msg
chip current toMsg value =
    let
        active =
            current == value
    in
    button
        [ onClick (toMsg value)
        , style "font" "11px ui-monospace, monospace"
        , style "padding" "4px 7px"
        , style "border-radius" "5px"
        , style "cursor" "pointer"
        , style "border"
            (if active then
                "1px solid #b6a4e8"

             else
                "1px solid #3a3646"
            )
        , style "background"
            (if active then
                "#3b3358"

             else
                "#232030"
            )
        , style "color"
            (if active then
                "#e8e2ff"

             else
                "#b8b2c6"
            )
        ]
        [ span [] [ text (String.replace "ch." "" value |> String.replace "loc." "") ] ]
