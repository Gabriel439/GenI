-- GenI surface realiser
-- Copyright (C) 2011 SRI
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

{-# LANGUAGE OverloadedStrings  #-}
{-# LANGUAGE StandaloneDeriving #-}
module NLP.GenI.Test.TreeSchema where

import Data.Tree

import Test.HUnit
import Test.QuickCheck hiding (collect, Failure)
import Test.Framework
import Test.Framework.Providers.HUnit
import Test.Framework.Providers.QuickCheck2

import qualified Data.Text  as T
import NLP.GenI.FeatureStructure
import NLP.GenI.GeniVal
import NLP.GenI.TreeSchema

import NLP.GenI.Test.GeniVal hiding ( suite )

suite :: Test.Framework.Test
suite =
 testGroup "NLP.GenI.Tags"
  []

sillyTree :: Tree (GNode GeniVal)
sillyTree =
  Node r [ Node s1 []
         , Node l  []
         , Node s2 []
         ]
 where
   r  = emptyGN
     { gnname = "r"
     , gup    = [ catAv "a", idxAv "rbad" ]
     , gdown  = [ idxAv "r" ]
     }
   s x = emptyGN
     { gnname = x
     , gup    = [ catAv "b", idxAv "s" ]
     , gdown  = [ idxAv "sbad" ]
     , gtype  = Subs
     }
   s1  = s "b1"
   s2  = s "b2"
   l = sillyLexNode

sillyTreeAux :: Tree (GNode GeniVal)
sillyTreeAux =
  Node r [ Node f  []
         , Node l  []
         , Node s  []
         ]
 where
  r  = (emptyNodeCat "a") { gdown = [ idxAv "r" ] }
  f  = emptyGN
     { gnname = "a2"
     , gup    = [catAv "a", idxAv "f"]
     , gtype = Foot
     }
  s  = emptyGN
     { gnname = "b"
     , gup    = [catAv "b", idxAv "s"]
     , gtype  = Subs
     }
  l  = sillyLexNode

emptyNodeCat x = emptyGN
  { gnname = x
  , gup    = [catAv (mkGConstNone x)]
  }

sillyLexNode = emptyGN
     { gnname  = "l"
     , gup     = [catAv "l"]
     , ganchor = True
     , gtype   = Lex
     }

catAv = AvPair "cat"
idxAv = AvPair "idx"

emptyGN = GN
  { gnname   = ""
  , gup      = []
  , gdown    = []
  , ganchor  = False
  , glexeme  = []
  , gtype    = Other
  , gaconstr = False
  , gorigin  = "test"
  }

toSchemaTree :: Ttree (GNode GeniVal) -> SchemaTree
toSchemaTree st = TT { params  = params st
                     , pfamily = pfamily st
                     , pidname = pidname st
                     , ptype   = ptype st
                     , ptrace  = ptrace st
                     , pinterface = pinterface st
                     , psemantics = psemantics st
                     , tree    = fmap toSchemaNode (tree st)
                     }

toSchemaNode :: GNode GeniVal -> GNode SchemaVal
toSchemaNode gn = GN { gup      = map promote (gup gn)
                     , gdown    = map promote (gdown gn)
                     , gnname   = gnname gn
                     , ganchor  = ganchor gn
                     , glexeme  = glexeme gn
                     , gtype    = gtype gn
                     , gaconstr = gaconstr gn
                     , gorigin  = gorigin gn
                     }
 where
  promote (AvPair a v) = AvPair a (SchemaVal [v])
