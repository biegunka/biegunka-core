{-# LANGUAGE DataKinds #-}
{-# LANGUAGE OverloadedStrings #-}
-- | Very simple 'Source' using some existing directory
module Control.Biegunka.Source.Directory (directory) where

import Control.Monad (unless)
import System.Directory (doesDirectoryExist)

import Control.Biegunka.Execute.Exception (sourceFailure)
import Control.Biegunka.Language
import Control.Biegunka.Script


-- | Use the directory located as specified by first argument as 'Source'
directory
  :: FilePath
  -> Script 'Actions ()
  -> Script 'Sources ()
directory relpath inner =
  sourced "directory" relpath relpath inner update
 where
  update abspath = do
    exists <- doesDirectoryExist abspath
    unless exists $
      sourceFailure abspath abspath "No directory found!"
    return Nothing
