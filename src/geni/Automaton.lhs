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

\chapter{Automaton}
\label{cha:Automaton}

\begin{code}
module Automaton 
  ( NFA(..), 
    finalSt,
    addTrans, lookupTrans)
where

import qualified Data.Map as Map
\end{code}

This module provides a simple, naive implementation of nondeterministic
finite automata (NFA).  The transition function consists of a Map, but 
there are also accessor function which help you query the automaton 
without worrying about how it's implemented.

\begin{enumerate}
\item The states are a list of lists, not just a simple flat list as 
  you might expect.  This allows you to optionally group your 
  states into ``columns'' (which is something we use in the 
  GenI polarity automaton optimisation).  If you don't want 
  columns, you can just make one big group out of all your states.
\item I'd love to reuse some other library out there, but Leon P. Smith's
  Automata library requires us to know before-hand the size of our alphabet,
  which is highly unacceptable for this task.  
\end{enumerate}

\begin{code}
data NFA st ab = NFA 
  { startSt :: st
  , isFinalSt :: st -> Bool
  , transitions :: Map.Map st (Map.Map ab [st])
  -- see chapter comments about list of list 
  , states    :: [[st]] }
\end{code}

\fnlabel{finalSt} returns all the final states of an automaton

\begin{code}
finalSt :: NFA st ab -> [st]
finalSt aut = concatMap (filter (isFinalSt aut)) (states aut)
\end{code}

\fnlabel{lookupTrans} takes an automaton, a state $st1$ and an element
$ab$ of the alphabet; and returns the state that $st1$ transitions to
via $a$, if possible. 

\begin{code}
lookupTrans :: (Ord ab, Ord st) => NFA st ab -> st -> ab -> [st]
lookupTrans aut st ab = Map.findWithDefault [] ab subT
  where subT = Map.findWithDefault Map.empty st (transitions aut) 
\end{code}

\begin{code}
addTrans :: (Ord ab, Ord st) => NFA st ab -> st -> ab -> st -> NFA st ab 
addTrans aut st1 ab st2 = 
  aut { transitions = Map.insert st1 newSubT oldT }
  where oldSt2   = Map.findWithDefault [] ab oldSubT 
        oldT     = transitions aut
        oldSubT  = Map.findWithDefault Map.empty st1 oldT 
        newSubT  = Map.insert ab (st2:oldSt2) oldSubT
\end{code}


