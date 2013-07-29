{-# LANGUAGE OverloadedStrings #-}
-- |
-- Basic sanity check
--
-- Checks you /can/ have script with Source under Profile
module Main where

import Control.Biegunka
import Control.Biegunka.Source.Git


main :: IO ()
main = biegunka id (run id) $ do
  git_ "git@github.com:ghc/ghc" "ghc"
