port module Main exposing (..)

import Browser
import Element.WithContext as Ele exposing (..)
import Element.WithContext.Background as Background
import Element.WithContext.Border as Border
import Element.WithContext.Events as Events
import Element.WithContext.Font as Font
import Element.WithContext.Input as Input
import FeatherIcons
import Html.Attributes as Attr
import List


port switchAudio : String -> Cmd msg


main : Program () Model Msg
main =
    Browser.element
        { init = init
        , view = \model -> view configuration model
        , update = update
        , subscriptions = subscriptions
        }


type Msg
    = InputMsg String
    | ToggleMode


type alias Configuration =
    { debugging : Bool
    , palette : Palette
    , maxWidth : Int
    , maxHeight : Int
    }


type alias Context =
    { conf : Configuration
    , palette : Palette
    }


type alias Element msg =
    Ele.Element Context msg


type alias Attribute msg =
    Ele.Attribute Context msg


type alias Attr decorative msg =
    Ele.Attr Context decorative msg


configuration : Configuration
configuration =
    { debugging = False
    , palette = paletteTmp
    , maxWidth = 1800
    , maxHeight = 1800
    }


type alias Palette =
    { primary : Color
    , secondary : Color
    , external : Color
    , background : Color
    , onRight : Color
    , onPrimary : Color
    , onBackground : Color
    , error : Color
    }


paletteTmp : Palette
paletteTmp =
    { primary = rgb255 230 230 230
    , secondary = rgb255 80 181 237
    , external = rgb255 59 62 64
    , background = rgb255 40 40 40
    , onRight = rgb255 253 251 247
    , onPrimary = rgb255 30 144 255
    , onBackground = rgb255 175 175 175
    , error = rgb255 255 46 46
    }


type Mode
    = Mic
    | MicOff


type alias Post =
    { index : Int
    , word : String
    }


type alias Model =
    { inputMsg : String
    , wordsLenth : Int
    , postsI : List Post
    , text : String
    , audioText : String
    , mode : Mode
    }


init : () -> ( Model, Cmd Msg )
init _ =
    let
        model =
            { inputMsg = ""
            , wordsLenth = 0
            , postsI = []
            , text = textmsg
            , audioText = ">"
            , mode = Mic
            }
    in
    ( model, Cmd.none )


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        InputMsg val ->
            inputUpdate val model

        ToggleMode ->
            ( { model
                | mode =
                    case model.mode of
                        Mic ->
                            MicOff

                        MicOff ->
                            Mic
              }
            , Cmd.none
            )


inputUpdate val model =
    let
        wordsLenth =
            List.length (String.words val)

        posts =
            List.indexedMap (\i s -> Post i s) (wordFilter model.text)

        postsI =
            let
                split =
                    String.words (String.toLower val)

                matchesAllTerms entry =
                    let
                        lowerEntry =
                            String.toLower entry.word

                        matchesTerm term =
                            let
                                lowerTerm =
                                    String.toLower term
                            in
                            lowerTerm == lowerEntry
                    in
                    List.any matchesTerm split
            in
            List.filter matchesAllTerms posts
    in
    ( { model | inputMsg = val, wordsLenth = wordsLenth, postsI = postsI }, Cmd.none )


view conf model =
    layoutWith (contextBuilder conf)
        { options = options }
        (mainAttrs conf model)
        (viewPage conf model)


viewPage conf model =
    column [ width fill ]
        [ target_phrase conf model
        , viewText conf model
        , inputText conf model
        , audioText conf model
        ]


viewText conf model =
    el
        [ centerX
        , moveDown 200
        ]
    <|
        row []
            [ Ele.paragraph [ width (px 1000), height (px 100), padding 10, Ele.scrollbarY ]
                (List.indexedMap
                    (\i s ->
                        el
                            [ if i < model.wordsLenth && isRight i model.postsI then
                                Font.color conf.palette.onRight

                              else if i < model.wordsLenth && isErr i model.postsI then
                                Font.color conf.palette.error

                              else
                                noneAttr
                            , if i == model.wordsLenth then
                                Font.underline

                              else
                                noneAttr
                            ]
                        <|
                            Ele.text (s ++ " ")
                    )
                    (wordFilter model.text)
                )
            ]


isRight i posts =
    List.any (\s -> i == s.index) posts


isErr i posts =
    List.any (\s -> i /= s.index) posts


inputText conf model =
    row [ centerX, moveDown 250 ]
        [ Input.text
            [ width (px 500)
            , spacing 16
            ]
            { onChange = InputMsg
            , text = model.inputMsg
            , placeholder = Nothing
            , label = Input.labelAbove [] (text "")
            }
        ]


target_phrase conf model =
    row [ moveRight 820, moveDown 190, spacing 80 ]
        [ Input.button [ id "record" ]
            { onPress = Just <| ToggleMode
            , label =
                atomIcon
                    [ transition "transform 0.1s"
                    , mouseOver
                        [ scale 1.2 ]
                    ]
                    { shape =
                        if model.mode == Mic then
                            FeatherIcons.micOff

                        else
                            FeatherIcons.mic
                    , color =
                        if model.mode == Mic then
                            .primary

                        else
                            .onPrimary
                    , size = 30
                    , fill = False
                    }
            }
        , Input.button [ id "play" ]
            { onPress = Nothing
            , label =
                atomIcon
                    [ transition "transform 0.1s"
                    , mouseOver
                        [ scale 1.2 ]
                    ]
                    { shape = FeatherIcons.play
                    , color = .primary
                    , size = 30
                    , fill = False
                    }
            }
        , Input.button [ id "save" ]
            { onPress = Nothing
            , label =
                atomIcon
                    [ transition "transform 0.1s"
                    , mouseOver
                        [ scale 1.2 ]
                    ]
                    { shape = FeatherIcons.save
                    , color = .primary
                    , size = 30
                    , fill = False
                    }
            }
        ]


audioText conf model =
    column [ centerX, moveDown 280, spacing 10 ]
        [ text "ai infered: "
        , text model.audioText
        ]


atomIcon :
    List (Attribute msg)
    -> { color : Palette -> Color, fill : Bool, shape : FeatherIcons.Icon, size : Float }
    -> Element msg
atomIcon attrs { shape, color, size, fill } =
    elementWithContext <|
        \c ->
            el attrs <|
                html <|
                    (shape
                        |> FeatherIcons.withSize size
                        |> FeatherIcons.withStrokeWidth 1
                        |> FeatherIcons.toHtml
                            (Attr.style "stroke" (colorToCssString (color c.palette))
                                :: (if fill && shape /= FeatherIcons.arrowUp && shape /= FeatherIcons.chevronLeft && shape /= FeatherIcons.chevronRight then
                                        [ Attr.style "fill" (colorToCssString (changeAlpha 1 (color c.palette))) ]
                                        -- [ Html.Attributes.style "fill" "rgb(255, 111 ,255)" ]

                                    else
                                        []
                                   )
                            )
                    )


elementWithContext : (Context -> Element msg) -> Element msg
elementWithContext =
    with identity


colorToCssString : Color -> String
colorToCssString color =
    -- Copied from https://github.com/avh4/elm-color/blob/1.0.0/src/Color.elm#L555
    let
        { red, green, blue, alpha } =
            toRgb color

        pct x =
            ((x * 10000) |> round |> toFloat) / 100

        roundTo x =
            ((x * 1000) |> round |> toFloat) / 1000
    in
    String.concat
        [ "rgba("
        , String.fromFloat (pct red)
        , "%,"
        , String.fromFloat (pct green)
        , "%,"
        , String.fromFloat (pct blue)
        , "%,"
        , String.fromFloat (roundTo alpha)
        , ")"
        ]


changeAlpha : Float -> Color -> Color
changeAlpha alpha color =
    let
        { red, green, blue } =
            toRgb color
    in
    rgba red green blue alpha


mainAttrs : Configuration -> Model -> List (Attribute Msg)
mainAttrs conf model =
    let
        c =
            contextBuilder conf
    in
    [ Font.size 28
    , Font.color c.palette.onBackground
    , Font.family [ Font.typeface "Liberation Sans", Font.sansSerif ]
    , Font.unitalicized
    , Background.color c.palette.background
    , transition "background-color 2s"
    ]


noneAttr : Attribute msg
noneAttr =
    htmlAttribute <| Attr.style "" ""


id : String -> Attribute msg
id i =
    htmlAttribute <| Attr.id i


transition : String -> Attribute msg
transition string =
    style "transition" string


style : String -> String -> Attribute msg
style string1 string2 =
    htmlAttribute <| Attr.style string1 string2


contextBuilder : Configuration -> Context
contextBuilder conf =
    { conf = conf
    , palette = conf.palette
    }


options : List Option
options =
    [ focusStyle { borderColor = Just (rgb255 0 191 255), backgroundColor = Nothing, shadow = Nothing } ]


wordFilter text =
    let
        chars =
            "!.,?–-"

        characters char =
            let
                isChar c =
                    char /= c
            in
            String.all isChar chars
    in
    String.filter characters (String.toLower text)
        |> String.words


textEn =
    """to provide a global context available while building the view. If you're not familiar with elm-ui, you should try it and only come back to this library when you have a problem to solve."""


textmsg =
    """
    Я проснулся от лая соседской собачки. Гнусная тварь, она всегда меня
    будит. Как я ее ненавижу! Почему я должен пробуждаться именно от
    звуков, которые издает это гадкое отродье? Надо пойти прогуляться,
    успокоиться и как-то отвлечься от острого желания поджечь соседский дом.
    Какая собачка, такие и хозяева. Вечно в мою жизнь вползают какие-то гады
    и стараются меня достать. Нервно одеваюсь. Опять куда-то запропастились
    мои тапки. Где вы, изворотливые ублюдки? Найду – выброшу!
    На улице туман, сырость. Я шел по скользкой тропинке через угрюмый
    лес. Почти все листья уже опали, обнажив серые стволы полумертвых
    деревьев. Почему я живу посреди этого мрачного болота? Достаю сигарету.
    Вроде не хочется курить, но старая привычка говорит, что надо. Надо? С
    каких это пор сигарета стала для меня как обязанность? Да, довольно
    """


subscriptions : Model -> Sub Msg
subscriptions model =
    Sub.none
