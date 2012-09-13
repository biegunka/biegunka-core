{-# LANGUAGE GADTs #-}
{-# OPTIONS_HADDOCK prune #-}
module Biegunka.Interpreter.Execute (execute) where

import Control.Monad (forM_, unless, when)
import Data.Function (on)
import Data.Monoid (mempty)

import Control.Lens ((^.))
import Control.Monad.Free (Free(..))
import Data.Default (Default)
import System.Directory (getHomeDirectory, removeDirectoryRecursive, removeFile)

import           Biegunka.DB
import           Biegunka.DSL
  ( ProfileScript
  , Command(..)
  , update, script
  , Profile, Source, Files
  , foldie)
import qualified Biegunka.Interpreter.Common.Map as Map
import           Biegunka.Interpreter.Common.State
import           Biegunka.Interpreter.IO (issue)


-- | Execute Interpreter
--
-- Execute script. Copy and links files, compiles stuff. You get the idea
--
-- @
-- main ∷ IO ()
-- main = execute $ do
--   profile ...
--   profile ...
-- @
execute ∷ (Default s, Default t) ⇒ ProfileScript s t () → IO ()
execute s = do
  home ← getHomeDirectory
  let s' = infect home s
  α ← load
  when (α == mempty) $
    putStrLn "Warning: Biegunka is empty"
  profile s'
  let β = Map.construct s'
  removeOrphanFiles α β
  removeOrphanRepos α β
  save β
 where
  removeOrphanFiles = removeOrphan removeFile filepaths
  removeOrphanRepos = removeOrphan removeDirectoryRecursive sources

  removeOrphan f g = removeIfNotElem f `on` g
  removeIfNotElem f xs ys = forM_ xs $ \x → unless (x `elem` ys) $ f x


profile ∷ Free (Command Profile (Free (Command Source (Free (Command Files ()) ())) ())) () → IO ()
profile = foldie (>>) (return ()) f
 where
  f ∷ Command Profile (Free (Command Source (Free (Command Files ()) ())) ()) a → IO ()
  f (Profile _ s _) = source s


source ∷ Free (Command Source (Free (Command Files ()) ())) () → IO ()
source = foldie (>>) (return ()) f
 where
  f s = (s^.update) >> files (s^.script)


files ∷ Free (Command Files ()) a → IO ()
files = foldie (>>) (return ()) issue
