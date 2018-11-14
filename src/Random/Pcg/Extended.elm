module Random.Pcg.Extended exposing
    ( config
    , step, initialSeed
    , Generator, bool, int, float, oneIn, sample
    , pair, list, maybe, choice, choices, frequency
    , constant, map, map2, map3, map4, map5, andMap, andThen, filter
    , Seed, independentSeed, toJson, fromJson
    , minInt, maxInt
    )

{-| This is an extended version of the Pcg random generator.
It offers k dimensional equidistributed random numbers.

It has a larger space cost than the normal Pcg version, but it also offers a much higher period

@docs config


# Getting Started

@docs step, initialSeed


# Basic Generators

@docs Generator, bool, int, float, oneIn, sample


# Combining Generators

@docs pair, list, maybe, choice, choices, frequency


# Custom Generators

@docs constant, map, map2, map3, map4, map5, andMap, andThen, filter


# Working With Seeds

@docs Seed, independentSeed, toJson, fromJson


# Constants

@docs minInt, maxInt

-}

import Array exposing (Array)
import Bitwise
import Internal.Pcg
import Json.Decode
import Json.Encode
import Random.General as RNG exposing (Config(..))



{- NOTE: this implementation tries to follow the description in the Pcg paper
   (http://www.pcg-random.org/paper.html).
   Special attention should be given to section 4.3.4 and 7.1.
   However, I didn't fully understand how exactely to implement the advance step of the extension array.
-}


{-| -}
type Seed
    = Seed { extension : Array Int, base : Internal.Pcg.Seed }


{-| -}
type alias Generator a =
    RNG.Generator Seed a


{-| Seed this generator with some random data.
Best get this via a flag from `window.crypto.getRandomValues(..)`.

The more random integers you provide, the longer the period gets.

This is based on section 7.1 from [the PCG paper](http://www.pcg-random.org/paper.html)
Since the PCG generator used as a base is the RXS-M-XS variant (section 6.3.4),
The extended generator will have a period of `2^((List.length extendedSeed + 1)*32)`

If your `extendedSeed` list has a length that is a power of two, the performance will be a bit better.

-}
initialSeed : Int -> List Int -> Seed
initialSeed baseSeed extendedSeed =
    Seed { extension = Array.fromList extendedSeed, base = Internal.Pcg.initialSeed baseSeed }


{-| This gives you an independant seed.

TODO: how sound is this function?

-}
independentSeed : Generator Seed
independentSeed =
    RNG.generator <|
        \seed0 ->
            let
                gen =
                    int 0 0xFFFFFFFF

                ( ( state, b, c ), Seed seed1 ) =
                    step (map3 (\x y z -> ( x, y, z )) gen gen gen) seed0

                {--
                Although it probably doesn't hold water theoretically, xor two
                random numbers to make an increment less likely to be
                pathological. Then make sure that it's odd, which is required.
                Finally step it once before use.
                --}
                incr =
                    Bitwise.xor b c |> Bitwise.or 1 |> Bitwise.shiftRightZfBy 0
            in
            ( Seed seed1, Seed { extension = seed1.extension, base = Internal.Pcg.next <| Internal.Pcg.Seed state incr } )


{-| The config for the PCG-extended variant
-}
config : Config Seed
config =
    RNG.makeConfig next peel


{-| -}
int : Int -> Int -> Generator Int
int =
    RNG.int config


{-| -}
float : Float -> Float -> Generator Float
float =
    RNG.float config


next : Seed -> Seed
next (Seed s) =
    let
        ((Internal.Pcg.Seed baseState _) as newBase) =
            Internal.Pcg.next s.base
    in
    Seed
        { base = newBase
        , extension =
            if baseState == 0 then
                -- only advance the extension if we cross the all zero state for the base generator
                incrementExtension s.extension

            else
                s.extension
        }


peel : Seed -> Int
peel (Seed s) =
    -- As in section 7.1 of the paper
    let
        baseOut =
            Internal.Pcg.peel s.base

        ( randIndex, _ ) =
            RNG.step (Internal.Pcg.int 0 (Array.length s.extension - 1)) s.base

        extension =
            Array.get randIndex s.extension |> Maybe.withDefault 0
    in
    Bitwise.xor baseOut extension
        |> Bitwise.shiftRightZfBy 0


incrementExtension : Array Int -> Array Int
incrementExtension arr =
    -- Increment as described in section 4.3.4 of the PCG paper
    incrementExtensionHelp 0 0 arr


incrementExtensionHelp : Int -> Int -> Array Int -> Array Int
incrementExtensionHelp index prev arr =
    if prev == 0 then
        case Array.get index arr of
            Just elem ->
                let
                    newElem =
                        -- TODO: is this the right way to increment?
                        -- Or should it use a different increment for each element of the array?
                        elem + 1013904223 |> Bitwise.shiftRightZfBy 0
                in
                incrementExtensionHelp (index + 1) newElem (Array.set index newElem arr)

            Nothing ->
                arr

    else
        arr


{-| -}
step : Generator a -> Seed -> ( a, Seed )
step =
    RNG.step


{-| -}
bool : Generator Bool
bool =
    RNG.bool config


{-| -}
maxInt : Int
maxInt =
    RNG.maxInt


{-| -}
minInt : Int
minInt =
    RNG.minInt


{-| -}
pair : Generator a -> Generator b -> Generator ( a, b )
pair =
    RNG.pair


{-| -}
list : Int -> Generator a -> Generator (List a)
list =
    RNG.list


{-| -}
constant : a -> Generator a
constant =
    RNG.constant


{-| -}
map : (a -> b) -> Generator a -> Generator b
map =
    RNG.map


{-| -}
map2 : (a -> b -> c) -> Generator a -> Generator b -> Generator c
map2 =
    RNG.map2


{-| -}
map3 : (a -> b -> c -> d) -> Generator a -> Generator b -> Generator c -> Generator d
map3 =
    RNG.map3


{-| -}
map4 : (a -> b -> c -> d -> e) -> Generator a -> Generator b -> Generator c -> Generator d -> Generator e
map4 =
    RNG.map4


{-| -}
map5 : (a -> b -> c -> d -> e -> f) -> Generator a -> Generator b -> Generator c -> Generator d -> Generator e -> Generator f
map5 =
    RNG.map5


{-| -}
andMap : Generator a -> Generator (a -> b) -> Generator b
andMap =
    RNG.andMap


{-| -}
andThen : (a -> Generator b) -> Generator a -> Generator b
andThen =
    RNG.andThen


{-| -}
filter : (a -> Bool) -> Generator a -> Generator a
filter =
    RNG.filter


{-| -}
oneIn : Int -> Generator Bool
oneIn =
    RNG.oneIn config


{-| -}
sample : List a -> Generator (Maybe a)
sample =
    RNG.sample config


{-| -}
choice : a -> a -> Generator a
choice =
    RNG.choice config


{-| -}
choices : Generator a -> List (Generator a) -> Generator a
choices =
    RNG.choices config


{-| -}
frequency : ( Float, Generator a ) -> List ( Float, Generator a ) -> Generator a
frequency =
    RNG.frequency config


{-| -}
maybe : Generator Bool -> Generator a -> Generator (Maybe a)
maybe =
    RNG.maybe


{-| -}
toJson : Seed -> Json.Encode.Value
toJson (Seed s) =
    Json.Encode.list identity
        [ Internal.Pcg.toJson s.base
        , Json.Encode.list Json.Encode.int (Array.toList s.extension)
        ]


{-| -}
fromJson : Json.Decode.Decoder Seed
fromJson =
    Json.Decode.map2 (\b e -> Seed { base = b, extension = e })
        (Json.Decode.index 0 Internal.Pcg.fromJson)
        (Json.Decode.index 1 (Json.Decode.list Json.Decode.int |> Json.Decode.map Array.fromList))
