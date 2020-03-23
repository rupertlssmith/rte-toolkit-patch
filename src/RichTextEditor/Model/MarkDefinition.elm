module RichTextEditor.Model.MarkDefinition exposing
    ( MarkDefinition, markDefinition, MarkToHtml, HtmlToMark, name, toHtmlNode, fromHtmlNode
    , defaultHtmlToMark, defaultMarkDefinition, defaultMarkToHtml
    )

{-| A mark definition describes how to encode and decode a mark.

@docs MarkDefinition, markDefinition, MarkToHtml, HtmlToMark, name, toHtmlNode, fromHtmlNode

-}

import RichTextEditor.Model.Attribute exposing (Attribute(..))
import RichTextEditor.Model.HtmlNode exposing (HtmlNode(..))
import RichTextEditor.Model.Internal as Internal


{-| A mark definition defines how a mark is encoded an decoded.
-}
type alias MarkDefinition =
    Internal.MarkDefinition


{-| Type alias for a mark encoding function: `Mark -> Array HtmlNode -> HtmlNode`

    codeToHtmlNode : MarkToHtml
    codeToHtmlNode _ children =
        ElementNode "code" [] children

-}
type alias MarkToHtml =
    Internal.MarkToHtml


{-| Type alias for a mark decoding function: `MarkDefinition -> HtmlNode -> Maybe ( Mark, Array HtmlNode )`

    htmlNodeToCode : HtmlToMark
    htmlNodeToCode definition node =
        case node of
            ElementNode name _ children ->
                if name == 'code' then
                    Just ( mark def [], children )

                else
                    Nothing

            _ ->
                Nothing

-}
type alias HtmlToMark =
    Internal.HtmlToMark


{-| Defines a mark. The arguments are as follows:

  - `name` - The unique name for this mark. This should be something like 'bold' or 'link'.

  - `encode function` - The function that converts the mark to html. This is used in rendering,
    DOM validation, and path translation.

  - `decode function` - The function that converts html to marks. This is used in things
    like paste to determine the editor nodes from html.

```
    code : MarkDefinition
    code =
        markDefinition "code" codeToHtmlNode htmlNodeToCode
```

-}
markDefinition : String -> MarkToHtml -> HtmlToMark -> MarkDefinition
markDefinition name_ toHtml fromHtml =
    Internal.MarkDefinition
        { name = name_
        , toHtmlNode = toHtml
        , fromHtmlNode = fromHtml
        }


{-| Name of the mark this mark definition defines.

    name code
    --> "code"

-}
name : MarkDefinition -> String
name definition_ =
    case definition_ of
        Internal.MarkDefinition c ->
            c.name


{-| Function which encodes a mark to Html
-}
toHtmlNode : MarkDefinition -> MarkToHtml
toHtmlNode definition_ =
    case definition_ of
        Internal.MarkDefinition c ->
            c.toHtmlNode


{-| Function which decodes a mark from Html
-}
fromHtmlNode : MarkDefinition -> HtmlToMark
fromHtmlNode definition_ =
    case definition_ of
        Internal.MarkDefinition c ->
            c.fromHtmlNode


defaultMarkDefinition : String -> MarkDefinition
defaultMarkDefinition name_ =
    markDefinition name_ defaultMarkToHtml (defaultHtmlToMark name_)


defaultHtmlToMark : String -> HtmlToMark
defaultHtmlToMark htmlTag def node =
    case node of
        ElementNode name_ _ children ->
            if name_ == htmlTag then
                Just ( Internal.mark def [], children )

            else
                Nothing

        _ ->
            Nothing


defaultMarkToHtml : MarkToHtml
defaultMarkToHtml mark_ children =
    ElementNode (Internal.nameFromMark mark_)
        (List.filterMap
            (\attr ->
                case attr of
                    StringAttribute k v ->
                        Just ( k, v )

                    _ ->
                        Nothing
            )
            (Internal.attributesFromMark mark_)
        )
        children