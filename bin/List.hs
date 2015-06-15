{-# LANGUAGE CPP #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ViewPatterns #-}
module List
  ( list
  ) where

import           Control.Applicative (liftA3)
import           Control.Lens hiding ((<.>))
import           Control.Monad.Trans.Writer (execWriter, tell)
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Encode as Aeson
import           Data.Char (toUpper)
import           Data.Foldable (for_)
import qualified Data.Map as Map
import           Data.Maybe (fromMaybe)
import qualified Data.Set as Set
import           Data.String (fromString)
import           Data.Text.Lazy (Text)
import           Data.Text.Lazy.Builder (Builder)
import qualified Data.Text.Lazy.Builder as Builder
import qualified Data.Text.Lazy.IO as Text
import           System.IO (hFlush, hPutStrLn, stderr, stdout)

import           Control.Biegunka.Biegunka (expandHome)
import           Control.Biegunka.Namespace
  (Db, Namespaces(..), NamespaceRecord(..), SourceRecord(..), FileRecord(..), namespaces, namespacing, withDb)
import           Control.Biegunka.Settings (defaultSettings, biegunkaRoot)

import           Options


data Formatted a = Formatted
  { nsFormat     :: String       -> a
  , sourceFormat :: SourceRecord -> a
  , fileFormat   :: FileRecord   -> a
  }

instance Functor Formatted where
  fmap g (Formatted p s f) = Formatted (g . p) (g . s) (g . f)


list :: FilePath -> Format -> IO ()
list brpat format = do
  br <- expandHome brpat

  let settings = set biegunkaRoot br defaultSettings

  case format of
    Format pattern -> case formattingText pattern of
      Left errorMessage ->
        badformat errorMessage pattern
      Right formatted -> do
        withDb settings $
          Text.putStr . execWriter . info formatted . view (namespaces.namespacing)
        hFlush stdout
    JSON -> do
      withDb settings $
        Text.putStrLn . Builder.toLazyText . toJson
      hFlush stdout
 where
  info formatted db =
    ifor_ db $ \nsName (NR nsData) -> do
      tell $ nsFormat formatted nsName
      ifor_ nsData $ \sourceRecord fileRecords -> do
        tell $ sourceFormat formatted sourceRecord
        for_ fileRecords $ \fileRecord ->
          tell $ fileFormat formatted fileRecord

  badformat message pattern = hPutStrLn stderr $
    "Bad format pattern: \"" ++ pattern ++ "\" - " ++ message

toJson :: Db -> Builder
toJson (view namespaces -> Namespaces { _unNamespaces }) =
  Aeson.encodeToTextBuilder
    (Aeson.object
      [ "namespaces" Aeson..= ns (Map.toList _unNamespaces)
      ])
 where
  ns xs = Aeson.object (map (\(k, v) -> fromString k Aeson..= nr v) xs)
  nr (NR t) = Aeson.object ["sources" Aeson..= map repo (Map.toList t)]
   where
    repo (k, v) =
      Aeson.object [ "info"  Aeson..= sr k
                   , "files" Aeson..= map fr (Set.toList v)]
  sr SR { sourceType, fromLocation, sourcePath, sourceOwner } = Aeson.object
    [ "type" Aeson..= sourceType
    , "from" Aeson..= fromLocation
    , "path" Aeson..= sourcePath
    , "user" Aeson..= who sourceOwner
    ]
  fr FR { fileType, fromSource, filePath, fileOwner } = Aeson.object
    [ "type" Aeson..= fileType
    , "from" Aeson..= fromSource
    , "path" Aeson..= filePath
    , "user" Aeson..= who fileOwner
    ]

formattingText :: String -> Either String (Formatted Text)
formattingText = (fmap . fmap) fromString . formatting

formatting :: String -> Either String (Formatted String)
formatting xs = do
  (x, ys) <- breaking xs
  (y, z)  <- breaking ys
  liftA3 Formatted (formatNamespace x) (formatSource y) (formatFile z)
 where
  formatNamespace = format $ \case
    'p' -> Right id
    c   -> Left ("%" ++ [c] ++ " is not a namespace info placeholder")

  formatSource = format $ \case
    't' -> Right sourceType
    'l' -> Right fromLocation
    'p' -> Right sourcePath
    'u' -> Right (who . sourceOwner)
    c   -> Left ("%" ++ [c] ++ " is not a source info placeholder")

  formatFile = format $ \case
    't' -> Right fileType
    'T' -> Right (capitalize . fileType)
    'l' -> Right fromSource
    'p' -> Right filePath
    'u' -> Right (who . fileOwner)
    c   -> Left ("%" ++ [c] ++ " is not a file info placeholder")

  format :: (Char -> Either String (a -> String)) -> String -> Either String (a -> String)
  format rules = \case
    '%':'%':vs -> fmap (\g r -> '%' : g r) (format rules vs)
    '%':'n':vs -> fmap (\g r -> '\n' : g r) (format rules vs)
    '%':vs -> case vs of
      c:cs -> do
        s <- rules c
        t <- format rules cs
        return (\a -> s a ++ t a)
      _ -> Left "incomplete %-placeholder at the end"
    v:vs -> fmap (\g r -> v : g r) (format rules vs)
    []   -> Right (const "")

-- | Break string on "%;"
--
-- >>> breaking "hello%;world"
-- Right ("hello","world")
--
-- >>> breaking "hello%;"
-- Right ("hello","")
--
-- >>> breaking "%;world"
-- Right ("","world")
--
-- >>> breaking "%;"
-- Right ("","")
--
-- >>> breaking "he%nllo%;wo%mrld"
-- Right ("he%nllo","wo%mrld")
--
-- >>> breaking "%"
-- Left "Formatting section is missing"
--
-- >>> breaking "123hello"
-- Left "Formatting section is missing"
breaking :: String -> Either String (String, String)
breaking xs = case break (== '%') xs of
  (ys, _:';':zs) -> Right (ys, zs)
  (ys, _:c:zs)   -> fmap (\(a, b) -> (ys ++ ['%',c] ++ a, b)) (breaking zs)
  (_, _)         -> Left "Formatting section is missing"

-- | Make word's first letter uppercase
--
-- >>> capitalize "hello"
-- "Hello"
--
-- >>> capitalize "Hello"
-- "Hello"
--
-- >>> capitalize "123hello"
-- "123hello"
capitalize :: String -> String
capitalize (c:cs) = toUpper c : cs
capitalize ""     = ""

who :: Maybe (Either String Int) -> String
who = either id show . fromMaybe (Left "(unknown)")
