{-# LANGUAGE FlexibleContexts #-}
module Lamdu.GUI.ExpressionEdit.HoleEdit.ValTerms
    ( ofName, expr
    , allowedSearchTermCommon
    , allowedFragmentSearchTerm
    , getSearchStringRemainder
    , verifyInjectSuffix
    , definitePart
    ) where

import qualified Control.Lens as Lens
import qualified Data.Char as Char
import           Data.Property (Property)
import qualified Data.Property as Property
import qualified Data.Text as Text
import qualified GUI.Momentu.Widgets.Menu.Search as SearchMenu
import qualified Lamdu.Builtins.Anchors as Builtins
import qualified Lamdu.CharClassification as Chars
import           Lamdu.Formatting (Format(..))
import           Lamdu.GUI.ExpressionGui (ExpressionN)
import           Lamdu.Name (Name(..), Collision(..))
import qualified Lamdu.Name as Name
import qualified Lamdu.Sugar.Lens as SugarLens
import qualified Lamdu.Sugar.Names.Get as NamesGet
import qualified Lamdu.Sugar.Types as Sugar

import           Lamdu.Prelude

collisionText :: Name.Collision -> Text
collisionText NoCollision = ""
collisionText (Collision i) = Text.pack (show i)
collisionText UnknownCollision = "?"

ofName :: Name o -> [Text]
ofName Name.Unnamed{} = []
ofName (Name.AutoGenerated text) = [text]
ofName (Name.Stored storedName) =
    [ displayName
        <> collisionText textCollision
        <> collisionText (storedName ^. Name.snTagCollision)
    ]
    where
        Name.TagText displayName textCollision = storedName ^. Name.snDisplayText

formatProp :: Format a => Property m a -> Text
formatProp i = i ^. Property.pVal & format

formatLiteral :: Sugar.Literal (Property m) -> Text
formatLiteral (Sugar.LiteralNum i) = formatProp i
formatLiteral (Sugar.LiteralText i) = formatProp i
formatLiteral (Sugar.LiteralBytes i) = formatProp i

bodyShape :: Sugar.Body (Name o) i o expr -> [Text]
bodyShape = \case
    Sugar.BodyLam {} -> ["lambda", "\\", "Λ", "λ", "->", "→"]
    Sugar.BodySimpleApply {} -> ["Apply"]
    Sugar.BodyLabeledApply {} -> ["Apply"]
    Sugar.BodyRecord {} -> ["{}", "()", "[]"]
    Sugar.BodyGetField gf -> ofName (gf ^. Sugar.gfTag . Sugar.tagInfo . Sugar.tagName) <&> ("." <>)
    Sugar.BodyCase cas ->
        ["case", "of"] ++
        case cas of
            Sugar.Case Sugar.LambdaCase (Sugar.Composite [] Sugar.ClosedComposite{} _) -> ["absurd"]
            _ -> []
    Sugar.BodyIfElse {} -> ["if", ":"]
    -- An inject "base expr" can have various things in its val filled
    -- in, so the result group based on it may have both nullary
    -- inject (".") and value inject (":"). Thus, an inject must match
    -- both.
    -- So these terms are used to filter the whole group, and then
    -- isExactMatch (see below) is used to filter each entry.
    Sugar.BodyInject (Sugar.Inject tag _) ->
        (<>) <$> ofName (tag ^. Sugar.tagInfo . Sugar.tagName) <*> [":", "."]
    Sugar.BodyLiteral i -> [formatLiteral i]
    Sugar.BodyGetVar Sugar.GetParamsRecord {} -> ["Params"]
    Sugar.BodyGetVar {} -> []
    Sugar.BodyToNom {} -> []
    Sugar.BodyFromNom nom
        | nom ^. Sugar.nTId . Sugar.tidTId == Builtins.boolTid -> ["if"]
        | otherwise -> []
    Sugar.BodyHole {} -> []
    Sugar.BodyFragment {} -> []
    Sugar.BodyPlaceHolder {} -> []

bodyNames :: Monad i => Sugar.Body (Name o) i o expr -> [Text]
bodyNames =
    \case
    Sugar.BodyGetVar Sugar.GetParamsRecord {} -> []
    Sugar.BodyLam {} -> []
    b -> NamesGet.fromBody b >>= ofName

expr :: Monad i => ExpressionN i o a -> [Text]
expr (Sugar.Expression body _) =
    bodyShape body <>
    bodyNames body <>
    case body of
    Sugar.BodyToNom (Sugar.Nominal _ binder) ->
        expr (binder ^. Sugar.bbContent . SugarLens.binderContentExpr)
    Sugar.BodyFromNom (Sugar.Nominal _ val) -> expr val
    _ -> []

type Suffix = Char

allowedSearchTermCommon :: [Suffix] -> Text -> Bool
allowedSearchTermCommon suffixes searchTerm =
    any (searchTerm &)
    [ Text.all (`elem` Chars.operator)
    , Text.all Char.isAlphaNum
    , (`Text.isPrefixOf` "{}")
    , (== "\\")
    , Lens.has (Lens.reversed . Lens._Cons . Lens.filtered inj)
    ]
    where
        inj (lastChar, revInit) =
            lastChar `elem` suffixes && Text.all Char.isAlphaNum revInit

allowedFragmentSearchTerm :: Text -> Bool
allowedFragmentSearchTerm searchTerm =
    allowedSearchTermCommon ":" searchTerm || isGetField searchTerm
    where
        isGetField t =
            case Text.uncons t of
            Just (c, rest) -> c == '.' && Text.all Char.isAlphaNum rest
            Nothing -> False

-- | Given a hole result sugared expression, determine which part of
-- the search term is a remainder and which belongs inside the hole
-- result expr
getSearchStringRemainder ::
    SearchMenu.ResultsContext -> Sugar.Expression name i o a -> Text
getSearchStringRemainder ctx holeResultConverted
    | isA Sugar._BodyInject = ""
      -- NOTE: This is wrong for operator search terms like ".." which
      -- should NOT have a remainder, but do. We might want to correct
      -- that.  However, this does not cause any bug because search
      -- string remainders are genreally ignored EXCEPT in
      -- apply-operator, which does not occur when the search string
      -- already is an operator.
    | isSuffixed ":" = ":"
    | isSuffixed "." = "."
    | otherwise = ""
    where
        isSuffixed suffix = Text.isSuffixOf suffix (ctx ^. SearchMenu.rSearchTerm)
        fragmentExpr = Sugar.rBody . Sugar._BodyFragment . Sugar.fExpr
        isA x = any (`Lens.has` holeResultConverted) [Sugar.rBody . x, fragmentExpr . Sugar.rBody . x]

injectMVal ::
    Lens.Traversal'
    (Sugar.Expression name i o a)
    (Sugar.InjectVal name i o (Sugar.Expression name i o a))
injectMVal = Sugar.rBody . Sugar._BodyInject . Sugar.iMVal

verifyInjectSuffix :: Text -> Sugar.Expression name i o a -> Bool
verifyInjectSuffix searchTerm val =
    case suffix of
    Just ':' | Lens.has (injectMVal . Sugar._InjectNullary) val -> False
    Just '.' | Lens.has (injectMVal . Sugar._InjectVal) val -> False
    _ -> True
    where
        suffix = searchTerm ^? Lens.reversed . Lens._Cons . _1

-- | Returns the part of the search term that is DEFINITELY part of
-- it. Some of the stripped suffix may be part of the search term,
-- depending on the val.
definitePart :: Text -> Text
definitePart searchTerm
    | Text.any Char.isAlphaNum searchTerm
    && any (`Text.isSuffixOf` searchTerm) [":", "."] = Text.init searchTerm
    | otherwise = searchTerm
