--  GenI surface realiser
--  Copyright (C) 2009 Eric Kow
--
--  This program is free software; you can redistribute it and/or
--  modify it under the terms of the GNU General Public License
--  as published by the Free Software Foundation; either version 2
--  of the License, or (at your option) any later version.
--
--  This program is distributed in the hope that it will be useful,
--  but WITHOUT ANY WARRANTY; without even the implied warranty of
--  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
--  GNU General Public License for more details.
--
--  You should have received a copy of the GNU General Public License
--  along with this program; if not, write to the Free Software
--  Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA  02111-1307, USA.

{-# LANGUAGE FlexibleInstances, TypeSynonymInstances, MultiParamTypeClasses, FlexibleContexts #-}
{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -fno-warn-orphans #-}
-- | Outputting core GenI data to graphviz.
module NLP.GenI.GraphvizShow
where

import Data.FullList ( fromFL )
import Data.List ( nub )
import Data.List.Split (wordsBy)
import Data.Maybe(listToMaybe, maybeToList, mapMaybe)

import Data.GraphViz
import Data.GraphViz.Attributes.Complete
import qualified Data.Text.Lazy as TL
import qualified Data.Text as T

import NLP.GenI.Tags
 ( TagDerivation,
   TagItem(..), TagElem(..),
   DerivationStep(..), dsChild, dsParent
 )
import NLP.GenI.Btypes (AvPair(..),
               GNode(..), GType(..), Flist,
               showSem,
               )
import NLP.GenI.General ( clumpBy )
import NLP.GenI.GeniVal (GeniVal(..), isConst)
import NLP.GenI.Graphviz
  ( GraphvizShow(graphvizShowAsSubgraph, graphvizLabel, graphvizParams)
  , GraphvizShowNode(graphvizShowNode)
  , GraphvizShowString(graphvizShow)
  , gvUnlines, gvShowTree
  )
import NLP.GenI.Semantics ( Sem )

-- ----------------------------------------------------------------------
--
-- ----------------------------------------------------------------------

-- | Imagine some kind of menu system that displays a list of items
--   and displays the selected item
data GvItem flg itm = GvHeader String       -- ^ no actual item
                    | GvItem String flg itm

gvItemLabel :: GvItem a b -> String
gvItemLabel (GvHeader h)   = h
gvItemLabel (GvItem l _ _) = l

gvItemSetFlag :: f -> GvItem f a -> GvItem f a
gvItemSetFlag _  g@(GvHeader _) = g
gvItemSetFlag f2 (GvItem l _ x) = GvItem l f2 x

instance GraphvizShow a => GraphvizShow (GvItem () a) where
  graphvizShowAsSubgraph _ (GvHeader _ )   = []
  graphvizShowAsSubgraph p (GvItem _ () b) = graphvizShowAsSubgraph p b

  graphvizLabel (GvHeader _)     = ""
  graphvizLabel (GvItem _ () b)  = graphvizLabel b

  graphvizParams (GvHeader _)    = []
  graphvizParams (GvItem _ () b) = graphvizParams b

instance Functor (GvItem flg) where
  fmap _  (GvHeader h)     = GvHeader h
  fmap fn (GvItem l flg x) = GvItem l flg (fn x)

-- ----------------------------------------------------------------------
-- For GraphViz
-- ----------------------------------------------------------------------

type GNodeHighlights = (Bool, Highlights (GNode GeniVal))
type Highlights a    = (a -> Maybe Color)

nullHighlighter :: Highlights a
nullHighlighter = const Nothing

addNullHighlighter :: GvItem Bool x -> GvItem GNodeHighlights x
addNullHighlighter (GvHeader h)   = GvHeader h
addNullHighlighter (GvItem l f x) = GvItem l (f, nullHighlighter) x

instance GraphvizShow (GvItem Bool TagElem) where
 graphvizShowAsSubgraph p = graphvizShowAsSubgraph p . addNullHighlighter
 graphvizLabel  = graphvizLabel  . addNullHighlighter
 graphvizParams = graphvizParams . addNullHighlighter

instance TagItem t => GraphvizShow (GvItem GNodeHighlights t) where
 graphvizShowAsSubgraph _      (GvHeader _) = []
 graphvizShowAsSubgraph prefix (GvItem _ (sf, hfn) te) =
    [gvShowTree (prefix `TL.append` "DerivedTree0")
                (fmap toDetails (tgTree te))
    ]
  where
   toDetails x = Details { ddetails = sf
                         , dcolour  = hfn x
                         , dnode    = x
                         }

 graphvizLabel (GvHeader _)    = ""
 graphvizLabel (GvItem _ _ te) =
  -- we display the tree semantics as the graph label
  let treename   = "name: "      `TL.append` TL.pack (tgIdName te)
      semlist    = "semantics: " `TL.append` gvShowSem (tgSemantics te)
  in gvUnlines [ treename, semlist ]

 graphvizParams _ =
  [ GraphAttrs [ FontSize 10
               , RankSep [0.3]
               ]
  , NodeAttrs  [ FontSize 10
               ]
  , EdgeAttrs  [ FontSize 10
               , ArrowHead normal
               ]
  ]

gvShowSem :: Sem -> TL.Text
gvShowSem = gvUnlines . map TL.pack . map unwords . clumpBy length 72 . words . showSem

-- ----------------------------------------------------------------------
-- Helper functions for the TagElem GraphvizShow instance
-- ----------------------------------------------------------------------

data Details n = Details { ddetails :: Bool
                         , dcolour  :: Maybe Color
                         , dnode    :: n
                         }

instance GraphvizShowNode (Details (GNode GeniVal)) where
 -- compact -> (node, mcolour) -> String
 graphvizShowNode prefix dn =
   let -- attributes
       filledParam         = Style [SItem Filled []]
       fillcolorParam      = FillColor (X11Color LemonChiffon)
       shapeRecordParam    = Shape Record
       shapePlaintextParam = Shape PlainText
       --
       colorParams = case dcolour dn of
                     Nothing -> []
                     Just c  -> [ FontColor c ]
       shapeParams = if ddetails dn
                     then [ shapeRecordParam, filledParam, fillcolorParam ]
                     else [ shapePlaintextParam ]
       -- content
       gn    = dnode dn
       stub  = showGnStub gn
       extra = showGnDecorations gn
       summary = if TL.null extra
                 then FieldLabel stub
                 else FlipFields [ FieldLabel stub, FieldLabel extra ]
       body = Label $
              if not (ddetails dn) then (StrLabel (graphvizShow_ gn))
              else RecordLabel [ FlipFields $
                                   [ summary
                                   , FieldLabel . showFs $ gup gn
                                   ] ++ (maybeFs (gdown gn))
                   ]
        where showFs = gvUnlines . map graphvizShow_
              maybeFs fs = if null fs then [] else [FieldLabel (showFs fs)]
   in DotNode prefix (body : shapeParams ++ colorParams)

instance GraphvizShowString (GNode GeniVal) where
  graphvizShow gn =
    let stub  = showGnStub gn
        extra = showGnDecorations gn
    in stub `TL.append` extra

instance GraphvizShowString (AvPair GeniVal) where
  graphvizShow (AvPair a v) = TL.fromChunks [a, ":"] `TL.append` graphvizShow_ v

instance GraphvizShowString GeniVal where
  graphvizShow g =
    case (gLabel g, gConstraints g) of
      (Nothing, Nothing) -> "?_"
      (Nothing, Just cs) -> constraints cs
      (Just l,  Nothing) -> '?' `TL.cons` (TL.pack l)
      (Just l,  Just cs) -> '?' `TL.cons` (TL.concat [TL.pack l, "/", constraints cs])
   where
    constraints cs = TL.intercalate "!" $ map TL.fromChunks [fromFL cs]

showGnDecorations :: GNode GeniVal -> TL.Text
showGnDecorations gn =
  case gtype gn of
  Subs -> "↓"
  Foot -> "*"
  _    -> if gaconstr gn then "ᴺᴬ"   else ""

showGnStub :: GNode GeniVal -> TL.Text
showGnStub gn =
 let cat = case getGnVal gup "cat" gn of
           Nothing -> ""
           Just v  -> graphvizShow_ v
     --
     getIdx f =
       case getGnVal f "idx" gn of
       Nothing -> ""
       Just v  -> if isConst v then graphvizShow_ v else ""
     idxT = getIdx gup
     idxB = getIdx gdown
     idx  = tackOn "." idxT idxB
     --
     lexeme  = TL.intercalate "!" (map TL.pack (glexeme gn))
 in TL.intercalate ":" $ filter (not . TL.null) [ cat, idx, lexeme ]

getGnVal :: (GNode GeniVal -> Flist GeniVal) -> T.Text -> GNode GeniVal -> Maybe GeniVal
getGnVal getFeat attr gn =
  listToMaybe [ v | AvPair a v <- getFeat gn, a == attr ]

-- | @x `tackOn p` y@` is @TL.concat [x, p, y]@ if @y@ is not null
--   otherwise is just x
tackOn :: TL.Text -> TL.Text -> TL.Text -> TL.Text
tackOn p x y = if TL.null y then x else TL.concat [ x, p, y ]

graphvizShow_ :: GraphvizShowString a => a -> TL.Text
graphvizShow_ = graphvizShow

-- ----------------------------------------------------------------------
-- Derivation tree
-- ----------------------------------------------------------------------

graphvizShowDerivation :: TagDerivation -> [DotSubGraph TL.Text]
graphvizShowDerivation = maybeToList . derivationToGv

derivationToGv :: TagDerivation -> Maybe (DotSubGraph TL.Text)
derivationToGv deriv =
 if null histNodes
    then Nothing
    else Just $ DotSG False Nothing $ DotStmts atts [] nodes edges
  where
    atts = [ NodeAttrs [ Shape PlainText ]
           , EdgeAttrs [ ArrowHead noArrow ]
           ]
    nodes = map mkNode histNodes
    edges = mapMaybe mkEdge deriv
    --
    histNodes = reverse $ nub $ concatMap (\d -> dsChild d : maybeToList (dsParent d)) deriv
    mkNode n  =
      DotNode (gvDerivationLab n) [ Label . StrLabel $ label n ]
    mkEdge ds = do
     p <- dsParent ds
     return $ DotEdge (gvDerivationLab p)
                      (gvDerivationLab (dsChild ds))
                      (edgeStyle ds)
    edgeStyle (AdjunctionStep {}) = [Style [SItem Dashed []]]
    edgeStyle _ = []
    label n = case wordsBy (== ':') n of
              name:fam:tree:_ -> TL.pack $ name ++ ":" ++ fam ++ "\n" ++ tree
              _               -> TL.pack n `TL.append` " (geni/gv ERROR)"

gvDerivationLab :: String -> TL.Text
gvDerivationLab xs = TL.pack ("Derivation" ++ gvMunge xs)

-- | Node names can't have hyphens in them and newlines within the node
--   labels should be represented literally as @\\n@.
gvMunge :: String -> String
gvMunge = map dot2x . filter (/= ':') . filter (/= '-')

dot2x :: Char -> Char
dot2x '.' = 'x'
dot2x c   = c
