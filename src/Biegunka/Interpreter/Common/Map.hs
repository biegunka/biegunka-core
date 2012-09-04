{-# LANGUAGE ScopedTypeVariables #-}
{-# OPTIONS_HADDOCK hide #-}
module Biegunka.Interpreter.Common.Map (construct) where

import Data.Monoid (Monoid(..), (<>))

import           Control.Monad.Free (Free(..))
import           Data.Map (Map)
import qualified Data.Map as M
import           Data.Set (Set)
import qualified Data.Set as S

import Biegunka.DSL (Profile(..), Source(..), Files(..), foldie)


construct ∷ Free (Profile (Free (Source (Free Files ())) ())) () → Map String (Map FilePath (Set FilePath))
construct = profile


profile ∷ Free (Profile (Free (Source (Free Files ())) ())) () → Map String (Map FilePath (Set FilePath))
profile s = foldie ($) mempty s f
 where
  f (Profile name s' _) = M.insertWith' mappend name (source s')


source ∷ Free (Source (Free Files ())) () → Map FilePath (Set FilePath)
source s = foldie (<>) mempty s f
 where
  f (Git _ path s' _) = M.singleton path (files s')


files ∷ Free Files () → Set FilePath
files s = foldie (<>) mempty s f
 where
  f (Message _ _) = mempty
  f (RegisterAt _ dst _) = S.singleton dst
  f (Link _ dst _) = S.singleton dst
  f (Copy _ dst _) = S.singleton dst
  f (Compile _ _ dst _) = S.singleton dst
