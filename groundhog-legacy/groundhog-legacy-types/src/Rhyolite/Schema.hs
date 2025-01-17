-- | Part of the Rhyolite integration with
-- [groundhog](http://hackage.haskell.org/package/groundhog). In particular, we
-- define 'SchemaName' in order to send it across the wire.

{-# Language DefaultSignatures #-}
{-# Language DeriveDataTypeable #-}
{-# Language DeriveGeneric #-}
{-# Language FlexibleContexts #-}
{-# Language GeneralizedNewtypeDeriving #-}
{-# Language RankNTypes #-}
{-# Language ScopedTypeVariables #-}
{-# Language TypeFamilies #-}
{-# Language UndecidableInstances #-}

{-# OPTIONS_GHC -fno-warn-orphans -fno-warn-deprecations #-}
module Rhyolite.Schema where

import Data.Aeson (FromJSON, ToJSON)
import Database.Id.Class
import Control.Category ((>>>))
import Control.Monad.Error (MonadError)
import Data.Text (Text)
import qualified Data.Text as T
import Data.Typeable (Typeable)
import GHC.Generics (Generic)
import Obelisk.Route

newtype SchemaName = SchemaName { unSchemaName :: Text }
  deriving (Eq, Ord, Read, Show, FromJSON, ToJSON, Typeable, Generic)

data WithSchema a = WithSchema SchemaName a
  deriving (Eq, Ord, Read, Show, Typeable, Generic)

withoutSchema :: WithSchema a -> a
withoutSchema (WithSchema _ a) = a

instance (FromJSON a) => FromJSON (WithSchema a)
instance (ToJSON a) => ToJSON (WithSchema a)

instance ShowPretty a => ShowPretty (IdValue a) where
  showPretty (IdValue _ x) = showPretty x

instance Show (IdData a) => ShowPretty (Id a) where
  showPretty = T.pack . show . unId

class ShowPretty a where
  showPretty :: a -> Text
  default showPretty :: Show a => a -> Text
  showPretty = T.pack . show

type Email = Text --TODO: Validation

-- | Wrapper for storing objects as JSON in the DB. Import the instance from
newtype Json a = Json { unJson :: a }
  deriving (Eq, Ord, Show, ToJSON, FromJSON)

idPathSegmentEncoder
  :: forall a check parse.
  (MonadError Text parse, Applicative check, Show (IdData a), Read (IdData a))
  => Encoder check parse (Id a) PageName
idPathSegmentEncoder = idEncoder >>> singlePathSegmentEncoder

idEncoder
  :: forall a check parse.
  (MonadError Text parse, Applicative check, Show (IdData a), Read (IdData a))
  => Encoder check parse (Id a) Text
idEncoder = unsafeMkEncoder EncoderImpl
  { _encoderImpl_encode = showPretty
  , _encoderImpl_decode = \x -> Id <$> tryDecode unsafeTshowEncoder x
  }
