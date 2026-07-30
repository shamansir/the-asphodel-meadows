module HttpDate exposing (parse)

{-| Parse an RFC 7231 `Date` response header into unix milliseconds.

Used for clock-skew correction (ARCHITECTURE.md §1). A viewer whose machine
clock is four minutes fast would otherwise silently watch a different scene
than everyone else, which quietly breaks the one promise the project makes.

    parse "Thu, 30 Jul 2026 21:04:11 GMT" == Just 1785445451000

-}


parse : String -> Maybe Int
parse raw =
    case String.words (String.trim raw) of
        _ :: dayS :: monS :: yearS :: timeS :: _ ->
            Maybe.map4
                (\d m y ( hh, mm, ss ) ->
                    ((daysFromCivil y m d * 86400) + (hh * 3600) + (mm * 60) + ss) * 1000
                )
                (String.toInt dayS)
                (month monS)
                (String.toInt yearS)
                (time timeS)

        _ ->
            Nothing


time : String -> Maybe ( Int, Int, Int )
time s =
    case String.split ":" s |> List.map String.toInt of
        [ Just hh, Just mm, Just ss ] ->
            Just ( hh, mm, ss )

        _ ->
            Nothing


month : String -> Maybe Int
month s =
    case s of
        "Jan" -> Just 1
        "Feb" -> Just 2
        "Mar" -> Just 3
        "Apr" -> Just 4
        "May" -> Just 5
        "Jun" -> Just 6
        "Jul" -> Just 7
        "Aug" -> Just 8
        "Sep" -> Just 9
        "Oct" -> Just 10
        "Nov" -> Just 11
        "Dec" -> Just 12
        _ -> Nothing


{-| Howard Hinnant's days-from-civil. Valid for any proleptic Gregorian date;
we only ever feed it years well past 1970, so the negative-era branch is
theoretical.
-}
daysFromCivil : Int -> Int -> Int -> Int
daysFromCivil year m d =
    let
        y =
            if m <= 2 then
                year - 1

            else
                year

        era =
            (if y >= 0 then
                y

             else
                y - 399
            )
                // 400

        yoe =
            y - era * 400

        mp =
            if m > 2 then
                m - 3

            else
                m + 9

        doy =
            ((153 * mp + 2) // 5) + d - 1

        doe =
            yoe * 365 + (yoe // 4) - (yoe // 100) + doy
    in
    era * 146097 + doe - 719468
