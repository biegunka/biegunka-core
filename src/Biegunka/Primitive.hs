{-# LANGUAGE DataKinds #-}
{-# LANGUAGE ViewPatterns #-}
-- | Language primitives
module Biegunka.Primitive
  ( -- * Profile layer primitives
    profile
    -- * Actions layer primitives
  , registerAt, link, copy, substitute, shell
    -- * Wrappers
  , sudo, reacting, chain, (~>>)
  ) where

import Data.Monoid (mempty)

import Control.Monad.State
import Text.StringTemplate (newSTMP, render, setAttribute)

import Biegunka.Language

infixr 7 `chain`, ~>>


-- | Configuration profile
--
-- Provides convenient sources grouping
--
-- > profile "mine" $ do
-- >   git ...
-- >   git ...
-- > profile "friend's" $ do
-- >   svn ...
profile :: String -> Script Sources () -> Script Profiles ()
profile n i = do
  (ast, s) <- state $ \s -> let (ast, (succ -> s')) = annotate i s in ((ast, s'), s')
  liftS $ EP s (Profile n) ast ()
{-# INLINE profile #-}

-- | Links source to specified filepath
--
-- > git "https://example.com/repo.git" "git/repo" $
-- >   registerAt "we/need/you/here"
--
-- Links the whole ${HOME}\/git\/repo to ${HOME}\/we\/need\/you\/here
registerAt :: FilePath -> Script Actions ()
registerAt dst = liftS $ EA () (Link mempty dst) ()
{-# INLINE registerAt #-}

-- | Links given file to specified filepath
--
-- > git "https://example.com/repo.git" "git/repo" $
-- >   link "you" "we/need/you/here"
--
-- Links ${HOME}\/git\/repo\/you to ${HOME}\/we\/need\/you\/here
link :: FilePath -> FilePath -> Script Actions ()
link src dst = liftS $ EA () (Link src dst) ()
{-# INLINE link #-}

-- | Copies given file to specified filepath
--
-- > git "https://example.com/repo.git" "git/repo" $
-- >   copy "you" "we/need/you/here"
--
-- Copies ${HOME}\/git\/repo\/you to ${HOME}\/we\/need\/you\/here
copy :: FilePath -> FilePath -> Script Actions ()
copy src dst = liftS $ EA () (Copy src dst) ()
{-# INLINE copy #-}

-- | Substitutes $template.X$ templates in given file and writes result to specified filepath
--
-- > git "https://example.com/repo.git" "git/repo" $
-- >   substitute "you.hs" "we/need/you/here"
--
-- Substitutes templates in ${HOME}\/git\/repo\/you.hs with values from
-- Settings.template and writes result to ${HOME}\/we\/need\/you\/here
substitute :: FilePath -> FilePath -> Script Actions ()
substitute src dst = liftS $
  EA () (Template src dst (\b -> render . setAttribute "template" b . newSTMP)) ()
{-# INLINE substitute #-}


-- | Executes shell command with default shell
--
-- > git "https://example.com/repo.git" "git/repo" $
-- >   shell "echo -n hello"
--
-- Prints "hello" (without a newline)
shell :: String -> Script Actions ()
shell c = liftS $ EA () (Shell mempty c) ()
{-# INLINE shell #-}

-- | Change effective user id for wrapped commands
sudo :: String -> Script sc () -> Script sc ()
sudo n s = liftS (EW (User (Just n)) ()) >> s >> liftS (EW (User Nothing) ())
{-# INLINE sudo #-}

-- | Change reaction pattern for wrapped commands
reacting :: React -> Script sc () -> Script sc ()
reacting r s = liftS (EW (Reacting (Just r)) ()) >> s >> liftS (EW (Reacting Nothing) ())
{-# INLINE reacting #-}

-- | Chain tasks sequentially
-- Connects two tasks which forces them to run sequentially one after another.
--
-- Note: redundant if 'Order' is 'Sequential'
chain :: Script sc () -> Script sc () -> Script sc ()
chain a b = do
  (ast, ast') <- state $ \s ->
    let (ast,  s')  = annotate a s
        (ast', s'') = annotate b s
    in ((ast, ast'), max s' s'')
  Script (lift ast)
  Script (lift ast')

-- | Alias for 'chain'
(~>>) :: Script sc () -> Script sc () -> Script sc ()
(~>>) = chain
{-# INLINE (~>>) #-}
