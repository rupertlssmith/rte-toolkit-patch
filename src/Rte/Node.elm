module Rte.Node exposing
    ( EditorFragment(..)
    , EditorNode(..)
    , Iterator
    , findAncestor
    , findBackwardFrom
    , findBackwardFromExclusive
    , findForwardFrom
    , findForwardFromExclusive
    , findTextBlockNodeAncestor
    , foldl
    , foldr
    , indexedFoldl
    , indexedFoldr
    , indexedMap
    , isSelectable
    , map
    , next
    , nodeAt
    , previous
    , removeInRange
    , removeNodeAndEmptyParents
    , replace
    , replaceWithFragment
    , splitBlockAtPathAndOffset
    )

import Array exposing (Array)
import Array.Extra
import Rte.Model exposing (ChildNodes(..), EditorBlockNode, EditorInlineLeaf(..), HtmlNode(..), NodePath, selectableMark)


type EditorNode
    = BlockNodeWrapper EditorBlockNode
    | InlineLeafWrapper EditorInlineLeaf


type EditorFragment
    = BlockNodeFragment (Array EditorBlockNode)
    | InlineLeafFragment (Array EditorInlineLeaf)


findLastPath : EditorBlockNode -> ( NodePath, EditorNode )
findLastPath node =
    case node.childNodes of
        BlockArray a ->
            let
                lastIndex =
                    Array.length a - 1
            in
            case Array.get lastIndex a of
                Nothing ->
                    ( [], BlockNodeWrapper node )

                Just b ->
                    let
                        ( p, n ) =
                            findLastPath b
                    in
                    ( lastIndex :: p, n )

        InlineLeafArray a ->
            let
                lastIndex =
                    Array.length a - 1
            in
            case Array.get lastIndex a of
                Nothing ->
                    ( [], BlockNodeWrapper node )

                Just l ->
                    ( [ lastIndex ], InlineLeafWrapper l )

        Leaf ->
            ( [], BlockNodeWrapper node )


type alias Iterator =
    NodePath -> EditorBlockNode -> Maybe ( NodePath, EditorNode )


previous : Iterator
previous path node =
    case path of
        [] ->
            Nothing

        [ x ] ->
            let
                prevIndex =
                    x - 1
            in
            case node.childNodes of
                BlockArray a ->
                    case Array.get prevIndex a of
                        Nothing ->
                            Just ( [], BlockNodeWrapper node )

                        Just b ->
                            let
                                ( p, n ) =
                                    findLastPath b
                            in
                            Just ( prevIndex :: p, n )

                InlineLeafArray a ->
                    case Array.get prevIndex a of
                        Nothing ->
                            Just ( [], BlockNodeWrapper node )

                        Just l ->
                            Just ( [ prevIndex ], InlineLeafWrapper l )

                Leaf ->
                    Just ( [], BlockNodeWrapper node )

        x :: xs ->
            case node.childNodes of
                BlockArray a ->
                    case Array.get x a of
                        Nothing ->
                            Nothing

                        Just b ->
                            case previous xs b of
                                Nothing ->
                                    Just ( [ x ], BlockNodeWrapper b )

                                Just ( p, n ) ->
                                    Just ( x :: p, n )

                InlineLeafArray a ->
                    case Array.get (x - 1) a of
                        Nothing ->
                            Just ( [], BlockNodeWrapper node )

                        Just l ->
                            Just ( [ x - 1 ], InlineLeafWrapper l )

                Leaf ->
                    Nothing


next : Iterator
next path node =
    case path of
        [] ->
            case node.childNodes of
                BlockArray a ->
                    case Array.get 0 a of
                        Nothing ->
                            Nothing

                        Just b ->
                            Just ( [ 0 ], BlockNodeWrapper b )

                InlineLeafArray a ->
                    case Array.get 0 a of
                        Nothing ->
                            Nothing

                        Just b ->
                            Just ( [ 0 ], InlineLeafWrapper b )

                Leaf ->
                    Nothing

        x :: xs ->
            case node.childNodes of
                BlockArray a ->
                    case Array.get x a of
                        Nothing ->
                            Nothing

                        Just b ->
                            case next xs b of
                                Nothing ->
                                    case Array.get (x + 1) a of
                                        Nothing ->
                                            Nothing

                                        Just bNext ->
                                            Just ( [ x + 1 ], BlockNodeWrapper bNext )

                                Just ( p, n ) ->
                                    Just ( x :: p, n )

                InlineLeafArray a ->
                    case Array.get (x + 1) a of
                        Nothing ->
                            Nothing

                        Just b ->
                            Just ( [ x + 1 ], InlineLeafWrapper b )

                Leaf ->
                    Nothing


findForwardFrom : (NodePath -> EditorNode -> Bool) -> NodePath -> EditorBlockNode -> Maybe ( NodePath, EditorNode )
findForwardFrom =
    findNodeFrom next


findForwardFromExclusive : (NodePath -> EditorNode -> Bool) -> NodePath -> EditorBlockNode -> Maybe ( NodePath, EditorNode )
findForwardFromExclusive =
    findNodeFromExclusive next


findBackwardFrom : (NodePath -> EditorNode -> Bool) -> NodePath -> EditorBlockNode -> Maybe ( NodePath, EditorNode )
findBackwardFrom =
    findNodeFrom previous


findBackwardFromExclusive : (NodePath -> EditorNode -> Bool) -> NodePath -> EditorBlockNode -> Maybe ( NodePath, EditorNode )
findBackwardFromExclusive =
    findNodeFromExclusive previous


isSelectable : EditorNode -> Bool
isSelectable node =
    case node of
        BlockNodeWrapper bn ->
            List.member selectableMark bn.parameters.marks

        InlineLeafWrapper ln ->
            case ln of
                TextLeaf _ ->
                    True

                InlineLeaf p ->
                    List.member selectableMark p.marks


findNodeFromExclusive : Iterator -> (NodePath -> EditorNode -> Bool) -> NodePath -> EditorBlockNode -> Maybe ( NodePath, EditorNode )
findNodeFromExclusive iterator pred path node =
    case iterator path node of
        Nothing ->
            Nothing

        Just ( nextPath, _ ) ->
            findNodeFrom iterator pred nextPath node


findNodeFrom : Iterator -> (NodePath -> EditorNode -> Bool) -> NodePath -> EditorBlockNode -> Maybe ( NodePath, EditorNode )
findNodeFrom iterator pred path node =
    case nodeAt path node of
        Just n ->
            if pred path n then
                Just ( path, n )

            else
                findNodeFromExclusive iterator pred path node

        Nothing ->
            Nothing


map : (EditorNode -> EditorNode) -> EditorNode -> EditorNode
map func node =
    let
        applied =
            func node
    in
    case applied of
        BlockNodeWrapper blockNode ->
            BlockNodeWrapper
                { blockNode
                    | childNodes =
                        case blockNode.childNodes of
                            BlockArray a ->
                                BlockArray <|
                                    Array.map
                                        (\v ->
                                            case map func (BlockNodeWrapper v) of
                                                BlockNodeWrapper b ->
                                                    b

                                                _ ->
                                                    v
                                        )
                                        a

                            InlineLeafArray a ->
                                InlineLeafArray <|
                                    Array.map
                                        (\v ->
                                            case map func (InlineLeafWrapper v) of
                                                InlineLeafWrapper b ->
                                                    b

                                                _ ->
                                                    v
                                        )
                                        a

                            Leaf ->
                                Leaf
                }

        InlineLeafWrapper inlineLeaf ->
            InlineLeafWrapper inlineLeaf


indexedMap : (NodePath -> EditorNode -> EditorNode) -> EditorNode -> EditorNode
indexedMap =
    indexedMapRec []


indexedMapRec : NodePath -> (NodePath -> EditorNode -> EditorNode) -> EditorNode -> EditorNode
indexedMapRec path func node =
    let
        applied =
            func path node
    in
    case applied of
        BlockNodeWrapper blockNode ->
            BlockNodeWrapper
                { blockNode
                    | childNodes =
                        case blockNode.childNodes of
                            BlockArray a ->
                                BlockArray <|
                                    Array.indexedMap
                                        (\i v ->
                                            case indexedMapRec (path ++ [ i ]) func (BlockNodeWrapper v) of
                                                BlockNodeWrapper b ->
                                                    b

                                                _ ->
                                                    v
                                        )
                                        a

                            InlineLeafArray a ->
                                InlineLeafArray <|
                                    Array.indexedMap
                                        (\i v ->
                                            case indexedMapRec (path ++ [ i ]) func (InlineLeafWrapper v) of
                                                InlineLeafWrapper b ->
                                                    b

                                                _ ->
                                                    v
                                        )
                                        a

                            Leaf ->
                                Leaf
                }

        InlineLeafWrapper inlineLeaf ->
            InlineLeafWrapper inlineLeaf


foldr : (EditorNode -> b -> b) -> b -> EditorNode -> b
foldr func acc node =
    func
        node
        (case node of
            BlockNodeWrapper blockNode ->
                let
                    children =
                        case blockNode.childNodes of
                            Leaf ->
                                Array.empty

                            InlineLeafArray a ->
                                Array.map InlineLeafWrapper a

                            BlockArray a ->
                                Array.map BlockNodeWrapper a
                in
                Array.foldr
                    (\childNode agg ->
                        foldr func agg childNode
                    )
                    acc
                    children

            InlineLeafWrapper _ ->
                acc
        )


foldl : (EditorNode -> b -> b) -> b -> EditorNode -> b
foldl func acc node =
    case node of
        BlockNodeWrapper blockNode ->
            let
                children =
                    case blockNode.childNodes of
                        Leaf ->
                            Array.empty

                        InlineLeafArray a ->
                            Array.map InlineLeafWrapper a

                        BlockArray a ->
                            Array.map BlockNodeWrapper a
            in
            Array.foldl
                (\childNode agg ->
                    foldl func agg childNode
                )
                (func node acc)
                children

        InlineLeafWrapper _ ->
            func node acc


indexedFoldr : (NodePath -> EditorNode -> b -> b) -> b -> EditorNode -> b
indexedFoldr =
    indexedFoldrRec []


indexedFoldrRec : NodePath -> (NodePath -> EditorNode -> b -> b) -> b -> EditorNode -> b
indexedFoldrRec path func acc node =
    func
        path
        node
        (case node of
            BlockNodeWrapper blockNode ->
                let
                    children =
                        Array.indexedMap Tuple.pair <|
                            case blockNode.childNodes of
                                Leaf ->
                                    Array.empty

                                InlineLeafArray a ->
                                    Array.map InlineLeafWrapper a

                                BlockArray a ->
                                    Array.map BlockNodeWrapper a
                in
                Array.foldr
                    (\( index, childNode ) agg ->
                        indexedFoldrRec (path ++ [ index ]) func agg childNode
                    )
                    acc
                    children

            InlineLeafWrapper _ ->
                acc
        )


indexedFoldl : (NodePath -> EditorNode -> b -> b) -> b -> EditorNode -> b
indexedFoldl =
    indexedFoldlRec []


indexedFoldlRec : NodePath -> (NodePath -> EditorNode -> b -> b) -> b -> EditorNode -> b
indexedFoldlRec path func acc node =
    case node of
        BlockNodeWrapper blockNode ->
            let
                children =
                    Array.indexedMap Tuple.pair <|
                        case blockNode.childNodes of
                            Leaf ->
                                Array.empty

                            InlineLeafArray a ->
                                Array.map InlineLeafWrapper a

                            BlockArray a ->
                                Array.map BlockNodeWrapper a
            in
            Array.foldl
                (\( index, childNode ) agg ->
                    indexedFoldlRec (path ++ [ index ]) func agg childNode
                )
                (func path node acc)
                children

        InlineLeafWrapper _ ->
            func path node acc



{- replaceNodeWithFragment replaces the node at the node path with the given fragment -}


replaceWithFragment : NodePath -> EditorFragment -> EditorBlockNode -> Result String EditorBlockNode
replaceWithFragment path fragment root =
    case path of
        [] ->
            Err "Invalid path"

        [ x ] ->
            case root.childNodes of
                BlockArray a ->
                    case fragment of
                        BlockNodeFragment blocks ->
                            Ok
                                { root
                                    | childNodes =
                                        BlockArray
                                            (Array.append
                                                (Array.append
                                                    (Array.Extra.sliceUntil x a)
                                                    blocks
                                                )
                                                (Array.Extra.sliceFrom (x + 1) a)
                                            )
                                }

                        InlineLeafFragment _ ->
                            Err "I cannot replace a block fragment with an inline leaf fragment"

                InlineLeafArray a ->
                    case fragment of
                        InlineLeafFragment leaves ->
                            Ok
                                { root
                                    | childNodes =
                                        InlineLeafArray
                                            (Array.append
                                                (Array.append
                                                    (Array.Extra.sliceUntil x a)
                                                    leaves
                                                )
                                                (Array.Extra.sliceFrom (x + 1) a)
                                            )
                                }

                        BlockNodeFragment _ ->
                            Err "I cannot replace an inline fragment with an block fragment"

                Leaf ->
                    Err "Not implemented"

        x :: xs ->
            case root.childNodes of
                BlockArray a ->
                    case Array.get x a of
                        Nothing ->
                            Err "I received an invalid path, I can't find a block node at the given index."

                        Just node ->
                            case replaceWithFragment xs fragment node of
                                Ok n ->
                                    Ok { root | childNodes = BlockArray (Array.set x n a) }

                                Err v ->
                                    Err v

                InlineLeafArray _ ->
                    Err "I received an invalid path, I reached an inline leaf array but I still have more path left."

                Leaf ->
                    Err "I received an invalid path, I am on a leaf node, but I still have more path left."



{- replaceNode replaces the node at the nodepath with the given editor node -}


replace : NodePath -> EditorNode -> EditorBlockNode -> Result String EditorBlockNode
replace path node root =
    case path of
        [] ->
            case node of
                BlockNodeWrapper n ->
                    Ok n

                InlineLeafWrapper _ ->
                    Err "I cannot replace a block node with an inline leaf."

        _ ->
            let
                fragment =
                    case node of
                        BlockNodeWrapper n ->
                            BlockNodeFragment <| Array.fromList [ n ]

                        InlineLeafWrapper n ->
                            InlineLeafFragment <| Array.fromList [ n ]
            in
            replaceWithFragment path fragment root


{-| Finds the closest node ancestor with inline content.
-}
findTextBlockNodeAncestor : NodePath -> EditorBlockNode -> Maybe ( NodePath, EditorBlockNode )
findTextBlockNodeAncestor =
    findAncestor
        (\n ->
            case n.childNodes of
                InlineLeafArray _ ->
                    True

                _ ->
                    False
        )


{-| Find ancestor from path finds the closest ancestor from the given NodePath that matches the
predicate.
-}
findAncestor : (EditorBlockNode -> Bool) -> NodePath -> EditorBlockNode -> Maybe ( NodePath, EditorBlockNode )
findAncestor pred path node =
    case path of
        [] ->
            Nothing

        x :: xs ->
            case node.childNodes of
                BlockArray a ->
                    case Array.get x a of
                        Nothing ->
                            Nothing

                        Just childNode ->
                            case findAncestor pred xs childNode of
                                Nothing ->
                                    if pred node then
                                        Just ( [], node )

                                    else
                                        Nothing

                                Just ( p, result ) ->
                                    Just ( x :: p, result )

                _ ->
                    if pred node then
                        Just ( [], node )

                    else
                        Nothing


{-| nodeAt returns the node at the specified NodePath if it exists.
-}
nodeAt : NodePath -> EditorBlockNode -> Maybe EditorNode
nodeAt path node =
    case path of
        [] ->
            Just <| BlockNodeWrapper node

        x :: xs ->
            case node.childNodes of
                BlockArray list ->
                    case Array.get x list of
                        Nothing ->
                            Nothing

                        Just childNode ->
                            nodeAt xs childNode

                InlineLeafArray list ->
                    case Array.get x list of
                        Nothing ->
                            Nothing

                        Just childLeafNode ->
                            if List.isEmpty xs then
                                Just <| InlineLeafWrapper childLeafNode

                            else
                                Nothing

                Leaf ->
                    Nothing



{- This method removes all the nodes inclusive to both the start and end node path.  Note that
   an ancestor is not removed if the start path or end path is a child node.
-}


removeInRange : NodePath -> NodePath -> EditorBlockNode -> EditorBlockNode
removeInRange start end node =
    let
        startIndex =
            Maybe.withDefault 0 (List.head start)

        startRest =
            Maybe.withDefault [] (List.tail start)

        endIndex =
            Maybe.withDefault
                (case node.childNodes of
                    BlockArray a ->
                        Array.length a

                    InlineLeafArray a ->
                        Array.length a

                    Leaf ->
                        0
                )
                (List.head end)

        endRest =
            Maybe.withDefault [] (List.tail end)
    in
    if startIndex > endIndex then
        node

    else if startIndex == endIndex then
        case node.childNodes of
            BlockArray a ->
                if List.isEmpty startRest && List.isEmpty endRest then
                    { node | childNodes = BlockArray <| Array.Extra.removeAt startIndex a }

                else
                    case Array.get startIndex a of
                        Nothing ->
                            node

                        Just b ->
                            { node | childNodes = BlockArray <| Array.set startIndex (removeInRange startRest endRest b) a }

            InlineLeafArray a ->
                if List.isEmpty startRest && List.isEmpty endRest then
                    { node | childNodes = InlineLeafArray <| Array.Extra.removeAt startIndex a }

                else
                    node

            Leaf ->
                node

    else
        case node.childNodes of
            BlockArray a ->
                let
                    left =
                        Array.Extra.sliceUntil startIndex a

                    right =
                        Array.Extra.sliceFrom (endIndex + 1) a

                    leftRest =
                        if List.isEmpty startRest then
                            Array.empty

                        else
                            case Array.get startIndex a of
                                Nothing ->
                                    Array.empty

                                Just b ->
                                    Array.fromList [ removeInRange startRest endRest b ]

                    rightRest =
                        if List.isEmpty endRest then
                            Array.empty

                        else
                            case Array.get endIndex a of
                                Nothing ->
                                    Array.empty

                                Just b ->
                                    Array.fromList [ removeInRange startRest endRest b ]
                in
                { node | childNodes = BlockArray <| List.foldr Array.append Array.empty [ left, leftRest, rightRest, right ] }

            InlineLeafArray a ->
                let
                    left =
                        Array.Extra.sliceUntil
                            (if List.isEmpty startRest then
                                startIndex

                             else
                                startIndex + 1
                            )
                            a

                    right =
                        Array.Extra.sliceFrom
                            (if List.isEmpty endRest then
                                endIndex + 1

                             else
                                endIndex
                            )
                            a
                in
                { node | childNodes = InlineLeafArray <| Array.append left right }

            Leaf ->
                node


removeNodeAndEmptyParents : NodePath -> EditorBlockNode -> EditorBlockNode
removeNodeAndEmptyParents path node =
    case path of
        [] ->
            node

        [ x ] ->
            case node.childNodes of
                BlockArray a ->
                    { node | childNodes = BlockArray <| Array.Extra.removeAt x a }

                InlineLeafArray a ->
                    { node | childNodes = InlineLeafArray <| Array.Extra.removeAt x a }

                Leaf ->
                    node

        x :: xs ->
            case node.childNodes of
                BlockArray a ->
                    case Array.get x a of
                        Nothing ->
                            node

                        Just n ->
                            let
                                newNode =
                                    removeNodeAndEmptyParents xs n
                            in
                            case newNode.childNodes of
                                BlockArray newNodeChildren ->
                                    if Array.isEmpty newNodeChildren then
                                        { node | childNodes = BlockArray <| Array.Extra.removeAt x a }

                                    else
                                        { node | childNodes = BlockArray <| Array.set x newNode a }

                                InlineLeafArray newNodeChildren ->
                                    if Array.isEmpty newNodeChildren then
                                        { node | childNodes = BlockArray <| Array.Extra.removeAt x a }

                                    else
                                        { node | childNodes = BlockArray <| Array.set x newNode a }

                                _ ->
                                    { node | childNodes = BlockArray <| Array.set x newNode a }

                InlineLeafArray _ ->
                    node

                Leaf ->
                    node


splitBlockAtPathAndOffset : NodePath -> Int -> EditorBlockNode -> Maybe ( EditorBlockNode, EditorBlockNode )
splitBlockAtPathAndOffset path offset node =
    case path of
        [] ->
            case node.childNodes of
                BlockArray a ->
                    Just
                        ( { node | childNodes = BlockArray (Array.Extra.sliceUntil offset a) }
                        , { node | childNodes = BlockArray (Array.Extra.sliceFrom offset a) }
                        )

                InlineLeafArray a ->
                    Just
                        ( { node | childNodes = InlineLeafArray (Array.Extra.sliceUntil offset a) }
                        , { node | childNodes = InlineLeafArray (Array.Extra.sliceFrom offset a) }
                        )

                Leaf ->
                    Just ( node, node )

        x :: xs ->
            case node.childNodes of
                BlockArray a ->
                    case Array.get x a of
                        Nothing ->
                            Nothing

                        Just n ->
                            case splitBlockAtPathAndOffset xs offset n of
                                Nothing ->
                                    Nothing

                                Just ( before, after ) ->
                                    Just
                                        ( { node | childNodes = BlockArray (Array.set x before a) }
                                        , { node | childNodes = BlockArray (Array.set x after a) }
                                        )

                InlineLeafArray a ->
                    case Array.get x a of
                        Nothing ->
                            Nothing

                        Just n ->
                            case n of
                                TextLeaf tl ->
                                    let
                                        before =
                                            TextLeaf { tl | text = String.left offset tl.text }

                                        after =
                                            TextLeaf { tl | text = String.dropLeft offset tl.text }
                                    in
                                    Just
                                        ( { node | childNodes = InlineLeafArray (Array.set x before (Array.Extra.sliceUntil (x + 1) a)) }
                                        , { node | childNodes = InlineLeafArray (Array.set 0 after (Array.Extra.sliceFrom x a)) }
                                        )

                                InlineLeaf _ ->
                                    Just
                                        ( { node | childNodes = InlineLeafArray (Array.Extra.sliceUntil x a) }
                                        , { node | childNodes = InlineLeafArray (Array.Extra.sliceFrom x a) }
                                        )

                Leaf ->
                    Nothing