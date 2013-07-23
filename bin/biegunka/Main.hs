{-# LANGUAGE OverloadedStrings #-}
module Main where

import           Control.Concurrent (forkFinally)
import           Control.Concurrent (forkIO)
import           Control.Concurrent.MVar (newEmptyMVar, putMVar, takeMVar)
import           Control.Lens hiding ((<.>))
import           Control.Monad (forever)
import           Control.Monad.Trans.Either
import           Control.Monad.IO.Class (liftIO)
import           Data.Char (toLower)
import           Data.List (intercalate, isPrefixOf, partition)
import           Data.Monoid (Monoid(..), (<>))
import qualified Data.Text.Lazy.IO as T
import           Data.Version (Version(..))
import           Options.Applicative (customExecParser, prefs, showHelpOnError)
import qualified System.Directory as D
import           System.Exit (ExitCode(..), exitWith)
import           System.IO (hFlush, hSetBuffering, BufferMode(..), stdout)
import           System.Process (getProcessExitCode, runInteractiveProcess)
import           System.Info (arch, os, compilerName, compilerVersion)
import           System.Wordexp (wordexp, nosubst, noundef)

import List (list)
import Options
import Paths_biegunka


main :: IO ()
main = do
  hSetBuffering stdout NoBuffering
  biegunkaCommand <- customExecParser (prefs showHelpOnError) opts
  case biegunkaCommand of
    Init destination               -> initialize destination
    Script destination script args -> withScript destination script args
    List datadir format profiles   -> list datadir profiles format


initialize :: FilePath -> IO ()
initialize destination = do
  template <- getDataFileName "data/biegunka-init.template"
  destinationExists <- D.doesFileExist destination
  case destinationExists of
    True -> do
      response <- prompt $ destination ++ " already exists! Overwrite?"
      case response of
        True  -> move template
        False -> do
          putStrLn $ "Failed to initialize biegunka script: Already Exists"
          exitWith (ExitFailure 1)
    False -> move template
 where
  move :: FilePath -> IO ()
  move source = do
    D.copyFile source destination
    putStrLn $ "Initialized biegunka script at " ++ destination


withScript :: FilePath -> Script -> [String] -> IO ()
withScript destination script args = do
  let (biegunkaArgs, ghcArgs) = partition ("--" `isPrefixOf`) args
  packageDBArg <- if any ("-package-db" `isPrefixOf`) ghcArgs
                     then return (Right ())
                     else findPackageDBArg
  packageDBArg^!_Left.act (putStrLn . mappend "* Found cabal package DB at ")
  (stdin', stdout', stderr', pid) <- runInteractiveProcess "runhaskell"
         (ghcArgs
      ++ either (\packageDB -> ["-package-db=" ++ packageDB]) (const []) packageDBArg
      ++ [destination, toScriptOption script]
      ++ biegunkaArgs)
    Nothing
    Nothing
  hSetBuffering stdin' NoBuffering
  -- Can't use waitForProcess here because runhaskell ignores -threaded
  -- and we want to support runhaskell because compiling scripts is not cool
  stdoutAnchor <- newEmptyMVar
  stderrAnchor <- newEmptyMVar
  listen stdoutAnchor stdout'
  listen stderrAnchor stderr'
  tell stdin'
  takeMVar stdoutAnchor
  takeMVar stderrAnchor
  exitcode <- getProcessExitCode pid
  exitWith (maybe (ExitFailure 1) id exitcode)
 where
  listen mvar handle = forkFinally (forever $ T.hGetContents handle >>= T.putStr)
    (\_ -> putMVar mvar ())
  tell handle = forkIO . forever $ T.getLine >>= T.hPutStrLn handle


findPackageDBArg :: IO (Either String ())
findPackageDBArg = runEitherT $ do
  findCabalSandbox
  findCabalDevSandbox
 where
  findCabalSandbox    =
    findSandbox $ "cabal-dev/packages-" ++ compilerVersionString compilerVersion ++ "*.conf"
  findCabalDevSandbox =
    findSandbox $
         ".cabal-sandbox/" ++ arch ++ "-" ++ os ++ "-" ++ compilerName ++ "-"
      ++ compilerVersionString compilerVersion ++ "*-packages.conf.d"

  findSandbox :: String -> EitherT String IO ()
  findSandbox pattern = do
    findings <- liftIO $ wordexp (nosubst <> noundef) pattern
    case findings of
      Right [sandbox]
        | sandbox /= pattern -> left sandbox
      Right (sandbox:_:_) -> do
        liftIO . putStrLn $ "Found multiple sandboxes, going with " ++ sandbox ++ ", sorry!"
        left sandbox
      _ -> right ()

  compilerVersionString = intercalate "." . map show . versionBranch


prompt :: String -> IO Bool
prompt message = do
  putStr $ message ++ " [y/n] "
  hFlush stdout
  response <- getLine
  case map toLower response of
    "y" -> return True
    "n" -> return False
    _   -> prompt message