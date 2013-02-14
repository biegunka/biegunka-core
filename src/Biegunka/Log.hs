{-# LANGUAGE DataKinds #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_HADDOCK hide #-}
module Biegunka.Log (full) where

import Control.Monad (forM_, unless)
import Data.Function (on)
import Data.Int (Int64)
import Data.Monoid (Monoid(..), (<>))

import           Control.Monad.Writer (execWriter, tell)
import           Data.Text.Lazy (Text)
import qualified Data.Text.Lazy as T
import           Data.Text.Lazy.Builder (Builder, fromLazyText, fromString, toLazyText)

import Biegunka.DB (Biegunka, filepaths, sources)
import Biegunka.Language (Command(..), Action(..), Wrapper(..))


full :: [Command l () b] -> Biegunka -> Biegunka -> Text
full cs s t = toLazyText $ install cs <> uninstall s t


install :: [Command l () b] -> Builder
install = mconcat . map g


g :: Command l () b -> Builder
g (P name _ _) = "Setup profile " <> string name <> "\n"
g (S t u p _ _ _) = indent 2 <> "Setup " <> string t <> " repository " <> string u <> " at " <> string p <> "\n"
g (F a _) = h a
 where
  h (RegisterAt src dst) = indent 4 <>
    "Link repository " <> string src <> " to " <> string dst <> "\n"
  h (Link src dst) = indent 4 <>
    "Link file " <> string src <> " to " <> string dst <> "\n"
  h (Copy src dst) = indent 4 <>
    "Copy file " <> string src <> " to " <> string dst <> "\n"
  h (Template src dst _) = indent 4 <>
    "Write " <> string src <> " with substituted templates to " <> string dst <> "\n"
  h (Shell p c) = indent 4 <>
    "Shell `" <> string c <> "` from " <> string p <> "\n"
g (W a _) = h a
 where
  h (Reacting _) = mempty
  h (User (Just user)) = "--- * Do stuff from user " <> string user <> " * ---"
  h (User Nothing) = "--- * Do stuff from default user * ---"


indent :: Int64 -> Builder
indent n = fromLazyText $ T.replicate n " "


uninstall :: Biegunka -> Biegunka -> Builder
uninstall α β = (logNotElems `on` filepaths) α β <> (logNotElems `on` sources) α β
 where
  logNotElems xs ys = execWriter (forM_ xs $ \x -> unless (x `elem` ys) (tell $ "Delete " <> string x <> "\n"))


string :: String -> Builder
string = fromString
