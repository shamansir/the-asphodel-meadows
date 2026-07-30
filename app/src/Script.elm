module Script exposing
    ( Actor
    , Beat
    , Cam
    , Chunk
    , Say
    , Scene
    , decoder
    )

{-| The published script format. Mirrors ARCHITECTURE.md §4.2.

Every beat is a keyframe assignment, never a delta — that is what makes
seek-anywhere possible (§1). Nothing here describes "add velocity"; a beat says
where a thing ends up and how long it takes to get there.

-}

import Json.Decode as D exposing (Decoder)



-- TYPES


type alias Chunk =
    { chunk : String
    , epoch : Int -- ms since unix epoch; world time is measured from here
    , cycle : Float -- SPIKE ONLY: loop the fixture after this many seconds
    , scenes : List Scene
    }


type alias Scene =
    { id : String
    , t0 : Float -- seconds from chunk start
    , dur : Float
    , loc : String
    , cast : List Actor
    , beats : List Beat -- assumed sorted by .t; the compiler guarantees it
    }


{-| Opening state for one actor in a scene. Folding starts here.
-}
type alias Actor =
    { id : String
    , at : ( Float, Float )
    , facing : Float -- 1 = right, -1 = left
    , pose : String
    , expr : String
    }


{-| One keyframe. Channels are independent and all optional, so a single beat
can move someone, change their face, and give them a line at once.
-}
type alias Beat =
    { t : Float
    , dur : Float
    , who : Maybe String
    , act : Maybe String
    , to : Maybe ( Float, Float )
    , pose : Maybe String
    , expr : Maybe String
    , face : Maybe Float
    , say : Maybe Say
    , cam : Maybe Cam
    }


{-| Lines are pre-wrapped by the compiler, and `w`/`h` are its measurements at
the reference stage height. The browser never measures text — see §4.2.
-}
type alias Say =
    { kind : String
    , lines : List String
    , w : Float
    , h : Float
    }


type alias Cam =
    { to : ( Float, Float )
    , zoom : Float
    }



-- DECODERS


decoder : Decoder Chunk
decoder =
    D.map4 Chunk
        (D.field "chunk" D.string)
        (D.field "epoch" D.int)
        (D.field "cycle" D.float)
        (D.field "scenes" (D.list scene))


scene : Decoder Scene
scene =
    D.map6 Scene
        (D.field "id" D.string)
        (D.field "t0" D.float)
        (D.field "dur" D.float)
        (D.field "loc" D.string)
        (D.field "cast" (D.list actor))
        (D.field "beats" (D.list beat))


actor : Decoder Actor
actor =
    D.map5 Actor
        (D.field "id" D.string)
        (D.field "at" point)
        (optional "facing" D.float 1)
        (optional "pose" D.string "idle")
        (optional "expr" D.string "neutral")


beat : Decoder Beat
beat =
    D.succeed Beat
        |> andMap (D.field "t" D.float)
        |> andMap (optional "dur" D.float 0)
        |> andMap (D.maybe (D.field "who" D.string))
        |> andMap (D.maybe (D.field "act" D.string))
        |> andMap (D.maybe (D.field "to" point))
        |> andMap (D.maybe (D.field "pose" D.string))
        |> andMap (D.maybe (D.field "expr" D.string))
        |> andMap (D.maybe (D.field "face" D.float))
        |> andMap (D.maybe (D.field "say" say))
        |> andMap (D.maybe (D.field "cam" cam))


say : Decoder Say
say =
    D.map4 Say
        (optional "kind" D.string "normal")
        (D.field "lines" (D.list D.string))
        (D.field "w" D.float)
        (D.field "h" D.float)


cam : Decoder Cam
cam =
    D.map2 Cam
        (D.field "to" point)
        (optional "zoom" D.float 1)


point : Decoder ( Float, Float )
point =
    D.map2 Tuple.pair (D.index 0 D.float) (D.index 1 D.float)


optional : String -> Decoder a -> a -> Decoder a
optional key dec fallback =
    D.maybe (D.field key dec) |> D.map (Maybe.withDefault fallback)


andMap : Decoder a -> Decoder (a -> b) -> Decoder b
andMap va vf =
    D.map2 (\a f -> f a) va vf
