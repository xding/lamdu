module Lamdu.Sugar.Convert.GetField
    ( convert
    ) where

import qualified Control.Lens as Lens
import qualified Data.Property as Property
import           Data.Tree.Diverse (ann)
import           Lamdu.Calc.Term (Val)
import qualified Lamdu.Calc.Term as V
import qualified Lamdu.Expr.Lens as ExprLens
import           Lamdu.Sugar.Convert.Expression.Actions (addActions)
import qualified Lamdu.Sugar.Convert.Input as Input
import           Lamdu.Sugar.Convert.Monad (ConvertM)
import qualified Lamdu.Sugar.Convert.Monad as ConvertM
import           Lamdu.Sugar.Convert.Tag (convertTag)
import           Lamdu.Sugar.Internal
import qualified Lamdu.Sugar.Internal.EntityId as EntityId
import           Lamdu.Sugar.Types
import qualified Revision.Deltum.Transaction as Transaction

import           Lamdu.Prelude

convertGetFieldParam ::
    (Monad m, Monoid a) =>
    V.GetField (Val (Input.Payload m a)) -> Input.Payload m a ->
    ConvertM m (Maybe (ExpressionU m a))
convertGetFieldParam (V.GetField recExpr tag) exprPl =
    do
        tagParamInfos <- Lens.view (ConvertM.scScopeInfo . ConvertM.siTagParamInfos)
        do
            paramInfo <- tagParamInfos ^? Lens.ix tag . ConvertM._TagFieldParam
            param <- recExpr ^? ExprLens.valVar
            guard $ param == ConvertM.tpiFromParameters paramInfo
            GetParam ParamRef
                { _pNameRef = NameRef
                  { _nrName = nameWithContext param tag
                  , _nrGotoDefinition = ConvertM.tpiJumpTo paramInfo & pure
                  }
                , _pBinderMode = NormalBinder
                } & BodyGetVar & Just
            & Lens._Just %%~ addActions [recExpr] exprPl

convertGetFieldNonParam ::
    (Monad m, Monoid a) =>
    V.GetField (Val (Input.Payload m a)) -> Input.Payload m a ->
    ConvertM m (ExpressionU m a)
convertGetFieldNonParam (V.GetField recExpr tag) exprPl =
    GetField
    <$> ConvertM.convertSubexpression recExpr
    <*> do
            protectedSetToVal <- ConvertM.typeProtectedSetToVal
            let setTag newTag =
                    do
                        V.GetField recExprI newTag & V.BGetField & Transaction.writeIRef valI
                        protectedSetToVal recExprStored recExprI & void
            convertTag tag nameWithoutContext mempty (EntityId.ofTag (exprPl ^. Input.entityId)) setTag
    <&> BodyGetField
    >>= addActions [recExpr] exprPl
    where
        valI = exprPl ^. Input.stored . Property.pVal
        recExprStored = recExpr ^. ann . Input.stored
        recExprI = recExprStored ^. Property.pVal

convert ::
    (Monad m, Monoid a) =>
    V.GetField (Val (Input.Payload m a)) ->
    Input.Payload m a ->
    ConvertM m (ExpressionU m a)
convert getField exprPl =
    convertGetFieldParam getField exprPl
    >>= maybe (convertGetFieldNonParam getField exprPl) pure
