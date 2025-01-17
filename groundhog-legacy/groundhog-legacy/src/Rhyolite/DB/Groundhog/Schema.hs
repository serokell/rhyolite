{-# Language GeneralizedNewtypeDeriving #-}
{-# Language RankNTypes #-}
{-# Language ScopedTypeVariables #-}
{-# Language StandaloneDeriving #-}
{-# options_ghc -fno-warn-orphans #-}
module Rhyolite.DB.Groundhog.Schema where

import Control.Arrow ((&&&))
import Control.Exception
import Data.Aeson (FromJSON, ToJSON, eitherDecode', encode)
import Data.Functor.Identity (Identity(..))
import qualified Data.Map as Map
import Data.Text (Text)
import qualified Data.Text as T
import Data.Typeable (Proxy(..), TypeRep, Typeable, typeRep)
import Data.Universe
import Database.Groundhog.Core
import Database.Groundhog.Generic.Sql ()
import Database.Id.Class
import Database.PostgreSQL.Simple.Class
import Database.PostgreSQL.Simple.FromField (Conversion, FromField, conversionError, fromField)
import Database.PostgreSQL.Simple.ToField (Action, ToField, toField)
import Database.PostgreSQL.Simple.Types (Binary(..), Identifier(..))

import Rhyolite.DB.Groundhog.Schema.Class (DerivedEntity, DerivedEntityHead)
import Rhyolite.Schema (Json(..), SchemaName(..))

instance ToField SchemaName where
  toField (SchemaName t) = toField (Identifier t)

deriving instance PrimitivePersistField SchemaName

instance NeverNull SchemaName

instance PersistField LargeObjectId where
  persistName _ = "LargeObjectId"
  toPersistValues (LargeObjectId n) = toPersistValues n
  fromPersistValues pv = do
    (x, pv') <- fromPersistValues pv
    return (LargeObjectId x, pv')
  dbType _ _ = DbTypePrimitive
    (DbOther $ OtherTypeDef [Left "oid"]) -- From https://www.postgresql.org/docs/current/static/lo-funcs.html
    False -- Not nullable
    Nothing -- No default value
    Nothing -- No parent table reference

deriving instance PrimitivePersistField LargeObjectId

instance NeverNull LargeObjectId

instance (Typeable a, ToJSON a, FromJSON a) => PersistField (Json a) where
  --TODO: Should this include the name of the underlying type
  persistName _ = "Json"
  toPersistValues (Json a) = toPersistValues (encode a)
  fromPersistValues vs = do
    (r, vs') <- fromPersistValues vs
    case eitherDecode' r of
      Left err -> error $ show (typeRep (Proxy :: Proxy a)) <> ":" <> err
      Right r' -> return (Json r', vs')
  dbType p (Json a) = dbType p (encode a)

instance (Typeable a, ToJSON a, FromJSON a) => PrimitivePersistField (Json a) where
  toPrimitivePersistValue p (Json a) = toPrimitivePersistValue p (encode a)
  fromPrimitivePersistValue p v = runIdentity $ do
    r <- either error return $ eitherDecode' $ fromPrimitivePersistValue p v
    return (Json r)

instance ToJSON a => ToField (Json a) where
  toField (Json j) = toField $ Binary $ encode j

instance (Typeable a, FromJSON a) => FromField (Json a) where
  fromField f mb = do
    Binary v <- fromField f mb
    let ev = eitherDecode' v
    case ev of
      Left err -> fail $ show (typeRep (Proxy :: Proxy a)) <> ":" <> err
      Right v' -> return $ Json v'

instance NeverNull (Json a)

fromDerivedId :: DerivedEntity v => Id v -> Id (DerivedEntityHead v)
fromDerivedId = Id . unId

toDerivedId :: DerivedEntity v => Id (DerivedEntityHead v) -> Id v
toDerivedId = Id . unId

newtype VisibleUniverseFailure = VisibleUniverseFailure TypeRep
  deriving (Show)

fromShowUniverse :: forall a. (Typeable a, Universe a, Show a) => Text -> Conversion a
fromShowUniverse = maybe failUniv pure . univMap
  where
    pa :: Proxy a = Proxy
    univ :: [a] = universe
    failUniv :: Conversion a = conversionError $ VisibleUniverseFailure (typeRep pa)
    univMap = flip Map.lookup (Map.fromList $ (T.pack . show &&& id) <$> univ)

toShowUniverse :: forall a. Show a => a -> Action
toShowUniverse = toField . T.pack . show

instance Exception VisibleUniverseFailure

instance PersistField SchemaName where
  persistName _ = "SchemaName"
  toPersistValues (SchemaName x) = toPersistValues x
  fromPersistValues pv = do
    (x, pv') <- fromPersistValues pv
    return (SchemaName x, pv')
  dbType p (SchemaName x) = dbType p x
