{-# LANGUAGE TemplateHaskell #-}

module GUI.Momentu.Animation
    ( R, Size
    , Image(..), iAnimId, iUnitImage, iRect
    , Frame(..), frameImages, unitImages, images
    , draw
    , mapIdentities
    , unitSquare, emptyRectangle
    , coloredRectangle
    , translate, scale
    , singletonFrame
    , module GUI.Momentu.Animation.Id
    ) where

import           Control.DeepSeq (NFData(..), deepseq)
import           Control.DeepSeq.Generics (genericRnf)
import qualified Control.Lens as Lens
import           Data.Vector.Vector2 (Vector2(..))
import           GUI.Momentu.Animation.Id
import           GUI.Momentu.Rect (Rect(Rect))
import qualified GUI.Momentu.Rect as Rect
import           Graphics.DrawingCombinators (R, (%%))
import qualified Graphics.DrawingCombinators.Extended as Draw

import           Lamdu.Prelude

type Size = Vector2 R

data Image = Image
    { _iAnimId :: AnimId
    , _iUnitImage :: !(Draw.Image ())
        -- iUnitImage always occupies (0,0)..(1,1),
        -- the translation/scaling occurs when drawing
    , _iRect :: !Rect
    } deriving (Generic)
Lens.makeLenses ''Image
instance NFData Image where
    rnf (Image animId _image rect) = animId `deepseq` rect `deepseq` ()

newtype Frame = Frame
    { _frameImages :: [Image]
    } deriving (Generic)
Lens.makeLenses ''Frame
instance NFData Frame where rnf = genericRnf

{-# INLINE images #-}
images :: Lens.Traversal' Frame Image
images = frameImages . traverse

{-# INLINE unitImages #-}
unitImages :: Lens.Traversal' Frame (Draw.Image ())
unitImages = images . iUnitImage

singletonFrame :: Size -> AnimId -> Draw.Image () -> Frame
singletonFrame size animId =
    scale size .
    singletonUnitImage .
    (Draw.scaleV (1 / size) %%)
    where
        singletonUnitImage image = Frame [Image animId image (Rect 0 1)]

instance Semigroup Frame where
    Frame m0 <> Frame m1 = Frame (m0 ++ m1)
instance Monoid Frame where
    mempty = Frame mempty
    mappend = (<>)

draw :: Frame -> Draw.Image ()
draw frame =
    frame
    ^. frameImages
    <&> posImage
    & mconcat
    where
        posImage (Image _ img rect) =
            Draw.translateV (rect ^. Rect.topLeft) %%
            Draw.scaleV (rect ^. Rect.size) %%
            img

mapIdentities :: (AnimId -> AnimId) -> Frame -> Frame
mapIdentities f = images . iAnimId %~ f

unitSquare :: AnimId -> Frame
unitSquare animId = singletonFrame 1 animId Draw.square

emptyRectangle :: Vector2 R -> Vector2 R -> AnimId -> Frame
emptyRectangle (Vector2 fX fY) totalSize@(Vector2 sX sY) animId =
    mconcat
    [ rect 0                      (Vector2 sX fY)
    , rect (Vector2 0 (sY - fY))  (Vector2 sX fY)
    , rect (Vector2 0 fY)         (Vector2 fX (sY - fY*2))
    , rect (Vector2 (sX - fX) fY) (Vector2 fX (sY - fY*2))
    ]
    & singletonFrame totalSize animId
    where
        rect origin size =
            Draw.square
            & (Draw.scaleV size %%)
            & (Draw.translateV origin %%)

coloredRectangle :: AnimId -> Draw.Color -> Frame
coloredRectangle animId color =
    unitSquare animId
    & unitImages %~ Draw.tint color

translate :: Vector2 R -> Frame -> Frame
translate pos = images . iRect . Rect.topLeft +~ pos

scale :: Vector2 R -> Frame -> Frame
scale factor = images . iRect . Rect.topLeftAndSize *~ factor
