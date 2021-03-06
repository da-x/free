{-# LANGUAGE CPP #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE UndecidableInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
#if __GLASGOW_HASKELL__ >= 707
{-# LANGUAGE DeriveDataTypeable #-}
#endif

-----------------------------------------------------------------------------
-- |
-- Module      :  Control.Comonad.Trans.Coiter
-- Copyright   :  (C) 2008-2013 Edward Kmett
-- License     :  BSD-style (see the file LICENSE)
--
-- Maintainer  :  Edward Kmett <ekmett@gmail.com>
-- Stability   :  provisional
-- Portability :  MPTCs, fundeps
--
-- The coiterative comonad generated by a comonad
----------------------------------------------------------------------------
module Control.Comonad.Trans.Coiter
  (
  -- |
  -- Coiterative comonads represent non-terminating, productive computations.
  --
  -- They are the dual notion of iterative monads. While iterative computations
  -- produce no values or eventually terminate with one, coiterative
  -- computations constantly produce values and they never terminate.
  -- 
  -- It's simpler form, 'Coiter', is an infinite stream of data. 'CoiterT'
  -- extends this so that each step of the computation can be performed in
  -- a comonadic context.

  -- * The coiterative comonad transformer
    CoiterT(..)
  -- * The coiterative comonad
  , Coiter, coiter, runCoiter
  -- * Generating coiterative comonads
  , unfold
  -- * Cofree comonads
  , ComonadCofree(..)
  -- * Examples
  -- $example
  ) where

import Control.Arrow hiding (second)
import Control.Comonad
import Control.Comonad.Cofree.Class
import Control.Comonad.Env.Class
import Control.Comonad.Hoist.Class
import Control.Comonad.Store.Class
import Control.Comonad.Traced.Class
import Control.Comonad.Trans.Class
import Control.Category
import Data.Bifunctor
import Data.Bifoldable
import Data.Bitraversable
import Data.Data
import Data.Foldable
import Data.Function (on)
import Data.Functor.Identity
import Data.Traversable
import Prelude hiding (id,(.))
import Prelude.Extras

-- | This is the coiterative comonad generated by a comonad
newtype CoiterT w a = CoiterT { runCoiterT :: w (a, CoiterT w a) }
#if __GLASGOW_HASKELL__ >= 707
  deriving Typeable
#endif

instance (Functor w, Eq1 w) => Eq1 (CoiterT w) where
  (==#) = on (==#) (fmap (fmap Lift1) . runCoiterT)

instance (Functor w, Ord1 w) => Ord1 (CoiterT w) where
  compare1 = on compare1 (fmap (fmap Lift1) . runCoiterT)

instance (Functor w, Show1 w) => Show1 (CoiterT w) where
  showsPrec1 d (CoiterT as) = showParen (d > 10) $
    showString "CoiterT " . showsPrec1 11 (fmap (fmap Lift1) as)

instance (Functor w, Read1 w) => Read1 (CoiterT w) where
  readsPrec1 d =  readParen (d > 10) $ \r ->
    [ (CoiterT (fmap (fmap lower1) m),t) | ("CoiterT",s) <- lex r, (m,t) <- readsPrec1 11 s]

-- | The coiterative comonad
type Coiter = CoiterT Identity

-- | Prepends a result to a coiterative computation.
--
-- prop> runCoiter . uncurry coiter == id
coiter :: a -> Coiter a -> Coiter a
coiter a as = CoiterT $ Identity (a,as)
{-# INLINE coiter #-}

-- | Extracts the first result from a coiterative computation.
--
-- prop> uncurry coiter . runCoiter == id
runCoiter :: Coiter a -> (a, Coiter a)
runCoiter = runIdentity . runCoiterT
{-# INLINE runCoiter #-}

instance Functor w => Functor (CoiterT w) where
  fmap f = CoiterT . fmap (bimap f (fmap f)) . runCoiterT

instance Comonad w => Comonad (CoiterT w) where
  extract = fst . extract . runCoiterT
  {-# INLINE extract #-}
  extend f = CoiterT . extend (\w -> (f (CoiterT w), extend f $ snd $ extract w)) . runCoiterT

instance Foldable w => Foldable (CoiterT w) where
  foldMap f = foldMap (bifoldMap f (foldMap f)) . runCoiterT

instance Traversable w => Traversable (CoiterT w) where
  traverse f = fmap CoiterT . traverse (bitraverse f (traverse f)) . runCoiterT

instance ComonadTrans CoiterT where
  lower = fmap fst . runCoiterT

instance Comonad w => ComonadCofree Identity (CoiterT w) where
  unwrap = Identity . snd . extract . runCoiterT
  {-# INLINE unwrap #-}
  
instance ComonadEnv e w => ComonadEnv e (CoiterT w) where
  ask = ask . lower
  {-# INLINE ask #-}
  
instance ComonadHoist CoiterT where
  cohoist g = CoiterT . fmap (second (cohoist g)) . g . runCoiterT

instance ComonadTraced m w => ComonadTraced m (CoiterT w) where
  trace m = trace m . lower
  {-# INLINE trace #-}

instance ComonadStore s w => ComonadStore s (CoiterT w) where
  pos = pos . lower
  peek s = peek s . lower
  peeks f = peeks f . lower
  seek = seek
  seeks = seeks
  experiment f = experiment f . lower
  {-# INLINE pos #-}
  {-# INLINE peek #-}
  {-# INLINE peeks #-}
  {-# INLINE seek #-}
  {-# INLINE seeks #-}
  {-# INLINE experiment #-}

instance Show (w (a, CoiterT w a)) => Show (CoiterT w a) where
  showsPrec d w = showParen (d > 10) $
    showString "CoiterT " . showsPrec 11 w

instance Read (w (a, CoiterT w a)) => Read (CoiterT w a) where
  readsPrec d = readParen (d > 10) $ \r ->
     [(CoiterT w, t) | ("CoiterT", s) <- lex r, (w, t) <- readsPrec 11 s]

instance Eq (w (a, CoiterT w a)) => Eq (CoiterT w a) where
  CoiterT a == CoiterT b = a == b
  {-# INLINE (==) #-}

instance Ord (w (a, CoiterT w a)) => Ord (CoiterT w a) where
  compare (CoiterT a) (CoiterT b) = compare a b
  {-# INLINE compare #-}

-- | Unfold a @CoiterT@ comonad transformer from a cokleisli arrow and an initial comonadic seed.
unfold :: Comonad w => (w a -> a) -> w a -> CoiterT w a
unfold psi = CoiterT . extend (extract &&& unfold psi . extend psi)

#if __GLASGOW_HASKELL__ < 707

instance Typeable1 w => Typeable1 (CoiterT w) where
  typeOf1 t = mkTyConApp coiterTTyCon [typeOf1 (w t)] where
    w :: CoiterT w a -> w a
    w = undefined

coiterTTyCon :: TyCon
#if __GLASGOW_HASKELL__ < 704
coiterTTyCon = mkTyCon "Control.Comonad.Trans.Coiter.CoiterT"
#else
coiterTTyCon = mkTyCon3 "free" "Control.Comonad.Trans.Coiter" "CoiterT"
#endif
{-# NOINLINE coiterTTyCon #-}

#else
#define Typeable1 Typeable
#endif

instance
  ( Typeable1 w, Typeable a
  , Data (w (a, CoiterT w a))
  , Data a
  ) => Data (CoiterT w a) where
    gfoldl f z (CoiterT w) = z CoiterT `f` w
    toConstr _ = coiterTConstr
    gunfold k z c = case constrIndex c of
        1 -> k (z CoiterT)
        _ -> error "gunfold"
    dataTypeOf _ = coiterTDataType
    dataCast1 f = gcast1 f

coiterTConstr :: Constr
coiterTConstr = mkConstr coiterTDataType "CoiterT" [] Prefix
{-# NOINLINE coiterTConstr #-}

coiterTDataType :: DataType
coiterTDataType = mkDataType "Control.Comonad.Trans.Coiter.CoiterT" [coiterTConstr]
{-# NOINLINE coiterTDataType #-}

{- $example

<examples/NewtonCoiter.lhs Newton's method>

-}
