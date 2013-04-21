{-# LANGUAGE ExistentialQuantification #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE TemplateHaskell #-}
module Biegunka.Execute.Control
  ( -- * Execution facade type
    Execution
    -- * Execution thread state
  , ES(..), reactStack, usersStack, retryCount
    -- * Execution environment
  , EE(..)
  , priviledges, react, templates
  , work, retries, running, sudoing, controls
    -- * Misc
  , Statement(..), Templates(..), Priviledges(..), Work(..)
  ) where

import Control.Concurrent.STM.TQueue (TQueue)
import System.IO.Unsafe (unsafePerformIO)

import Control.Concurrent.STM.TVar
import Control.Lens
import Control.Monad.State (StateT)
import Data.Default
import Data.Tag
import Text.StringTemplate (ToSElem(..))

import Biegunka.Language (React(..))
import Biegunka.Control (Controls)


type Execution s a = Tag s (StateT ES IO) a


-- | 'Execution' thread state.
-- Denotes current failure reaction, effective user id and more
data ES = ES
  { _reactStack  :: [React]
  , _usersStack  :: [String]
  , _retryCount  :: Int
  } deriving (Show, Read, Eq, Ord)

instance Default ES where
  def = ES
    { _reactStack = []
    , _usersStack = []
    , _retryCount = 0
    }

makeLenses ''ES


-- | 'Execution' environment.
-- Denotes default failure reaction, templates used and more
data EE = EE
  { _priviledges :: Priviledges
  , _react       :: React
  , _templates   :: Templates
  , _work        :: TQueue Work
  , _retries     :: Int
  , _running     :: TVar Bool
  , _sudoing     :: TVar Bool
  , _controls    :: Controls
  }

-- | Priviledges control.
-- Controls how to behave if started with sudo
data Priviledges =
    Drop     -- ^ Drop priviledges
  | Preserve -- ^ Preserve priviledges
    deriving (Show, Read, Eq, Ord)

-- | Statement thoroughness
data Statement =
    Thorough { text :: String } -- ^ Highly verbose statement with lots of details
  | Typical  { text :: String } -- ^ Typical report with minimum information
    deriving (Show, Read, Eq, Ord)

-- | Wrapper for templates to not have to specify `t' type on 'ExecutionState'
-- Existence of that wrapper is what made 'Default' instance possible
data Templates = forall t. ToSElem t => Templates t

-- | Workload
data Work =
    Do (IO ()) -- ^ Task to come
  | Stop       -- ^ Task is done

-- | Execution context TVar. True if sudoed operation is in progress.
sudo :: TVar Bool
sudo = unsafePerformIO $ newTVarIO False
{-# NOINLINE sudo #-}

-- | Execution context TVar. True if simple operation is in progress.
run :: TVar Bool
run = unsafePerformIO $ newTVarIO False
{-# NOINLINE run #-}


instance Default EE where
  def = EE
    { _priviledges = Preserve
    , _react       = Ignorant
    , _templates   = Templates ()
    , _work        = undefined    -- User doesn't have a chance to get there
    , _retries     = 1
    , _running     = run
    , _sudoing     = sudo
    , _controls    = def
    }

makeLenses ''EE
