{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QuasiQuotes #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE IncoherentInstances #-}

module Development.Cake3 where

import Control.Applicative
import Control.Monad
import Control.Monad.Trans
import Control.Monad.Writer
import Control.Monad.State
import Control.Monad.Loc
import qualified Data.Text as T
import Data.Text (Text)
import qualified Data.List as L
import Data.List
import qualified Data.Map as M
import Data.Map (Map)
import qualified Data.Set as S
import Data.Set (Set)
import Prelude as P
import System.FilePath
import System.IO
import Text.Printf
import Text.QuasiText
import Text.Printf

import Language.Haskell.TH.Quote
import Language.Haskell.TH
import Language.Haskell.Meta (parseExp)

type Command = String

class ToMake x where
  toMake :: x -> String

data Variable = Variable { vname :: String, vval :: String }
  deriving(Show, Eq, Ord)

instance ToMake Variable where
  toMake (Variable n v) = printf "%s = %s" n v

data Rule = Rule
  { rtgt :: FilePath
  , rsrc :: [FilePath]
  , rcmd :: [Command]
  , rvars :: Map String (Set Variable)
  , rloc :: String
  } deriving(Show, Eq, Ord)

instance ToMake Rule where
  toMake r = unlines (hdr : cmds) where
    hdr = printf "%s : %s # %s" (rtgt r) (L.intercalate " " (rsrc r)) (rloc r)
    cmds = L.map ("\t" ++) (rcmd r)

type Rules = Map FilePath (Set Rule)


collapse' :: (Ord y) => Map String (Set y) -> (Uniq y, [String])
collapse' m = asUniq $ foldr check1 mempty $ M.toList m where
  check1 (k,s) (ss,es) | S.size s == 1 = (s`S.union`ss, es)
                       | otherwise = (ss, (printf "several values for key %s" k):es)
  asUniq (s,e) = (Uniq (S.toList s), e)

newtype Uniq s = Uniq [s] deriving(Show)


collapseRules :: Rules -> (Uniq Rule, [String])
collapseRules rs = collapse' rs

collapseVars :: Uniq Rule -> (Uniq Variable, [String])
collapseVars (Uniq rs) = collapse' $ (M.unionsWith mappend) $ map rvars rs

collapse :: Rules -> (Uniq Variable, Uniq Rule, [String])
collapse tree = (vs, rs, e1++e2) where
  (rs, e1) = collapseRules tree
  (vs, e2) = collapseVars rs

rulesToMake :: Rules -> String
rulesToMake tree = unlines $ (map toMake vs) ++ (map toMake rs) where
  (Uniq vs, Uniq rs, es) = collapse tree

type Location = String

type MakeState = (Rules,Location)

newtype Make a = Make { unMake :: (StateT MakeState IO) a }
  deriving(Monad, Functor, Applicative, MonadState MakeState, MonadIO)

runMake :: Make a -> IO Rules
runMake mk = fst <$> snd <$> runStateT (unMake mk) mempty

addRule r = modifyRules $ M.insertWith mappend (rtgt r) (S.singleton r)

modifyRules f = modify $ \(r,l) -> (f r,l)

modifyLoc f = modify $ \(r,l) -> (r,f l)

getLoc :: Make String
getLoc = snd <$> get

instance MonadLoc Make where
  withLoc l' (Make um) = Make $ do
    modifyLoc (\l -> l') >> um

-- 
-- instance MonadLoc (Make) where
--     withLoc loc (mk) = do
--     EMT $ do
--                      current <- withLoc loc emt
--                      case current of
--                        (Left (tr, a)) -> return (Left (loc:tr, a))
--                        _              -> return current

newtype A a = A { unA :: StateT Rule Make a }
  deriving(Monad, Functor, Applicative, MonadState Rule, MonadIO)

runA :: Rule -> A a -> Make (a,Rule)
runA r a = runStateT (unA a) r

execA r a = snd <$> runA r a

rule :: FilePath -> A () -> Make Rule
rule dst act = do
  loc <- getLoc
  let r = Rule dst [] [] M.empty loc
  r' <- execA r $ act
  addRule r'
  return r'

modifyRule = modify

sys :: Command -> A ()
sys s = modifyRule (\r -> r { rcmd = (s : rcmd r) })

var :: String -> String -> A Variable
var n v = do
  let var = Variable n v
  modifyRule (\r -> r { rvars = M.insertWith mappend n (S.singleton var) (rvars r) })
  return var

newtype SelfRef x = SelfRef x

dst :: A (SelfRef FilePath)
dst = SelfRef <$> rtgt <$> get

class Ref x where
  ref :: x -> A Text

instance Ref (SelfRef FilePath) where
  ref (SelfRef f) = return $ T.pack f

instance Ref Variable where
  ref (Variable n _) = return $ T.pack $ printf "$(%s)" n

instance Ref FilePath where
  ref f = do
    modifyRule $ \r -> r { rsrc = f : (rsrc r)}
    return $ T.pack f

instance Ref Rule where
  ref r = do
    modifyRule $ \r' -> r' { rsrc = (rtgt r) : (rsrc r')}
    return $ T.pack $ rtgt r

instance Ref x => Ref [x] where
  ref l = sequence (L.map ref l) >>= return . T.intercalate " "

instance Ref x => Ref (A x) where
  ref mx = mx >>= ref

instance Ref x => Ref (Make x) where
  ref mx = (A $ lift mx) >>= ref

make :: QuasiQuoter
make = QuasiQuoter
  { quotePat  = undefined
  , quoteType = undefined
  , quoteDec  = undefined
  , quoteExp = \s -> 
      let chunks = flip P.map (getChunks (T.pack s)) $ \c ->
                     case c of
                       T t -> [| return t |]
                       E t -> case parseExp (T.unpack t) of
                                Left  e -> error e
                                Right e -> appE [| ref |] (return e)
                       V t -> appE [| ref |] (global (mkName (T.unpack t)))
      in appE [| (\l -> T.unpack <$> T.concat <$> (sequence l) >>= sys) |] (listE chunks)
  }
