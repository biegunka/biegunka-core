{-# LANGUAGE GADTs #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE NamedFieldPuns #-}
-- | Describe execution I/O actions
module Control.Biegunka.Execute.Describe
  ( describeTerm, removal
  , sourceIdentifier
  , prettyDiff
  ) where

import           Control.Exception (SomeException)
import           Data.Bool (bool)
import qualified Data.List as List
import           Data.List.NonEmpty (NonEmpty((:|)))
import           Data.Text.Lazy (Text)
import qualified Data.Text.Lazy as Text
import           Data.Text.Lazy.Builder (Builder)
import qualified Data.Text.Lazy.Builder as Builder
import           System.Process (CmdSpec(..))
import           Text.Printf (printf)

import           Control.Biegunka.Language
import           Control.Biegunka.Script
import           Control.Biegunka.Patience (Hunk(..), Judgement(..), judgement)

-- | Describe an action and its outcome.
describeTerm
  :: Retries
  -> Either SomeException (Maybe String)
  -> Bool
  -> TermF Annotate s a
  -> String
describeTerm (Retries n) mout withSource ta =
  case mout of
    Left e -> unlines .
      (if withSource then (prefixf ta :) else id) $
        ("  * " ++ doc
                ++ bool "" (printf " [%sretry %d%s]" yellow n reset) (n > 0)
                ++ printf " [%sexception%s]" red reset)
        : map (\l -> printf "    %s%s%s" red l reset) (lines (show e))
    Right Nothing -> unlines $
      (if withSource then (prefixf ta :) else id)
        [ "  * " ++ doc
                 ++ " (up-to-date)"
                 ++ bool "" (printf " [%sretry %d%s]" yellow n reset) (n > 0)
        ]
    Right (Just out) -> unlines $
      (if withSource then (prefixf ta :) else id)
        [ "  * " ++ doc
                 ++ bool "" (printf " [%sretry %d%s]" yellow n reset) (n > 0)
                 ++ printf "\n    %s- %s%s" green out reset
        ]
 where
  prefixf :: TermF Annotate s a -> String
  prefixf t = case sourceIdentifier t of
    Nothing -> ""
    Just (url :| ns) ->
      List.intercalate "::" (reverse (printf "[%s]" url : ns))

  doc = case ta of
    TS _ (Source t _ d _) _ _  ->
      printf "%s source[%s] update" t d
    TA _ a _ ->
      case a of
        Link s d ->
          printf "symlink[%s] update (point to [%s])" d s
        Copy s d ->
          printf "file[%s] update (copy [%s])" d s
        Template s d ->
          printf "file[%s] update (from template [%s])" d s
        Command p (ShellCommand c) ->
          printf "execute[%s] (from [%s])" c p
        Command p (RawCommand c as) ->
          printf "execute[%s] (from [%s])" (unwords (c : as)) p
    _ -> ""

-- | Note that the components are in the reverse order.
sourceIdentifier :: TermF Annotate s a -> Maybe (NonEmpty String)
sourceIdentifier = \case
  TS (AS { asSegments }) (Source _ url _ _) _ _ -> Just (url :| asSegments)
  TA (AA { aaSegments, aaUrl }) _ _ -> Just (aaUrl :| aaSegments)
  TWait _ _ -> Nothing

prettyDiff :: [Hunk Text] -> String
prettyDiff =
  nonempty " (no diff)" (toString . unline . (mempty :) . map (prettyHunk . fmap Builder.fromLazyText))

nonempty :: b -> ([a] -> b) -> [a] -> b
nonempty z _ [] = z
nonempty _ f xs = f xs

prettyHunk :: Hunk Builder -> Builder
prettyHunk (Hunk n i m j ls) = unline (prettyHeader : map prettyLine ls)
 where
  prettyHeader = Builder.fromString (printf "      %s@@ -%d,%d +%d,%d @@" reset n i m j)

prettyLine :: Judgement Builder -> Builder
prettyLine j = mconcat
  [ Builder.fromString "      "
  , judgement (decorate red '-') (decorate green '+') (decorate reset ' ') j
  ]
 where
  decorate col ch x = mconcat [Builder.fromString col, Builder.singleton ch, x]

toString :: Builder -> String
toString = Text.unpack . Builder.toLazyText

unline :: [Builder] -> Builder
unline = mconcat . List.intersperse (Builder.singleton '\n')

-- | Describe file or directory removal
removal :: FilePath -> String
removal = printf "Removing: %s\n"

red :: String
red = "\ESC[31;2m"

yellow :: String
yellow = "\ESC[33;2m"

green :: String
green = "\ESC[32;2m"

reset :: String
reset = "\ESC[0m"
