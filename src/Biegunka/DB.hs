{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell #-}
module Biegunka.DB
  ( Biegunka(..), R(..)
  , load, loadProfile, save, construct
  , filepaths, sources
  ) where

import Control.Applicative
import Control.Monad ((<=<), mplus)
import Data.Maybe (catMaybes, mapMaybe)
import Data.Monoid (Monoid(..))
import System.IO.Error (catchIOError)

import           Control.Lens hiding ((.=), (<.>))
import           Control.Monad.State (State, execState)
import           Data.Aeson
import           Data.Aeson.Encode
import           Data.Aeson.Types
import qualified Data.ByteString as B
import qualified Data.ByteString.Lazy as BL
import           Data.Default
import           Data.Map (Map)
import qualified Data.Map as M
import qualified Data.Text.Lazy.Builder as T
import qualified Data.Text.Lazy.Encoding as T
import           System.Directory (createDirectoryIfMissing, removeDirectory, removeFile)
import           System.FilePath.Lens

import Biegunka.Control (Controls, appData)
import Biegunka.Language (IL(..), A(..))


newtype Biegunka = Biegunka
  { unBiegunka :: Map String (Map R (Map FilePath R))
  } deriving (Show, Read, Eq, Ord, Monoid)


data R = R
  { recordtype :: String
  , base :: FilePath
  , location :: FilePath
  } deriving (Show, Read, Eq, Ord)

instance FromJSON R where
  parseJSON (Object o) = liftA3 R (o .: "recordtype") (o .: "base") (o .: "location")
  parseJSON _          = empty

instance ToJSON R where
  toJSON R { recordtype = ft, base = bs, location = lc } = object [ "recordtype" .= ft, "base" .= bs, "location" .= lc ]


data Construct = Construct
  { _source :: R
  , _biegunka :: Map String (Map R (Map FilePath R))
  } deriving (Show, Read, Eq, Ord)

instance Default Construct where
  def = Construct (R "" "" "") mempty

makeLenses ''Construct


load :: Controls -> [IL] -> IO Biegunka
load c = fmap (Biegunka . M.fromList . catMaybes) . mapM (loadProfile c) . mapMaybe profiles
 where
  profiles (IS _ _ _ n _) = Just n
  profiles _              = Nothing


loadProfile :: Controls -> String -> IO (Maybe (String, Map R (Map FilePath R)))
loadProfile c n = do
  let (z, _) = c & appData <</>~ n
  flip catchIOError (\_ -> return Nothing) $
    (parseMaybe parser <=< decode . fromStrict) <$> B.readFile z
 where
  parser (Object o) = (,) n .  M.fromList <$> (mapM repo =<< o .: "sources")
   where
    repo z = do
      t <- z .: "info"
      fs <- z .: "files" >>= mapM parseJSON
      return (t, M.fromList fs)
  parser _ = empty


-- | Save profile information to files.
--
-- Each profile is mapped to a separate file in 'appData' directory.
-- Mapping rules are simple: profile name is a relative path in 'appData'.
--
-- For example, profile @dotfiles@ is located in @~/.biegunka/dotfiles@ by default
-- and profile @my/dotfiles@ is located in @~/.biegunka.my/dotfiles@ by default
save :: Controls -> Biegunka -> IO ()
save c (Biegunka b) = do
  createDirectoryIfMissing False (view appData c)
  ifor_ b $ \profile sourceData -> do
    let (name, _) = c & appData <</>~ profile -- | Map profile to file name
        dir = view directory name
        dirs = takeWhile (/= view appData c) $ iterate (view directory) dir
    if M.null sourceData then do
      removeFile name            -- | Since profile is empty no need having crap in the filesystem
      mapM_ removeDirectory dirs -- | Also remove empty directories if possible
     `mplus`
      return ()                  -- | Ignore failures, they are not critical in any way here
    else do
      createDirectoryIfMissing True dir      -- | Create missing directories for nested profile files
      BL.writeFile name $ encode' sourceData -- | Finally encode profile as JSON
 where
  encode' = T.encodeUtf8 . T.toLazyText . fromValue . unparser
  unparser t  = object [             "sources" .= map repo   (M.toList t)]
  repo (k, v) = object ["info" .= k, "files"   .= map toJSON (M.toList v)]


filepaths :: Biegunka -> [FilePath]
filepaths = M.keys <=< M.elems <=< M.elems . unBiegunka


sources :: Biegunka -> [FilePath]
sources = map location . M.keys <=< M.elems . unBiegunka


fromStrict :: B.ByteString -> BL.ByteString
fromStrict = BL.fromChunks . return


construct :: [IL] -> Biegunka
construct = Biegunka . _biegunka . (`execState` def) . mapM_ g
 where
  g :: IL -> State Construct ()
  g (IS dst t _ pn sn) = do
    let s = R { recordtype = t, base = sn, location = dst }
    assign source s
    biegunka . at pn . non mempty <>= M.singleton s mempty
  g (IA a _ _ pn _) = do
    s <- use source
    biegunka . at pn . traverse . at s . traverse <>= h a
   where
    h (Link src dst)       = M.singleton dst R { recordtype = "link",       base = src, location = dst }
    h (Copy src dst)       = M.singleton dst R { recordtype = "copy",       base = src, location = dst }
    h (Template src dst _) = M.singleton dst R { recordtype = "template",   base = src, location = dst }
    h (Shell {})           = mempty
  g (IW _) = return ()
  g (IT _) = error "Internal language invariant broken"
