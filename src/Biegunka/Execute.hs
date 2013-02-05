{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DeriveDataTypeable #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# OPTIONS_HADDOCK prune #-}
module Biegunka.Execute (execute, BiegunkaException(..)) where

import Control.Applicative
import Control.Monad (when)
import Control.Exception.Lifted (Exception, SomeException(..), throwIO, try)
import Data.Char (toUpper)
import Data.List ((\\))
import Data.Monoid ((<>))
import Data.Foldable (traverse_)
import Data.Function (fix)
import Data.Typeable (Typeable)
import System.Exit (ExitCode(..))
import System.IO (hFlush, stdout)
import System.IO.Error (catchIOError, tryIOError)

import           Control.Lens hiding (Action)
import           Data.Default (def)
import           Control.Monad.Free (Free(..))
import           Control.Monad.Reader (ReaderT, runReaderT)
import           Control.Monad.State (StateT, evalStateT)
import           Control.Monad.Trans (MonadIO, liftIO)
import           Data.Proxy
import           Data.Reflection
import           Data.Text (Text)
import           Data.Text.Lazy (toStrict)
import qualified Data.Text as T
import qualified Data.Text.IO as T
import           System.Directory
  ( getCurrentDirectory, removeDirectoryRecursive, removeFile, setCurrentDirectory
  , copyFile, createDirectoryIfMissing
  )
import           System.FilePath (dropFileName)
import           System.Posix.Files (createSymbolicLink, removeLink)
import           System.Posix.Env (getEnv)
import           System.Posix.User (getEffectiveUserName, getUserEntryForName, userID, setEffectiveUserID)
import           System.Process (system)

import Biegunka.Control (Interpreter(..))
import Biegunka.DB
import Biegunka.Execute.Narrator
import Biegunka.Execute.State
import Biegunka.Language (Command(..), Action(..), Wrapper(..), React(..), next)


type Execution a = StateT ES IO a
type Task l a = Free (Command l ()) a


-- | Execute Interpreter
--
-- Execute script. Copy and links files, compiles stuff. You get the idea
--
-- Supports some options
--
-- @
-- main :: IO ()
-- main = execute (def & react .~ Ignorant) $ do
--   profile ...
--   profile ...
-- @
execute :: EE -> Interpreter
execute e = I $ \s -> do
  let b = construct s
  a <- load s
  when (e ^. priviledges == Drop) $ getEnv "SUDO_USER" >>= traverse_ setUser
  n <- narrator (_volubility e)
  runTask e n s
  mapM (tryIOError . removeFile) (filepaths a \\ filepaths b)
  mapM (tryIOError . removeDirectoryRecursive) (sources a \\ sources b)
  save b


runTask :: EE -> Narrative -> Task l a -> IO ()
runTask e n s = evalStateT (reify (n, e) (fold s)) def


-- | Custom execptions
data BiegunkaException =
    ShellCommandFailure String -- ^ Shell reports errors
  | SourceEmergingFailure String FilePath Text -- ^ Source emerging routine reports errors
  | ExecutionAbortion -- ^ User aborts script
    deriving (Typeable)


instance Show BiegunkaException where
  show = T.unpack . T.unlines . filter (not . T.null) . T.lines . pretty
   where
    pretty ExecutionAbortion = "Biegunka has aborted"
    pretty (ShellCommandFailure t) =
      "Biegunka has failed to execute `" <> T.pack t <> "`"
    pretty (SourceEmergingFailure up fp fs) =
      "Biegunka has failed to emerge source " <> T.pack up <> " in " <> T.pack fp <> "\nFailures log:\n" <> fs

instance Exception BiegunkaException


-- | Single command execution and exception handling
fold :: Reifies s (Narrative, EE) => Free (Command l ()) a -> Proxy s -> Execution ()
fold (Free command) p = do
  try (execute' command p) >>= \t -> case t of
    Left (SomeException e) -> do
      io . T.putStrLn $ "FAIL: " <> T.pack (show e)
      fmap (<|> [view (_2 . react) $ reflect p]) (use reactStack) >>= \(o:_) -> case o of
        Ignorant -> ignore command
        Asking -> fix $ \ask -> map toUpper <$> prompt "[I]gnore, [R]etry, [A]bort? " >>= \c -> case c of
          "I" -> ignore command
          "R" -> fold (Free command) p
          "A" -> io $ throwIO ExecutionAbortion
          _ -> ask
        Abortive -> io $ throwIO ExecutionAbortion
    _ -> fold (next command) p
 where
  prompt msg = io $ putStr msg >> hFlush stdout >> getLine

  ignore S {} = fold (dropCommands skip (next command)) p
  ignore _    = fold (next command) p

  skip P {} = False
  skip S {} = False
  skip (W _ (Free x)) = skip x
  skip _ = True
fold (Pure _) _ = return ()


-- | Command execution
execute' :: Reifies s (Narrative, EE) => Command l t a -> Proxy s -> Execution ()
execute' c p = case c of
  S url path _ update _ -> do
    narrate p (Typical $ "Emerging source: " ++ url)
    io $ update path

  F (RegisterAt src dst) _ -> io $ overWriteWith createSymbolicLink src dst
  F (Link src dst) _       -> io $ overWriteWith createSymbolicLink src dst
  F (Copy src dst) _       -> io $ overWriteWith copyFile src dst
  F (Template src dst substitute) _ -> do
    Templates ts <- return $ view (_2 . templates) (reflect p)
    io $ overWriteWith (\s d -> toStrict . substitute ts . T.unpack <$> T.readFile s >>= T.writeFile d) src dst
  F (Shell p sc) _         -> io $ do
    d <- getCurrentDirectory
    setCurrentDirectory p
    flip catchIOError (\_ -> throwIO $ ShellCommandFailure sc) $ do
      e <- system sc
      case e of
        ExitFailure _ -> throwIO $ ShellCommandFailure sc
        _ -> return ()
    setCurrentDirectory d

  W (Reacting (Just r)) _  -> reactStack %= (r :)
  W (Reacting Nothing) _   -> reactStack %= drop 1
  W (User (Just n)) _      -> io getEffectiveUserName >>= \u -> setUser n >> userStack %= (u :)
  W (User Nothing) _       -> use userStack >>= \(u:us) -> setUser u >> userStack .= us

  _ -> return ()
 where
  overWriteWith g src dst = do
    createDirectoryIfMissing True $ dropFileName dst
    tryIOError (removeLink dst) -- needed because removeLink throws an unintended exception if file is absent
    g src dst


dropCommands :: (Command l s (Free (Command l s) b) -> Bool) -> Free (Command l s) b -> Free (Command l s) b
dropCommands f p@(Free c)
  | f c = dropCommands f (next c)
  | otherwise    = p
dropCommands _ x@(Pure _) = x


setUser :: MonadIO m => String -> m ()
setUser n = io $ getUserEntryForName n >>= setEffectiveUserID . userID


io :: MonadIO m => IO a -> m a
io = liftIO
