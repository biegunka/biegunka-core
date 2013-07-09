{-# LANGUAGE DataKinds #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE KindSignatures #-}
{-# LANGUAGE Rank2Types #-}
-- | Specifies configuration language
module Biegunka.Language
  ( Scope(..)
  , Term(..), Action(..), Source(..), Modifier(..)
  , React(..)
  ) where

import Control.Applicative((<$>))
import Data.Foldable (Foldable(..))
import Data.Traversable (Traversable(..), fmapDefault, foldMapDefault)

import Control.Monad.Free (Free(..))
import Data.Copointed (Copointed(..))
import Data.Default (Default(..))
import Data.Text.Lazy (Text)
import System.Process (CmdSpec)
import Text.StringTemplate (ToSElem)
import Text.StringTemplate.GenericStandard ()


-- | Language terms scopes [kind]
data Scope = Actions | Sources


-- | Language terms datatype.
--
-- "Biegunka.Primitive" contains DSL primitives constructed
-- using these terms (and annotations).
--
-- User should *never* have a need to construct any DSL term using these manually.
--
-- Consists of 2 scopes ('Actions' and 'Sources') and also scope-agnostic modifiers.
data Term :: (Scope -> *) -> Scope -> * -> * where
  TS :: f Sources -> Source -> Free (Term f Actions) () -> x -> Term f Sources x
  TA :: f Actions -> Action -> x -> Term f Actions x
  TM :: Modifier -> x -> Term f s x

instance Functor (Term f s) where
  fmap = fmapDefault
  {-# INLINE fmap #-}

instance Foldable (Term f s) where
  foldMap = foldMapDefault
  {-# INLINE foldMap #-}

instance Traversable (Term f s) where
  traverse f (TS a s i x) = TS a s i <$> f x
  traverse f (TA a z   x) = TA a z   <$> f x
  traverse f (TM   w   x) = TM   w   <$> f x
  {-# INLINE traverse #-}

-- | Peek next 'Term'
instance Copointed (Term f s) where
  copoint (TS _ _ _ x) = x
  copoint (TA _ _   x) = x
  copoint (TM   _   x) = x

-- | 'Sources' scope terms data
data Source = Source {
  -- | Source type
    stype :: String
  -- | URI where source is located
  , suri :: String
  -- | Where to emerge source on FS (relative to Biegunka root setting)
  , spath :: FilePath
  -- | How to update source
  , supdate :: FilePath -> IO ()
  }

-- | 'Actions' scope terms data
data Action =
    -- | Symbolic link
    Link FilePath FilePath
    -- | Verbatim copy
  | Copy FilePath FilePath
    -- | Copy with template substitutions
  | Template FilePath FilePath (forall t. ToSElem t => t -> String -> Text)
    -- | External command
  | Command FilePath CmdSpec

-- | Modificators for other datatypes
data Modifier =
    User (Maybe String)
  | Reacting (Maybe React)
  | Chain

-- | Failure reaction
data React = Ignorant | Abortive | Retry
  deriving (Show, Read, Eq, Ord, Enum, Bounded)

instance Default React where
  def = Ignorant
