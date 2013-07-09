{-# LANGUAGE CPP #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE TupleSections #-}
-- | Saved profiles data management
module Biegunka.DB
  ( DB(..), Record(..)
  , load, loads, save, construct
  , filepaths, sources
  ) where

import Control.Applicative
import Control.Monad ((<=<), forM, mplus)
import Data.Monoid (Monoid(..))

import           Control.Lens hiding ((.=), (<.>))
import           Control.Monad.Free (Free(..))
import           Control.Monad.State (State, execState)
import           Data.Aeson
import           Data.Aeson.Encode
import           Data.Aeson.Types
import qualified Data.ByteString as B
import qualified Data.ByteString.Lazy as BL
#if defined(__GLASGOW_HASKELL__) && __GLASGOW_HASKELL__ >= 706
import           Data.ByteString.Lazy (fromStrict)
#endif
import           Data.Foldable (toList)
import           Data.Map (Map)
import qualified Data.Map as M
import           Data.Set (Set)
import qualified Data.Text.Lazy.Builder as T
import qualified Data.Text.Lazy.Encoding as T
import           System.Directory (createDirectoryIfMissing, removeDirectory, removeFile)
import           System.FilePath ((</>), (<.>))
import           System.FilePath.Lens (directory)

import Biegunka.Control (Settings, appData)
import Biegunka.Language (Scope(..), Term(..), Source(..), Action(..))
import Biegunka.Script (Annotate(..))


-- | Profiles data
newtype DB = DB
  { _db :: Map String (Map Record (Map FilePath Record))
  } deriving (Show, Read, Eq, Ord, Monoid)

-- | Source record
data Record = Record
  { recordtype :: String
  , base :: FilePath
  , location :: FilePath
  } deriving (Show, Read, Eq, Ord)

instance FromJSON Record where
  parseJSON (Object o) = liftA3 Record (o .: "recordtype") (o .: "base") (o .: "location")
  parseJSON _          = empty

instance ToJSON Record where
  toJSON Record { recordtype = ft, base = bs, location = lc } = object
    [ "recordtype" .= ft
    , "base" .= bs
    , "location" .= lc
    ]

makeLensesWith (defaultRules & generateSignatures .~ False) ''DB

-- | Already constructed mapping
db :: Lens' DB (Map String (Map Record (Map FilePath Record)))


-- | Load profiles mentioned in script
load :: Settings () -> Set String -> IO DB
load c = fmap (DB . M.fromList) . loads c . toList


-- | Load profile data from file
--
-- This may fail, on failure 'loadProfile' returns Nothing
--
-- Reasons to fail:
--
--  * Cannot read from profile file (various reasons here)
--
--  * Cannot parse profile file (wrong format)
loads :: Settings () -> [String] -> IO [(String, Map Record (Map FilePath Record))]
loads c (p:ps) = do
  let name = profileFilePath c p
  Just v <- (parseMaybe parser <=< decode . fromStrict) <$> B.readFile name
  (v:) <$> loads c ps
 `mplus`
  loads c ps
 where
  parser (Object o) = (p, ) . M.fromList <$> do
    ss <- o .: "sources"
    forM ss $ \s -> do
      t  <- s .: "info"
      fs <- s .: "files" >>= mapM parseJSON
      return (t, M.fromList fs)
  parser _ = empty
loads _ [] = return []


-- | Save profiles data to files.
--
-- Each profile is mapped to a separate file in 'appData' directory.
-- Mapping rules are simple: profile name is a relative path in 'appData'.
--
-- For example, profile @dotfiles@ is located in @~\/.biegunka\/dotfiles@ by default
-- and profile @my\/dotfiles@ is located in @~\/.biegunka.my\/dotfiles@ by default.
save :: Settings () -> DB -> IO ()
save c (DB b) = do
  createDirectoryIfMissing False (view appData c)
  ifor_ b $ \p sourceData -> do
    let name = profileFilePath c p
        dir = view directory name
        dirs = dir ^.. takingWhile (/= view appData c) (iterated (view directory))
    if M.null sourceData then do
      removeFile name            -- Since profile is empty no need having crap in the filesystem
      mapM_ removeDirectory dirs -- Also remove empty directories if possible
     `mplus`
      return ()                  -- Ignore failures, they are not critical in any way here
    else do
      createDirectoryIfMissing True dir      -- Create missing directories for nested profile files
      BL.writeFile name $ encode' sourceData -- Finally encode profile as JSON
 where
  encode' = T.encodeUtf8 . T.toLazyText . fromValue . unparser
  unparser t  = object [             "sources" .= map repo   (M.toList t)]
  repo (k, v) = object ["info" .= k, "files"   .= map toJSON (M.toList v)]


-- | Compute profiles' filepaths with current settings
--
-- >>> let settings = def :: Settings ()
--
-- >>> profileFilePath settings ""
-- "~/.biegunka/profiles/.profile"
--
-- >>> profileFilePath settings "dotfiles"
-- "~/.biegunka/profiles/dotfiles.profile"
profileFilePath :: Settings a -> String -> FilePath
profileFilePath settings name =
  settings^.appData.to (\app -> app </> "profiles" </> name <.> "profile")


-- | All destination files paths
filepaths :: DB -> [FilePath]
filepaths = M.keys <=< M.elems <=< M.elems . view db

-- | All sources paths
sources :: DB -> [FilePath]
sources = map location . M.keys <=< M.elems . view db


#if defined(__GLASGOW_HASKELL__) && __GLASGOW_HASKELL__ < 706
-- | Convert strict bytestring into lazy one
fromStrict :: B.ByteString -> BL.ByteString
fromStrict = BL.fromChunks . return
#endif


-- | Extract terms data from script
construct :: Free (Term Annotate Sources) a -> DB
construct z = execState (f z) mempty
 where
  f :: Free (Term Annotate Sources) a -> State DB ()
  f (Free (TS (AS { asProfile = p }) (Source t u d _) i x)) = do
    let s = Record { recordtype = t, base = u, location = d }
    db . at p . non mempty <>= M.singleton s mempty
    g p s i
    f x
  f (Free (TM _ x)) = f x
  f (Pure _) = return ()

  g :: String -> Record -> Free (Term Annotate Actions) a -> State DB ()
  g p s (Free (TA _ a x)) = do
    db . at p . traverse . at s . traverse <>= h a
    g p s x
   where
    h (Link src dst)       = M.singleton dst Record { recordtype = "link",     base = src, location = dst }
    h (Copy src dst)       = M.singleton dst Record { recordtype = "copy",     base = src, location = dst }
    h (Template src dst _) = M.singleton dst Record { recordtype = "template", base = src, location = dst }
    h (Command {})         = mempty
  g p s (Free (TM _ x)) = g p s x
  g _ _ (Pure _) = return ()
