{-# LANGUAGE NoImplicitPrelude, TemplateHaskell, DeriveFunctor, DeriveGeneric, FlexibleContexts, RecordWildCards, LambdaCase, PatternGuards, OverloadedStrings #-}
module Graphics.UI.Bottle.EventMap
    ( KeyEvent(..)
    , InputDoc, Subtitle, Doc(..), docStrs
    , MaybeWantsClipboard(..)
    , EventMap, lookup
    , emDocs
    , charEventMap, allChars
    , charGroup
    , keyEventMap, keyPress, keyPresses, keyPressOrRepeat
    , pasteOnKey
    , dropEventMap
    , deleteKey, deleteKeys
    , filterChars
    ) where

import qualified Control.Lens as Lens
import           Control.Lens.Operators
import           Control.Monad (guard)
import           Data.Foldable (asum)
import           Data.Map (Map)
import qualified Data.Map as Map
import           Data.Maybe (catMaybes, listToMaybe)
import           Data.Monoid ((<>))
import           Data.Set (Set)
import qualified Data.Set as Set
import           Data.Text (Text)
import           GHC.Generics (Generic)
import           Graphics.UI.Bottle.ModKey (ModKey(..))
import qualified Graphics.UI.Bottle.ModKey as ModKey
import qualified Graphics.UI.GLFW as GLFW
import qualified Graphics.UI.GLFW.Events as Events

import           Prelude.Compat hiding (lookup)

{-# ANN module ("HLint: ignore Use camelCase"::String) #-}

data KeyEvent = KeyEvent GLFW.KeyState ModKey
    deriving (Generic, Show, Eq, Ord)

charOfKey :: GLFW.Key -> Maybe Char
charOfKey key =
    case key of
    GLFW.Key'A           -> Just 'A'
    GLFW.Key'B           -> Just 'B'
    GLFW.Key'C           -> Just 'C'
    GLFW.Key'D           -> Just 'D'
    GLFW.Key'E           -> Just 'E'
    GLFW.Key'F           -> Just 'F'
    GLFW.Key'G           -> Just 'G'
    GLFW.Key'H           -> Just 'H'
    GLFW.Key'I           -> Just 'I'
    GLFW.Key'J           -> Just 'J'
    GLFW.Key'K           -> Just 'K'
    GLFW.Key'L           -> Just 'L'
    GLFW.Key'M           -> Just 'M'
    GLFW.Key'N           -> Just 'N'
    GLFW.Key'O           -> Just 'O'
    GLFW.Key'P           -> Just 'P'
    GLFW.Key'Q           -> Just 'Q'
    GLFW.Key'R           -> Just 'R'
    GLFW.Key'S           -> Just 'S'
    GLFW.Key'T           -> Just 'T'
    GLFW.Key'U           -> Just 'U'
    GLFW.Key'V           -> Just 'V'
    GLFW.Key'W           -> Just 'W'
    GLFW.Key'X           -> Just 'X'
    GLFW.Key'Y           -> Just 'Y'
    GLFW.Key'Z           -> Just 'Z'
    GLFW.Key'Comma       -> Just ','
    GLFW.Key'Enter       -> Just '\n'
    GLFW.Key'Equal       -> Just '='
    GLFW.Key'GraveAccent -> Just '`'
    GLFW.Key'Minus       -> Just '-'
    GLFW.Key'Space       -> Just ' '
    GLFW.Key'Pad0        -> Just '0'
    GLFW.Key'Pad1        -> Just '1'
    GLFW.Key'Pad2        -> Just '2'
    GLFW.Key'Pad3        -> Just '3'
    GLFW.Key'Pad4        -> Just '4'
    GLFW.Key'Pad5        -> Just '5'
    GLFW.Key'Pad6        -> Just '6'
    GLFW.Key'Pad7        -> Just '7'
    GLFW.Key'Pad8        -> Just '8'
    GLFW.Key'Pad9        -> Just '9'
    GLFW.Key'PadDivide   -> Just '/'
    GLFW.Key'PadMultiply -> Just '*'
    GLFW.Key'PadSubtract -> Just '-'
    GLFW.Key'PadAdd      -> Just '+'
    GLFW.Key'PadDecimal  -> Just '.'
    GLFW.Key'PadEqual    -> Just '='
    _              -> Nothing

type Clipboard = Text

type Subtitle = Text

newtype Doc = Doc
    { _docStrs :: [Subtitle]
    } deriving (Generic, Eq, Ord)
Lens.makeLenses ''Doc

data DocHandler a = DocHandler
    { _dhDoc :: Doc
    , _dhHandler :: a
    } deriving (Generic, Functor)
Lens.makeLenses ''DocHandler

type InputDoc = Text

-- AllCharsHandler always conflict with each other
data AllCharsHandler a = AllCharsHandler
    { chInputDoc :: InputDoc
    , _chDocHandler :: DocHandler (Char -> Maybe a)
    } deriving (Generic, Functor)
Lens.makeLenses ''AllCharsHandler

chDocs :: Lens.IndexedTraversal' InputDoc (AllCharsHandler a) Doc
chDocs f AllCharsHandler{..} =
    AllCharsHandler chInputDoc
    <$> dhDoc (Lens.indexed f chInputDoc) _chDocHandler

data CharGroupHandler a = CharGroupHandler
    { cgInputDoc :: InputDoc
    , _cgChars :: Set Char
    , cgDocHandler :: DocHandler (Char -> a)
    } deriving (Generic, Functor)
Lens.makeLenses ''CharGroupHandler

cgDocs :: Lens.IndexedTraversal' InputDoc (CharGroupHandler a) Doc
cgDocs f CharGroupHandler{..} =
    CharGroupHandler cgInputDoc _cgChars
    <$> dhDoc (Lens.indexed f cgInputDoc) cgDocHandler

-- File path (drag&)drop handler
data DropHandler a = DropHandler
    { dropHandlerInputDoc :: InputDoc
    , _dropDocHandler :: DocHandler ([FilePath] -> Maybe a)
    } deriving (Generic, Functor)
Lens.makeLenses ''DropHandler

dropHandlerDocs :: Lens.IndexedTraversal' InputDoc (DropHandler a) Doc
dropHandlerDocs f DropHandler{..} =
    DropHandler dropHandlerInputDoc
    <$> dhDoc (Lens.indexed f dropHandlerInputDoc) _dropDocHandler

data MaybeWantsClipboard a
    = Doesn'tWantClipboard a
    | WantsClipboard (Clipboard -> a)
    deriving (Functor)

type KeyMap a = Map KeyEvent (DocHandler (MaybeWantsClipboard a))

data EventMap a = EventMap
    { _emKeyMap :: KeyMap a
    , _emDropHandlers :: [DropHandler a]
    , _emCharGroupHandlers :: [CharGroupHandler a]
    , _emCharGroupChars :: Set Char
    , _emAllCharsHandler :: [AllCharsHandler a]
    } deriving (Generic, Functor)

prettyKeyEvent :: KeyEvent -> InputDoc
prettyKeyEvent (KeyEvent GLFW.KeyState'Pressed modKey) = ModKey.pretty modKey
prettyKeyEvent (KeyEvent GLFW.KeyState'Repeating modKey) = "Repeat " <> ModKey.pretty modKey
prettyKeyEvent (KeyEvent GLFW.KeyState'Released modKey) = "Depress " <> ModKey.pretty modKey

emDocs :: Lens.IndexedTraversal' InputDoc (EventMap a) Doc
emDocs f EventMap{..} =
    EventMap
    <$> (Lens.reindexed prettyKeyEvent Lens.itraversed <. dhDoc) f _emKeyMap
    <*> (Lens.traverse .> dropHandlerDocs) f _emDropHandlers
    <*> (Lens.traverse .> cgDocs) f _emCharGroupHandlers
    <*> pure _emCharGroupChars
    <*> (Lens.traverse .> chDocs) f _emAllCharsHandler

Lens.makeLenses ''EventMap

instance Monoid (EventMap a) where
    mempty = EventMap mempty mempty mempty mempty mempty
    mappend = overrides

overrides :: EventMap a -> EventMap a -> EventMap a
overrides
    x@(EventMap xMap xDropHandlers xCharGroups xChars xMAllChars)
    (EventMap yMap yDropHandlers yCharGroups yChars yMAllChars) =
    EventMap
    (xMap `mappend` filteredYMap)
    (xDropHandlers ++ yDropHandlers)
    (xCharGroups ++ filteredYCharGroups)
    (xChars `mappend` yChars)
    (xMAllChars ++ yMAllChars)
    where
        filteredYMap = filterByKey (not . isKeyConflict) yMap
        isKeyConflict (KeyEvent _ (ModKey mods key))
            | isCharMods mods =
                maybe False (isCharConflict x) $ charOfKey key
            | otherwise = False
        filteredYCharGroups =
            filterCharGroups (not . isCharConflict x) yCharGroups

filterCharGroups ::
    (Char -> Bool) ->
    [CharGroupHandler a] ->
    [CharGroupHandler a]
filterCharGroups f =
    filter (not . Set.null . (^. cgChars)) .
    (Lens.traversed . cgChars %~ Set.filter f)

isCharConflict :: EventMap a -> Char -> Bool
isCharConflict eventMap char =
    char `Set.member` (eventMap ^. emCharGroupChars) ||
    (not . null . catMaybes)
    (($ char) . (^. chDocHandler . dhHandler) <$>
      eventMap ^. emAllCharsHandler)

filterChars
    :: (Char -> Bool) -> EventMap a -> EventMap a
filterChars p =
    (emCharGroupHandlers %~ filterCharGroups p) .
    (emCharGroupChars %~ Set.filter p) .
    (emAllCharsHandler . Lens.traversed . chDocHandler . dhHandler %~ f)
    where
        f handler c = do
            guard $ p c
            handler c

isCharMods :: GLFW.ModifierKeys -> Bool
isCharMods modKeys =
        not $ any ($ modKeys)
        [ GLFW.modifierKeysSuper
        , GLFW.modifierKeysControl
        , GLFW.modifierKeysAlt
        ]

-- TODO: Remove this:
mkModKey :: GLFW.ModifierKeys -> GLFW.Key -> ModKey
mkModKey = ModKey

filterByKey :: (k -> Bool) -> Map k v -> Map k v
filterByKey p = Map.filterWithKey (const . p)

deleteKey :: KeyEvent -> EventMap a -> EventMap a
deleteKey key = emKeyMap %~ Map.delete key

deleteKeys :: [KeyEvent] -> EventMap a -> EventMap a
deleteKeys = foldr ((.) . deleteKey) id

lookup :: Applicative f => f (Maybe Clipboard) -> Events.Event -> EventMap a -> f (Maybe a)
lookup _ (Events.EventDropPaths paths) eventMap =
    map applyHandler (eventMap ^. emDropHandlers) & asum & pure
    where
        applyHandler dh = dh ^. dropDocHandler . dhHandler $ paths
lookup getClipboard (Events.EventKey event) eventMap
    | Just action <- lookupKeyMap getClipboard dict event = action
    | Just res <- lookupCharGroup charGroups event = pure (Just res)
    | Just res <- lookupAllCharHandler allCharHandlers event = pure (Just res)
    | otherwise = pure Nothing
    where
        EventMap dict _dropHandlers charGroups _ allCharHandlers = eventMap
lookup _ _ _ = pure Nothing

lookupKeyMap ::
    Applicative f => f (Maybe Clipboard) -> KeyMap a -> Events.KeyEvent ->
    Maybe (f (Maybe a))
lookupKeyMap getClipboard dict (Events.KeyEvent k _scanCode keyState modKeys _) =
      KeyEvent keyState modKey `Map.lookup` dict
      <&> (^. dhHandler)
      <&> \case
          Doesn'tWantClipboard x -> pure (Just x)
          WantsClipboard f -> getClipboard <&> fmap f
    where
        modKey = mkModKey modKeys k

lookupCharGroup :: [CharGroupHandler a] -> Events.KeyEvent -> Maybe a
lookupCharGroup charGroups (Events.KeyEvent _k _scanCode keyState _modKeys mchar) =
    listToMaybe $
    do
        GLFW.KeyState'Pressed <- return keyState
        char <- mchar ^.. Lens._Just
        CharGroupHandler _ chars handler <- charGroups
        guard $ Set.member char chars
        [(handler ^. dhHandler) char]

lookupAllCharHandler :: [AllCharsHandler t] -> Events.KeyEvent -> Maybe t
lookupAllCharHandler allCharHandlers (Events.KeyEvent _k _scanCode keyState _modKeys mchar) =
    listToMaybe $
    do
        GLFW.KeyState'Pressed <- return keyState
        char <- mchar ^.. Lens._Just
        AllCharsHandler _ handler <- allCharHandlers
        (handler ^. dhHandler) char ^.. Lens._Just

charGroup :: InputDoc -> Doc -> String -> (Char -> a) -> EventMap a
charGroup iDoc oDoc chars handler =
    mempty
    { _emCharGroupHandlers =
            [CharGroupHandler iDoc s (DocHandler oDoc handler)]
    , _emCharGroupChars = s
    }
    where
        s = Set.fromList chars

-- low-level "smart constructor" in case we need to enforce
-- invariants:
charEventMap
    :: InputDoc -> Doc -> (Char -> Maybe a) -> EventMap a
charEventMap iDoc oDoc handler =
    mempty
    { _emAllCharsHandler =
        [AllCharsHandler iDoc (DocHandler oDoc handler)]
    }

allChars :: InputDoc -> Doc -> (Char -> a) -> EventMap a
allChars iDoc oDoc f = charEventMap iDoc oDoc $ Just . f

keyEventMapH :: KeyEvent -> Doc -> MaybeWantsClipboard a -> EventMap a
keyEventMapH eventType doc handler =
    mempty
    { _emKeyMap =
      Map.singleton eventType (DocHandler doc handler)
    }

keyEventMap :: KeyEvent -> Doc -> a -> EventMap a
keyEventMap eventType doc handler = keyEventMapH eventType doc (Doesn'tWantClipboard handler)

keyPress :: ModKey -> Doc -> a -> EventMap a
keyPress key = keyEventMap (KeyEvent GLFW.KeyState'Pressed key)

keyPresses :: [ModKey] -> Doc -> a -> EventMap a
keyPresses = mconcat . map keyPress

keyPressOrRepeat :: ModKey -> Doc -> a -> EventMap a
keyPressOrRepeat key doc res =
    keyEventMap (KeyEvent GLFW.KeyState'Pressed key) doc res <>
    keyEventMap (KeyEvent GLFW.KeyState'Repeating key) doc res

dropEventMap :: InputDoc -> Doc -> ([FilePath] -> Maybe a) -> EventMap a
dropEventMap iDoc oDoc handler =
    mempty { _emDropHandlers = [DropHandler iDoc (DocHandler oDoc handler)] }

pasteOnKey :: ModKey -> Doc -> (Clipboard -> a) -> EventMap a
pasteOnKey key doc handler =
    keyEventMapH (KeyEvent GLFW.KeyState'Pressed key) doc (WantsClipboard handler)