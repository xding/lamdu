{-# LANGUAGE TemplateHaskell, TypeFamilies, FlexibleContexts #-}
module GUI.Momentu.Widgets.EventMapHelp
    ( make
    , IsHelpShown(..)
    , makeToggledHelpAdder
    , addHelpView
    , Style(..), styleText, styleInputDocColor, styleBGColor, styleTint
    , Config(..), configOverlayDocKeys
    , Env(..), eConfig, eStyle
    , defaultStyle
    , defaultConfig
    , defaultEnv
    ) where

import qualified Control.Lens as Lens
import           Control.Monad.IO.Class (MonadIO(..))
import qualified Control.Monad.Reader as Reader
import           Data.Function (on)
import           Data.IORef (IORef, newIORef, readIORef, modifyIORef)
import qualified Data.List as List
import qualified Data.Map as Map
import qualified Data.Tuple as Tuple
import           Data.Vector.Vector2 (Vector2(..))
import           GUI.Momentu.Align (Aligned(..))
import qualified GUI.Momentu.Align as Align
import           GUI.Momentu.Animation (AnimId, R)
import qualified GUI.Momentu.Animation as Anim
import qualified GUI.Momentu.Draw as MDraw
import qualified GUI.Momentu.Element as Element
import           GUI.Momentu.EventMap (EventMap)
import qualified GUI.Momentu.EventMap as E
import           GUI.Momentu.Font (Font)
import qualified GUI.Momentu.Font as Font
import           GUI.Momentu.Glue ((/|/))
import           GUI.Momentu.MetaKey (MetaKey(..), toModKey, noMods)
import qualified GUI.Momentu.MetaKey as MetaKey
import           GUI.Momentu.ModKey (ModKey(..))
import qualified GUI.Momentu.ModKey as ModKey
import           GUI.Momentu.State (Gui)
import qualified GUI.Momentu.State as State
import           GUI.Momentu.View (View(..))
import           GUI.Momentu.Widget (Widget)
import qualified GUI.Momentu.Widget as Widget
import qualified GUI.Momentu.Widgets.GridView as GridView
import qualified GUI.Momentu.Widgets.Label as Label
import qualified GUI.Momentu.Widgets.Spacer as Spacer
import qualified GUI.Momentu.Widgets.TextView as TextView
import qualified Graphics.DrawingCombinators as Draw

import           Lamdu.Prelude

data Style = Style
    { _styleText :: TextView.Style
    , _styleInputDocColor :: Draw.Color
    , _styleBGColor :: Draw.Color
    , _styleTint :: Draw.Color
    }
Lens.makeLenses ''Style

newtype Config = Config
    { _configOverlayDocKeys :: [MetaKey]
    }
Lens.makeLenses ''Config

data Env = Env
    { _eConfig :: Config
    , _eStyle :: Style
    , _eAnimIdPrefix :: AnimId
    }
Lens.makeLenses ''Env
instance Element.HasAnimIdPrefix Env where animIdPrefix = eAnimIdPrefix
instance TextView.HasStyle Env where style = eStyle . styleText

defaultStyle :: Font -> Style
defaultStyle font =
    Style
    { _styleText =
        TextView.Style
        { TextView._styleColor = Draw.Color 1 1 1 1
        , TextView._styleFont = font
        , TextView._styleUnderline = Nothing
        }
    , _styleInputDocColor = Draw.Color 0.1 0.7 0.7 1
    , _styleBGColor = Draw.Color 0.2 0.15 0.1 0.5
    , _styleTint = Draw.Color 1 1 1 0.8
    }

defaultConfig :: Config
defaultConfig =
    Config
    { _configOverlayDocKeys = [MetaKey noMods MetaKey.Key'F1]
    }

defaultEnv :: Font -> Env
defaultEnv font =
    Env
    { _eConfig = defaultConfig
    , _eStyle = defaultStyle font
    , _eAnimIdPrefix = ["help box"]
    }

data Tree n l = Leaf l | Branch n [Tree n l]
    deriving (Eq, Ord, Show, Functor, Foldable, Traversable)

bitraverseTree :: Applicative f => (n0 -> f n1) -> (l0 -> f l1) -> Tree n0 l0 -> f (Tree n1 l1)
bitraverseTree _ onLeaf (Leaf l) = Leaf <$> onLeaf l
bitraverseTree onNode onLeaf (Branch n ts) = Branch <$> onNode n <*> traverse (bitraverseTree onNode onLeaf) ts

treeNodes :: Lens.Traversal (Tree n0 l) (Tree n1 l) n0 n1
treeNodes = (`bitraverseTree` pure)

groupTree :: Eq node => [([node], leaf)] -> [Tree node leaf]
groupTree = foldr step []
    where
        step ([], l) rest = Leaf l : rest
        step (at:as, l) b =
            case b of
                Branch bt bs : rest
                    | at == bt -> Branch bt (step (as, l) bs) : rest
                _ -> Branch at (step (as, l) []) : b

-- We also rely on Map.toList returning a sorted list
groupInputDocs :: [([E.Subtitle], E.InputDoc)] -> [([E.Subtitle], [E.InputDoc])]
groupInputDocs = Map.toList . Map.fromListWith (++) . (Lens.traversed . _2 %~) (:[])

addAnimIds :: Show a => AnimId -> Tree a b -> Tree (AnimId, a) (AnimId, b)
addAnimIds animId (Leaf b) = Leaf (animId ++ ["leaf"], b)
addAnimIds animId (Branch a cs) =
    Branch (tAnimId, a) $ map (addAnimIds tAnimId) cs
    where
        tAnimId = Anim.augmentId a animId

makeShortcutKeyView :: MonadReader Env m => [E.InputDoc] -> m View
makeShortcutKeyView inputDocs =
    inputDocs
    <&> (<> " ")
    & traverse Label.make
    <&> map (^. Align.tValue)
    <&> Align.vboxAlign 1
    & Reader.local setColor
    where
        setColor env =
            env & TextView.style . TextView.styleColor .~ (env ^. eStyle . styleInputDocColor)

makeTextViews :: MonadReader Env m => Tree E.Subtitle [E.InputDoc] -> m (Tree View View)
makeTextViews tree =
    addAnimIds helpAnimId tree
    & traverse shortcut
    >>= treeNodes mkDoc
    where
        shortcut (animId, doc) =
            makeShortcutKeyView doc
            & Reader.local (Element.animIdPrefix .~ animId)
        mkDoc (animId, subtitle) =
            Label.make subtitle
            <&> (^. Align.tValue)
            & Reader.local (Element.animIdPrefix .~ animId)

columns :: R -> (a -> R) -> [a] -> [[a]]
columns maxHeight itemHeight =
    combine . foldr step (0, [], [])
    where
        combine (_, curColumn, doneColumns) = curColumn : doneColumns
        step new (curColumnHeight, curColumn, doneColumns)
            | newHeight + curColumnHeight > maxHeight =
                (newHeight, [new], curColumn : doneColumns)
            | otherwise =
                (newHeight + curColumnHeight, new : curColumn, doneColumns)
            where
                newHeight = itemHeight new

make :: MonadReader Env m => Vector2 R -> EventMap a -> m View
make size eventMap =
    (makeTreeView ?? size)
    <*>
    ( eventMap ^.. E.emDocs . Lens.withIndex
        <&> (_1 %~ (^. E.docStrs)) . Tuple.swap
        & groupInputDocs & groupTree
        & traverse makeTextViews
    )

makeTooltip :: MonadReader Env m => [ModKey] -> m View
makeTooltip helpKeys =
    (/|/)
    <$> (Label.make "Show help" <&> (^. Align.tValue))
    <*> makeShortcutKeyView (helpKeys <&> ModKey.pretty)

indent :: R -> View -> View
indent width = (Spacer.makeHorizontal width /|/)

fontHeight :: (MonadReader env m, TextView.HasStyle env) => m R
fontHeight =
    Lens.view (TextView.style . TextView.styleFont) <&> Font.height

makeFlatTreeView ::
    (MonadReader env m, TextView.HasStyle env) =>
    m (Vector2 R -> [(View, View)] -> View)
makeFlatTreeView =
    fontHeight <&> Spacer.makeHorizontal
    <&>
    \space size pairs ->
    let colViews =
            pairs
            & columns (size ^. _2) pairHeight
            <&> map toRow
            <&> GridView.make
            <&> snd
    in
    List.intersperse space colViews & Align.hboxAlign 1
    where
        toRow (titleView, docView) = [Aligned 0 titleView, Aligned (Vector2 1 0) docView]
        pairHeight (titleView, docView) = (max `on` (^. Element.height)) titleView docView

makeTreeView ::
    (MonadReader env m, TextView.HasStyle env) =>
    m (Vector2 R -> [Tree View View] -> View)
makeTreeView =
    do
        indentWidth <- fontHeight
        let go ts = ts <&> fromTree & mconcat
            fromTree (Leaf inputDocsView) = ([], [inputDocsView])
            fromTree (Branch titleView ts) =
                ( (titleView, Align.vboxAlign 1 inputDocs) :
                    (Lens.traversed . _1 %~ indent indentWidth) titles
                , [] )
                where
                    (titles, inputDocs) = go ts
        let handleResult (pairs, []) = pairs
            handleResult _ = error "Leafs at root of tree!"
        makeFlatTreeView
            <&> \mk size trees -> mk size (handleResult (go trees))

addToBottomRight :: View -> Widget.Size -> Element.Layers -> Element.Layers
addToBottomRight (View eventMapSize eventMapLayers) size =
    Element.addLayersAbove docLayers
    where
        docLayers = Element.translateLayers (size - eventMapSize) eventMapLayers

data IsHelpShown = HelpShown | HelpNotShown
    deriving (Eq, Ord, Read, Show, Enum, Bounded)

toggle :: IsHelpShown -> IsHelpShown
toggle HelpShown = HelpNotShown
toggle HelpNotShown = HelpShown

helpAnimId :: AnimId
helpAnimId = ["help box"]

addHelpView :: MonadReader Env m => Vector2 R -> Widget.Focused (f a) -> m (Widget.Focused (f a))
addHelpView = addHelpViewWith HelpShown

addHelpViewWith ::
    MonadReader Env m =>
    IsHelpShown -> Vector2 R ->
    Widget.Focused (f a) -> m (Widget.Focused (f a))
addHelpViewWith showingHelp size focus =
    do
        keys <- Lens.view (eConfig . configOverlayDocKeys) <&> Lens.mapped %~ toModKey
        helpView <-
            ( (.)
                <$> (Element.tint <$> Lens.view (eStyle . styleTint))
                <*> (MDraw.backgroundColor helpAnimId <$> Lens.view (eStyle . styleBGColor))
            ) <*>
            case showingHelp of
            HelpNotShown -> makeTooltip keys
            HelpShown ->
                make size
                ( (focus ^. Widget.fEventMap)
                    Widget.EventContext
                    { Widget._eVirtualCursor = focus ^. Widget.fFocalAreas & last & State.VirtualCursor
                    , Widget._ePrevTextRemainder = mempty
                    }
                )
        focus & Widget.fLayers %~ addToBottomRight helpView size & pure

toggleEventMap ::
    (MonadReader Env m, MonadIO f, Monoid a) =>
    IORef IsHelpShown -> IsHelpShown -> m (EventMap (f a))
toggleEventMap showingHelpVar showingHelp =
    Lens.view (eConfig . configOverlayDocKeys)
    <&>
    \keys ->
    modifyIORef showingHelpVar toggle
    & liftIO
    & E.keysEventMap keys
        (E.Doc ["Help", "Key Bindings", docStr])
    where
        docStr =
            case showingHelp of
            HelpNotShown -> "Show"
            HelpShown -> "Hide"

makeToggledHelpAdder ::
    MonadIO m =>
    IsHelpShown ->
    IO (Env -> Widget.Size -> Gui Widget m -> IO (Gui Widget m))
makeToggledHelpAdder startValue =
    newIORef startValue
    <&>
    \showingHelpVar env size widget ->
    widget & Widget.wState %%~
    \case
    Widget.StateUnfocused {} -> fail "adding help to non-focused root widget!"
    Widget.StateFocused makeFocus ->
        readIORef showingHelpVar
        <&> (\showingHelp ->
                makeFocus
                <&> (addHelpViewWith showingHelp size ?? env)
                <&> Widget.fEventMap . Lens.mapped %~ (toggleEventMap showingHelpVar showingHelp env <>)
            )
        <&> Widget.StateFocused
