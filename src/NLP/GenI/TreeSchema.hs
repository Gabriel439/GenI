-- GenI surface realiser
-- Copyright (C) 2005-2009 Carlos Areces and Eric Kow
--
-- This program is free software; you can redistribute it and/or
-- modify it under the terms of the GNU General Public License
-- as published by the Free Software Foundation; either version 2
-- of the License, or (at your option) any later version.
--
-- This program is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
-- GNU General Public License for more details.
--
-- You should have received a copy of the GNU General Public License
-- along with this program; if not, write to the Free Software
-- Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA  02111-1307, USA.

{-# OPTIONS_GHC -fno-warn-orphans #-}
{-# LANGUAGE OverlappingInstances, FlexibleInstances #-}
{-# LANGUAGE DeriveDataTypeable #-}
{-# LANGUAGE OverloadedStrings  #-}

-- | This module provides basic datatypes specific to Tree Adjoining Grammar
--   tree schemata.
module NLP.GenI.TreeSchema (
   Macros,
   SchemaTree, SchemaNode, Ttree(..), Ptype(..),

   -- Functions from Tree GNode
   root, rootUpd, foot, setLexeme, setAnchor, lexemeAttributes,
   crushTreeGNode,

   -- GNode
   GNode(..), gnnameIs, NodeName,
   GType(..), gCategory, showLexeme,
   crushGNode,
 ) where

import qualified Data.Map as Map
import Data.Binary
import Data.Tree
import Data.Text ( Text )
import qualified Data.Text as T

import Control.DeepSeq
import Data.FullList hiding (head, tail, (++))
import Data.Generics (Data)
import Data.Typeable (Typeable)

import NLP.GenI.General (filterTree, listRepNode, geniBug, quoteText)
import NLP.GenI.GeniShow
import NLP.GenI.GeniVal ( GeniVal(..), DescendGeniVal(..), Collectable(..),
                        )
import NLP.GenI.FeatureStructure ( AvPair(..), Flist, crushFlist )
import NLP.GenI.Pretty
import NLP.GenI.Semantics ( Sem )

-- ----------------------------------------------------------------------
-- Tree schemata

-- In GenI, the tree schemata are called `macros' for historical reasons.
-- We are working to phase out this name in favour of the more standard
-- `tree schema(ta)'.
-- ----------------------------------------------------------------------

type SchemaTree = Ttree SchemaNode
type SchemaNode = GNode [GeniVal]
type Macros = [SchemaTree]

data Ttree a = TT
    { params  :: [GeniVal]
    , pfamily :: Text
    , pidname :: Text
    , pinterface :: Flist GeniVal
    , ptype :: Ptype
    , psemantics :: Maybe Sem
    , ptrace :: [Text]
    , tree :: Tree a
    }
  deriving (Data, Typeable, Eq)

data Ptype = Initial | Auxiliar
  deriving (Show, Eq, Data, Typeable)

instance DescendGeniVal v => DescendGeniVal (Ttree v) where
  descendGeniVal s mt =
    mt { params = descendGeniVal s (params mt)
       , tree   = descendGeniVal s (tree mt)
       , pinterface  = descendGeniVal s (pinterface mt)
       , psemantics = descendGeniVal s (psemantics mt) }

instance (Collectable a) => Collectable (Ttree a) where
  collect mt = (collect $ params mt) . (collect $ tree mt) .
               (collect $ psemantics mt) . (collect $ pinterface mt)

-- ----------------------------------------------------------------------
-- Tree manipulation
-- ----------------------------------------------------------------------

-- Traversal

instance DescendGeniVal a => DescendGeniVal (Map.Map k a) where
  descendGeniVal s = {-# SCC "descendGeniVal" #-} Map.map (descendGeniVal s)

instance (Collectable a => Collectable (Tree a)) where
  collect = collect.flatten

-- Utility functions

root :: Tree a -> a
root (Node a _) = a

rootUpd :: Tree a -> a -> Tree a
rootUpd (Node _ l) b = (Node b l)

foot :: Tree (GNode a) -> GNode a
foot t = case filterTree (\n -> gtype n == Foot) t of
         [x] -> x
         _   -> geniBug $ "foot returned weird result"

-- | Given a lexical item @s@ and a Tree GNode t, returns the tree t'
--   where l has been assigned to the anchor node in t'
setAnchor :: FullList Text -> Tree (GNode a) -> Tree (GNode a)
setAnchor s t =
  let filt (Node a []) = (gtype a == Lex && ganchor a)
      filt _ = False
  in case listRepNode (setLexeme (fromFL s)) filt [t] of
     ([r],True) -> r
     _ -> geniBug $ "setLexeme " ++ show s ++ " returned weird result"

-- | Given a lexical item @l@ and a tree node @n@ (actually a subtree
--   with no children), return the same node with the lexical item as
--   its unique child.  The idea is that it converts terminal lexeme nodes
--   into preterminal nodes where the actual terminal is the given lexical
--   item
setLexeme :: [Text] -> Tree (GNode a) -> Tree (GNode a)
setLexeme l (Node a []) = Node a [ Node subanc [] ]
  where
    subanc = GN
        { gnname = T.concat $ "_" : gnname a : "." : l
        , gup    = []
        , gdown  = []
        , gaconstr = True
        , ganchor  = False
        , glexeme = l
        , gtype   = Other
        , gorigin = ""
        }
setLexeme _ _ = geniBug "impossible case in setLexeme - subtree with kids"

-- ----------------------------------------------------------------------
-- TAG nodes (GNode)
-- ----------------------------------------------------------------------

-- | A single node of a TAG tree.
data GNode gv = GN
    { gnname :: NodeName
    , gup    :: Flist gv   -- ^ top feature structure
    , gdown  :: Flist gv   -- ^ bottom feature structure
    , ganchor  :: Bool     -- ^ @False@ for na nodes
    , glexeme  :: [Text]   -- ^ @[]@ for na nodes
    , gtype    :: GType
    , gaconstr :: Bool
    , gorigin  :: Text -- ^ for TAG, this would be the elementary tree
                       --   that this node originally came from
    }
  deriving (Eq, Data, Typeable)

-- Node type used during parsing of the grammar
data GType = Subs | Foot | Lex | Other
  deriving (Show, Eq, Data, Typeable)

type NodeName = Text

-- Traversal

instance Collectable gv => Collectable (GNode gv) where
  collect n = (collect $ gdown n) . (collect $ gup n)

instance DescendGeniVal v => DescendGeniVal (GNode v) where
  descendGeniVal s gn =
    gn { gup = descendGeniVal s (gup gn)
       , gdown = descendGeniVal s (gdown gn) }

-- Utilities

gnnameIs :: NodeName -> GNode gv -> Bool
gnnameIs n = (== n) . gnname

-- | Return the value of the "cat" attribute, if available
gCategory :: Flist GeniVal -> Maybe GeniVal
gCategory top =
  case [ v | AvPair "cat" v <- top ] of
  []  -> Nothing
  [c] -> Just c
  _   -> geniBug $ "Impossible case: node with more than one category"

-- | Attributes recognised as lexemes, in order of preference
lexemeAttributes :: [Text]
lexemeAttributes = [ "lex", "phon", "cat" ]

-- ----------------------------------------------------------------------
-- Pretty printing and other text conversions
-- ----------------------------------------------------------------------

instance GeniShow Ptype where
    geniShow Initial  = "initial"
    geniShow Auxiliar = "auxiliary"

instance (GeniShow a) => GeniShow (Ttree a) where
    geniShowText tt = T.intercalate "\n" . filter (not . T.null) $
        [ "% ------------------------- ", pidname tt
        , T.unwords [ pfamily tt <> ":" <> pidname tt
                    , plist
                    , geniShowText (ptype  tt)
                    ]
        , geniShowText (tree   tt)
        , maybe "" showSem (psemantics tt)
        , showTr (ptrace tt)
        ]
      where
        plist = parens . T.unwords . concat $
            [ map geniShowText (params tt)
            , ["!"]
            , map geniShowText (pinterface tt)
            ]
        showSem = geniKeyword "semantics" . geniShowText
        showTr  = geniKeyword "trace" . squares . T.unwords

-- | The default show for GNode tries to be very compact; it only shows the value
--   for cat attribute and any flags which are marked on that node.
--
--   This is one the places where the pretty representation of a GenI object is
--   different from its GenI-format one
instance Pretty (GNode GeniVal) where
    pretty gn =
        stub `T.append` extra
      where
        cat_ = maybe "" pretty . gCategory $ gup gn
        lex_ = showLexeme (glexeme gn)
        --
        stub = T.intercalate ":" $ filter (not . T.null) [ cat_, lex_ ]
        extra = case gtype gn of
                    Subs -> " !"
                    Foot -> " *"
                    _    -> if gaconstr gn then " #"   else ""

instance GeniShow (GNode GeniVal) where
    geniShowText x =
        T.unwords . filter (not . T.null) $
            [ gnname x, gaconstrstr, gtypestr x, glexstr x, tbFeats x ]
      where
        gaconstrstr = case (gaconstr x, gtype x) of
                          (True, Other) -> "aconstr:noadj"
                          _             ->  ""
        gtypestr n  = case gtype n of
                          Subs -> "type:subst"
                          Foot -> "type:foot"
                          Lex  -> if ganchor n && (null.glexeme) n
                                     then "type:anchor" else "type:lex"
                          _    -> ""
        glexstr n =
            if null ls
               then ""
               else T.intercalate "|" (map quoteText ls)
          where
            ls = glexeme n
        tbFeats n =
            geniShowText (gup n)
            `T.append` "!"
            `T.append` geniShowText (gdown n)


-- FIXME: will have to think of nicer way - one which involves
-- unpacking the trees :-(
showLexeme :: [Text] -> Text
showLexeme []   = ""
showLexeme [l]  = l
showLexeme xs   = T.intercalate "|" xs

-- Fancy disjunction

crushTreeGNode :: Tree (GNode [GeniVal]) -> Maybe (Tree (GNode GeniVal))
crushTreeGNode (Node x xs) =
 do x2  <- crushGNode x
    xs2 <- mapM crushTreeGNode xs
    return $ Node x2 xs2

crushGNode :: GNode [GeniVal] -> Maybe (GNode GeniVal)
crushGNode gn =
  do gup2   <- crushFlist (gup gn)
     gdown2 <- crushFlist (gdown gn)
     return $ GN { gnname = gnname gn
                 , gup = gup2
                 , gdown = gdown2
                 , ganchor = ganchor gn
                 , glexeme = glexeme gn
                 , gtype = gtype gn
                 , gaconstr = gaconstr gn
                 , gorigin = gorigin gn}


instance Binary Ptype where
  put Initial = putWord8 0
  put Auxiliar = putWord8 1
  get = do
    tag_ <- getWord8
    case tag_ of
      0 -> return Initial
      1 -> return Auxiliar
      _ -> fail "no parse"

instance Binary gv => Binary (GNode gv) where
  put (GN a b c d e f g h) = put a >> put b >> put c >> put d >> put e >> put f >> put g >> put h
  get = get >>= \a -> get >>= \b -> get >>= \c -> get >>= \d -> get >>= \e -> get >>= \f -> get >>= \g -> get >>= \h -> return (GN a b c d e f g h)

instance Binary GType where
  put Subs = putWord8 0
  put Foot = putWord8 1
  put Lex = putWord8 2
  put Other = putWord8 3
  get = do
    tag_ <- getWord8
    case tag_ of
      0 -> return Subs
      1 -> return Foot
      2 -> return Lex
      3 -> return Other
      _ -> fail "no parse"

instance (Binary a) => Binary (Ttree a) where
  put (TT a b c d e f g h) = put a >> put b >> put c >> put d >> put e >> put f >> put g >> put h
  get = get >>= \a -> get >>= \b -> get >>= \c -> get >>= \d -> get >>= \e -> get >>= \f -> get >>= \g -> get >>= \h -> return (TT a b c d e f g h)

-- Node type used during parsing of the grammar
instance NFData GType where
  rnf x = x `seq` ()

instance NFData Ptype where
  rnf x = x `seq` ()

-- | A single node of a TAG tree.
instance NFData gv => NFData (GNode gv) where
  rnf (GN x1 x2 x3 x4 x5 x6 x7 x8)
          = rnf x1 `seq`
              rnf x2 `seq`
                rnf x3 `seq`
                  rnf x4 `seq`
                    rnf x5 `seq`
                      rnf x6 `seq`
                        rnf x7 `seq` rnf x8 `seq` ()
