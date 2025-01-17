-- Copyright 2019 Google LLC
--
-- Use of this source code is governed by a BSD-style
-- license that can be found in the LICENSE file or at
-- https://developers.google.com/open-source/licenses/bsd

{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE GADTs #-}

module Pass (TopPassM, assertEq, ignoreExcept, liftExceptTop, runFullPass,
             throwTopErr, emitOutput, (>+>), throwIf, TopPass (..), FullPass) where

import Control.Monad.State.Strict
import Control.Monad.Except hiding (Except)
import Data.Text.Prettyprint.Doc
import Data.Void

import Syntax
import PPrint
import Cat

-- === top-level pass ===

type TopPassM env a = ExceptT Result' (CatT env IO) a
type FullPass env = SourceBlock -> TopPassM env Void

data TopPass a b where
  TopPass :: Monoid env => (a -> TopPassM env b) -> TopPass a b

runFullPass :: Monoid env => env -> FullPass env -> SourceBlock -> IO (Result, env)
runFullPass env pass source = do
  ~(Left result, env') <- runTopPassM env (pass source)
  return (addErrSrc source (Result result), env')

runTopPassM :: Monoid env => env -> TopPassM env a -> IO (Either Result' a, env)
runTopPassM env m = runCatT (runExceptT m) env

infixl 1 >+>

(>+>) :: TopPass a b -> TopPass b c -> TopPass a c
(>+>) (TopPass f1) (TopPass f2) = TopPass $ \x -> do
  (env1, env2) <- look
  (y, env1') <- liftIO $ runTopPassM env1 (f1 x)
  extend (env1', mempty)
  y' <- liftEither y
  (z, env2') <- liftIO $ runTopPassM env2 (f2 y')
  extend (mempty, env2')
  z' <- liftEither z
  return z'

throwTopErr :: Err -> TopPassM env a
throwTopErr e = throwError (Left e)

emitOutput :: Output -> TopPassM env a
emitOutput out = throwError (Right out)

liftExceptTop :: Either Err a -> TopPassM env a
liftExceptTop (Left e) = throwError (Left e)
liftExceptTop (Right x) = return x

-- === common monad structure for pure passes ===

assertEq :: (MonadError Err m, Pretty a, Eq a) => a -> a -> String -> m ()
assertEq x y s = if x == y then return ()
                           else throw CompilerErr msg
  where msg = s ++ ": " ++ pprint x ++ " != " ++ pprint y

throwIf :: MonadError Err m => Bool -> String -> m ()
throwIf True  s = throw CompilerErr s
throwIf False _ = return ()

ignoreExcept :: Except a -> a
ignoreExcept (Left e) = error $ pprint e
ignoreExcept (Right x) = x
