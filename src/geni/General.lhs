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

\chapter{General}

This module provides some very generic, non-Geni specific functions on strings,
trees and other miscellaneous odds and ends.

\begin{code}
module General 
where
\end{code}

\ignore{
\begin{code}
import Data.Char (isSpace)
import Data.FiniteMap (emptyFM, FiniteMap, addToFM_C)
import Data.List (intersect)
import Data.Tree
import System.Directory (getCurrentDirectory, setCurrentDirectory)
\end{code}
}

\section{Strings}

Haskell seems to be missing a string library.  Here are some functions I had to
implement.

\begin{code}
trim :: String -> String
trim = reverse . (dropWhile isSpace) . reverse . (dropWhile isSpace) 
\end{code}

\section{Three-tuples}

\begin{code}
fst3 :: (a,b,c) -> a
fst3 (x,_,_) = x

snd3 :: (a,b,c) -> b
snd3 (_,x,_) = x

thd3 :: (a,b,c) -> c
thd3 (_,_,x) = x
\end{code}

\section{Trees}

\paragraph{mapTree} is like map, except on Trees.  This has to be
tucked away somewhere (i.e. i must be reinventing the wheel)!

\begin{code}
mapTree :: (a->b) -> Tree a -> Tree b
mapTree fn (Node a []) = (Node (fn a) [])
mapTree fn (Node a l)  = (Node (fn a) (map (mapTree fn) l))
\end{code}

\paragraph{filterTree} is like filter, except on Trees.  Filter 
might not be a good name, though, because we return a list of 
nodes, not a tree.

\begin{code}
filterTree :: (a->Bool) -> Tree a -> [a]
filterTree fn (Node a []) = 
  if fn a then [a] else []
filterTree fn (Node a l)  = 
  if fn a then a:next else next
  where next = concatMap (filterTree fn) l
\end{code}

\paragraph{treeLeaves} returns the leaf nodes of a Tree.

\begin{code}
treeLeaves :: Tree a -> [a]
treeLeaves (Node n []) = [n]
treeLeaves (Node _ l ) = concatMap treeLeaves l
\end{code}

\paragraph{listRepNode} is a generic tree-walking/editing function.  It
takes a replacement function, a filtering function and a tree.  It
returns the tree, except that the first node for which the filtering
function returns True is transformed with the replacement function.

\begin{code}
listRepNode :: (Tree a -> Tree a) -> (Tree a -> Bool) 
              -> [Tree a] -> ([Tree a], Bool)
listRepNode _ _ [] = ([], False)
listRepNode fn filt ((n@(Node a l1)):l2) = 
  if filt n
  then ((fn n):(l2), True)
  else let (lt1, flag1) = listRepNode fn filt l1 
           (lt2, flag2) = listRepNode fn filt l2
       in if flag1
          then ((Node a lt1):l2, flag1)
          else (n:lt2, flag2)
\end{code}

\section{Files}

\begin{code}
slash = "/"
\end{code}

\paragraph{geniReadFile}

readFile in Linux seems to change the current directory to where the file is:
we force it back to one where GenI was called so that the GUI doesn't start
behaving funny.

\begin{code}
geniReadFile filename = do
     curDir <- getCurrentDirectory
     contents <- readFile filename
     setCurrentDirectory curDir
     return contents
\end{code}

\section{Other}

\begin{code}
type BitVector = Integer
\end{code}

\paragraph{isEmptyIntersect} is true if the intersection of two lists is
empty.

\begin{code}
isEmptyIntersect :: (Eq a) => [a] -> [a] -> Bool
isEmptyIntersect a b = null $ intersect a b
\end{code}

\paragraph{groupByFM} serves the same function as Data.List.groupBy.  It
groups together items by some property they have in common. The
difference is that the property is used as a key to a FiniteMap that you
can lookup.  \texttt{fn} extracts the property from the item.

\begin{code}
groupByFM :: (Ord b) => (a -> b) -> [a] -> (FiniteMap b [a])
groupByFM fn list = 
  let addfn  x acc key = addToFM_C (++) acc key [x]
      helper x acc     = addfn x acc (fn x)
  in foldr helper emptyFM list 
\end{code}

\paragraph{multiGroupByFM} is the same as groupByFM, except that we
assume an item can appear in multiple groups.  \texttt{fn} extracts the
property from the item, and returns multiple results in the form of a
list.

\begin{code}
multiGroupByFM :: (Ord b) => (a -> [b]) -> [a] -> (FiniteMap b [a])
multiGroupByFM fn list = 
  let addfn  x key acc = addToFM_C (++) acc key [x]
      helper x acc     = foldr (addfn x) acc (fn x)
  in foldr helper emptyFM list 
\end{code}


