module Main where


import Biegunka
import Biegunka.Source.Git


main :: IO ()
main = biegunka id (execute id) $ do
  link ".xmonad/xmonad.hs" ".xmonad/xmonad.hs.bak"