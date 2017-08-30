{-# LANGUAGE NoImplicitPrelude, TemplateHaskell, DeriveGeneric, OverloadedStrings, DeriveTraversable #-}

module GUI.Momentu.Widgets.Menu
    ( Style(..), HasStyle(..)
    , Option(..), oId, oWidget, oSubmenuWidget
    , OrderedOptions(..), optionsFromTop, optionsFromBottom
    , Placement(..), HasMoreOptions(..)
    , layout
    ) where

import qualified Control.Lens as Lens
import qualified Control.Monad.Reader as Reader
import qualified Data.Aeson.Types as Aeson
import           GHC.Generics (Generic)
import           GUI.Momentu.Align (WithTextPos)
import qualified GUI.Momentu.Align as Align
import qualified GUI.Momentu.Draw as Draw
import qualified GUI.Momentu.Element as Element
import qualified GUI.Momentu.EventMap as E
import           GUI.Momentu.Glue ((/|/))
import qualified GUI.Momentu.Glue as Glue
import qualified GUI.Momentu.Hover as Hover
import qualified GUI.Momentu.MetaKey as MetaKey
import           GUI.Momentu.ModKey (ModKey(..))
import           GUI.Momentu.View (View)
import           GUI.Momentu.Widget (Widget)
import qualified GUI.Momentu.Widget as Widget
import qualified GUI.Momentu.Widgets.TextView as TextView

import           Lamdu.Prelude

data Style = Style
    { submenuSymbolColorUnselected :: Draw.Color
    , submenuSymbolColorSelected :: Draw.Color
    } deriving (Eq, Generic, Show)
instance Aeson.ToJSON Style where
    toJSON = Aeson.genericToJSON Aeson.defaultOptions
instance Aeson.FromJSON Style

class HasStyle env where style :: Lens' env Style
instance HasStyle Style where style = id

data Option m = Option
    { _oId :: !Widget.Id
    , -- A widget that represents this option
      _oWidget :: !(WithTextPos (Widget (m Widget.EventResult)))
    , -- An optionally empty submenu
      _oSubmenuWidget :: !(Maybe (WithTextPos (Widget (m Widget.EventResult))))
    }
Lens.makeLenses ''Option

data OrderedOptions a = OrderedOptions
    { _optionsFromTop :: a
    , _optionsFromBottom :: a
    } deriving (Functor, Foldable, Traversable)
Lens.makeLenses ''OrderedOptions

instance Applicative OrderedOptions where
    pure = join OrderedOptions
    OrderedOptions fa fb <*> OrderedOptions xa xb =
        OrderedOptions (fa xa) (fb xb)

-- | You may want to limit the placement of hovering pop-up menus,
-- so that they don't cover other ui elements.
data Placement = Above | Below | AnyPlace

data HasMoreOptions = MoreOptionsAvailable | NoMoreOptions

makeNoResults ::
    (MonadReader env m, TextView.HasStyle env, Element.HasAnimIdPrefix env) =>
    m (WithTextPos View)
makeNoResults = TextView.makeLabel "(No results)"

makeMoreOptionsView ::
    (MonadReader env m, TextView.HasStyle env, Element.HasAnimIdPrefix env) =>
    HasMoreOptions -> m (WithTextPos View)
makeMoreOptionsView NoMoreOptions = pure Element.empty
makeMoreOptionsView MoreOptionsAvailable = TextView.makeLabel "..."

blockEvents ::
    Applicative f =>
    OrderedOptions (Widget (f (Widget.EventResult)) -> Widget (f (Widget.EventResult)))
blockEvents =
    OrderedOptions
    { _optionsFromTop = blockDirection MetaKey.Key'Down "down"
    , _optionsFromBottom = blockDirection MetaKey.Key'Up "up"
    }
    where
        blockDirection key keyName =
            pure mempty
            & E.keyPresses
                [ModKey mempty key]
                (E.Doc ["Navigation", "Move", keyName <> " (blocked)"])
            & E.weakerEvents


submenuSymbolText :: Text
submenuSymbolText = " ▷"

makeSubmenuSymbol ::
    ( MonadReader env m, HasStyle env, Element.HasAnimIdPrefix env
    , TextView.HasStyle env
    ) =>
    Bool -> m (WithTextPos View)
makeSubmenuSymbol isSelected =
    do
        color <- Lens.view style <&> submenuSymbolColor
        TextView.makeLabel submenuSymbolText
            & Reader.local (TextView.color .~ color)
    where
        submenuSymbolColor
            | isSelected = submenuSymbolColorSelected
            | otherwise = submenuSymbolColorUnselected

layoutOption ::
    ( MonadReader env m, Element.HasAnimIdPrefix env, TextView.HasStyle env
    , HasStyle env, Functor f
    ) =>
    Widget.R -> Option f -> m (WithTextPos (Widget (f Widget.EventResult)))
layoutOption maxOptionWidth option =
    case option ^. oSubmenuWidget of
    Nothing ->
        option ^. oWidget & Element.width .~ maxOptionWidth & pure
    Just submenu ->
        do
            submenuSymbol <-
                makeSubmenuSymbol isSelected
                & Reader.local (Element.animIdPrefix .~ Widget.toAnimId (option ^. oId))
            let base =
                    (option ^. oWidget
                     & Element.width .~ maxOptionWidth - submenuSymbol ^. Element.width)
                    /|/ submenuSymbol
                    & Align.tValue %~ Hover.anchor
            base
                & Align.tValue %~
                Hover.hoverInPlaceOf
                (Hover.hoverBesideOptionsAxis Glue.Horizontal
                    (submenu & Align.tValue %~ Hover.hover) base
                 <&> (^. Align.tValue))
                & pure
    where
        isSelected =
            Widget.isFocused (option ^. oWidget . Align.tValue)
            || Lens.anyOf (oSubmenuWidget . Lens._Just . Align.tValue)
               Widget.isFocused option

layout ::
    ( MonadReader env m, TextView.HasStyle env
    , Element.HasAnimIdPrefix env, HasStyle env
    , Applicative f
    ) =>
    Widget.R -> [Option f] -> HasMoreOptions ->
    m (OrderedOptions (Widget (f Widget.EventResult)))
layout minWidth options hiddenResults
    | null options = makeNoResults <&> (^. Align.tValue) <&> Widget.fromView <&> pure
    | otherwise =
        do
            submenuSymbolWidth <-
                TextView.drawText ?? submenuSymbolText
                <&> (^. TextView.renderedTextSize . TextView.bounding . _1)
            let optionMinWidth option =
                    option ^. oWidget . Element.width +
                    case option ^. oSubmenuWidget of
                    Nothing -> 0
                    Just _ -> submenuSymbolWidth
            let maxOptionWidth = options <&> optionMinWidth & maximum & max minWidth
            hiddenOptionsWidget <-
                makeMoreOptionsView hiddenResults
                <&> (^. Align.tValue) <&> Widget.fromView
            laidOutOptions <-
                traverse (layoutOption maxOptionWidth) options
                <&> map (^. Align.tValue)
            blockEvents <*>
                ( OrderedOptions
                    { _optionsFromTop = id
                    , _optionsFromBottom = reverse
                    } ?? (laidOutOptions ++ [hiddenOptionsWidget])
                    <&> Glue.vbox
                ) & pure

