module Lamdu.Sugar.Convert.Hole.ResultScore
    ( resultScore
    ) where

import qualified Control.Lens as Lens
import qualified Data.Map as Map
import           Data.Tree.Diverse (Ann(..), val)
import qualified Lamdu.Calc.Lens as ExprLens
import           Lamdu.Calc.Term (Val)
import qualified Lamdu.Calc.Term as V
import           Lamdu.Calc.Type (Type(..), Composite(..))
import qualified Lamdu.Infer as Infer
import           Lamdu.Sugar.Types.Parts (HoleResultScore(..))

import           Lamdu.Prelude

resultTypeScore :: Type -> [Int]
resultTypeScore (TVar _) = [0]
resultTypeScore (TInst _ p) = 1 : maximum ([] : map resultTypeScore (Map.elems p))
resultTypeScore (TFun a r) = 2 : max (resultTypeScore a) (resultTypeScore r)
resultTypeScore (TVariant c) = 2 : compositeTypeScore c
resultTypeScore (TRecord c) = 2 : compositeTypeScore c

compositeTypeScore :: Composite t -> [Int]
compositeTypeScore CEmpty = []
compositeTypeScore (CVar _) = [1]
compositeTypeScore (CExtend _ t r) =
    max (resultTypeScore t) (compositeTypeScore r)

score :: Val Infer.Payload -> [Int]
score (Ann pl body) =
    (if Lens.has ExprLens.valBodyHole body then 1 else 0) :
    resultScopeScore :
    resultTypeScore (pl ^. Infer.plType) ++
    (body ^.. V.termChildren >>= score)
    where
        resultScopeScore =
            case body ^? ExprLens.valBodyVar <&> (`Map.member` Infer.scopeToTypeMap (pl ^. Infer.plScope)) of
            Just False -> 1
            _ -> 0

resultScore :: Val Infer.Payload -> HoleResultScore
resultScore x =
    HoleResultScore
    { _hrsNumFragments = numFragments x
    , _hrsScore = score x
    }

numFragments :: Val a -> Int
numFragments x =
    sum (x ^.. val . V.termChildren <&> numFragments) +
    if Lens.has appliedHole x
    then 1
    else 0

appliedHole :: Lens.Traversal' (Val a) ()
appliedHole = ExprLens.valApply . V.applyFunc . ExprLens.valHole
