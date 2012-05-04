#!/usr/bin/env runhaskell
{-# LANGUAGE UnicodeSyntax #-}

import Biegunka
import Control.Arrow (first)
import Control.Monad (forM_)
import Data.Monoid ((<>))
import System.FilePath ((</>))

main = do
  α ← bzdury
    [ git "https://github.com/ujihisa/neco-ghc" "/home/maksenov/git/neco-ghc" --> neco_ghc
    , git "https://github.com/Shougo/neocomplcache" "/home/maksenov/git/neocomplcache" --> neocomplicache
    , git "https://github.com/supki/.dotfiles" "/home/maksenov/git/.dotfiles" --> utils [Core, Extended, Laptop]
    ]
  β ← load
  let γ = merge α β
  save γ
  where neco_ghc = link_repo_itself ".vim/bundle/neco-ghc"
        neocomplicache = link_repo_itself ".vim/bundle/neocomplcache"

data Set = Core
         | Extended
         | Laptop
         | Work
           deriving Show

dir Core = "core"
dir Extended = "extended"
dir Laptop = "laptop"
dir Work = "work"

utils ∷ [Set] → Script ()
utils = mapM_ installSet

installSet ∷ Set → Script ()
installSet s = do message $ "Installing " <> show s <> " configs..."
                  forM_ (pairs s) $ uncurry link_repo_file . first (dir s </>)

pairs ∷ Set → [(FilePath, FilePath)]
pairs Core =
  [ ("xsession", ".xsession")
  , ("mpdconf", ".mpdconf")
  , ("bashrc", ".bashrc")
  , ("zshrc", ".zshrc")
  , ("inputrc", ".inputrc")
  , ("profile", ".profile")
  , ("vimrc", ".vimrc")
  , ("ghci", ".ghci")
  , ("haskeline", ".haskeline")
  , ("racketrc", ".racketrc")
  , ("gitconfig", ".gitconfig")
  , ("gitignore", ".gitignore")
  , ("ackrc", ".ackrc")
  , ("vim/pathogen.vim", ".vim/autoload/pathogen.vim")
  , ("vim/haskellmode.vim", ".vim/autoload/haskellmode.vim")
  , ("vim/cscope_maps.vim", ".vim/bundle/cscope_maps.vim")
  , ("vim/scratch", ".vim/bundle/scratch")
  , ("conceal/haskell.vim", ".vim/after/syntax/haskell.vim")
  , ("XCompose", ".XCompose")
  ]
pairs Extended =
  [ ("xmonad.hs", ".xmonad/xmonad.hs")
  , ("xmonad/Controls.hs", ".xmonad/lib/Controls.hs")
  , ("xmonad/Layouts.hs", ".xmonad/lib/Layouts.hs")
  , ("xmonad/Misc.hs", ".xmonad/lib/Misc.hs")
  , ("xmonad/Startup.hs", ".xmonad/lib/Startup.hs")
  , ("xmonad/Themes.hs", ".xmonad/lib/Themes.hs")
  , ("xmonad/Workspaces.hs", ".xmonad/lib/Workspaces.hs")
  , ("gvimrc", ".gvimrc")
  , ("vimcolors", ".vim/colors")
  , ("pentadactylrc", ".pentadactylrc")
  , ("gtkrc.mine", ".gtkrc.mine")
  ]
pairs _ =
  [ ("xmonad/Profile.hs", ".xmonad/lib/Profile.hs")
  , ("mcabberrc", ".mcabberrc")
  , ("ncmpcpp", ".ncmpcpp/config")
  , ("xmobarrc", ".xmobarrc")
  , ("Xdefaults", ".Xdefaults")
  , ("xmodmap", ".xmodmap")
  ]
