% GenI surface realiser
% Copyright (C) 2005 Carlos Areces and Eric Kow
%
% This program is free software; you can redistribute it and/or
% modify it under the terms of the GNU General Public License
% as published by the Free Software Foundation; either version 2
% of the License, or (at your option) any later version.
%
% This program is distributed in the hope that it will be useful,
% but WITHOUT ANY WARRANTY; without even the implied warranty of
% MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
% GNU General Public License for more details.
%
% You should have received a copy of the GNU General Public License
% along with this program; if not, write to the Free Software
% Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA  02111-1307, USA.

\begin{code}
{-# LANGUAGE TypeSynonymInstances #-}
{-# OPTIONS_GHC -fno-warn-orphans #-}
module NLP.GenI.GraphvizShowPolarity
where

import Data.List (intersperse, intercalate)
import qualified Data.Map as Map
import Data.Maybe ( catMaybes )
import Data.GraphViz
import Data.GraphViz.Printing ( printIt )

import NLP.GenI.Btypes(showSem)
import NLP.GenI.General(showInterval, isEmptyIntersect)
import NLP.GenI.Polarity(PolAut, PolState(PolSt), NFA(states, transitions), finalSt)
import NLP.GenI.Graphviz(GraphvizShow(..), gvUnlines, gvNode, gvEdge)
import NLP.GenI.Tags(idname)
\end{code}

\begin{code}
instance GraphvizShow () PolAut where
  -- we want a directed graph (arrows)
  graphvizShowGraph f aut =
     "digraph aut {\n"
     ++ "rankdir=LR\n"
     ++ "ranksep = 0.02\n"
     ++ "pack=1\n"
     ++ "edge [ fontsize=10 ]\n"
     ++ "node [ fontsize=10 ]\n"
     ++ graphvizShowAsSubgraph f "aut" aut
     ++ "}"

  --
  graphvizShowAsSubgraph _ prefix aut =
    printIt $ DotGraph False True Nothing
            $ DotStmts [ NodeAttrs [ Shape Ellipse, Peripheries 1 ] ]
                       []
                       (zipWith (gvShowState fin) ids st)
                       (concat $ zipWith (gvShowTrans aut stmap) ids st)
    where
       st  = (concat.states) aut
       fin = finalSt aut
       ids = map (\x -> prefix ++ show x) ([0..] :: [Int])
       -- map which permits us to assign an id to a state
       stmap = Map.fromList $ zip st ids

gvShowState :: [PolState] -> String -> PolState -> DotNode String
gvShowState fin stId st =
  DotNode stId $ decorate [ Label . StrLabel . showSt $ st ]
  where
   showSt (PolSt pr ex po) =
          gvUnlines . catMaybes $
            [ Nothing -- Just (snd3 pr)
            , if null ex then Nothing else Just (showSem ex)
            , Just . intercalate "," $ map showInterval po
            ]
   decorate = if st `elem` fin
                 then (Peripheries 2 :)
                 else id

gvShowTrans :: PolAut -> Map.Map PolState String
               -> String -> PolState -> [DotEdge String]
gvShowTrans aut stmap idFrom st =
  let -- outgoing transition labels from st
      trans = Map.findWithDefault Map.empty st $ transitions aut
      -- returns the graphviz dot command to draw a labeled transition
      drawTrans (stTo,x) = case Map.lookup stTo stmap of
                             Nothing   -> drawTrans' ("id_error_" ++ (sem_ stTo)) x
                             Just idTo -> drawTrans' idTo x
                           where sem_ (PolSt i _ _) = show i
                                 --showSem (PolSt (_,pred,_) _ _) = pred
      drawTrans' idTo x = DotEdge idFrom idTo True [Label (drawLabel x)]
      drawLabel labels  = StrLabel . gvUnlines $ labs
        where
          lablen  = length labels
          maxlabs = 6
          excess = "...and " ++ (show $ lablen - maxlabs) ++ " more"
          --
          labstrs = map (maybe "EMPTY" idname) labels
          labs = if lablen > maxlabs
                 then take maxlabs labstrs ++ [ excess ]
                 else labstrs
  in map drawTrans (Map.toList trans)
\end{code}
