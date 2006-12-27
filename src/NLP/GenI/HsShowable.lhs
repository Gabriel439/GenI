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

\chapter{HsShowable}

One idea I'm experimenting with is dumping the grammars into Haskell, haskell which will
need to be linked against GenI in order to produce a generator.  This might make the whole
lexical selection thing og a lot faster.

\begin{code}
module NLP.GenI.HsShowable
where
\end{code}

\ignore{
\begin{code}
import Data.Tree
import Data.List(intersperse,nub)
import qualified Data.Map

import NLP.GenI.General (mapTree)
import NLP.GenI.Tags
 ( TagElem(TE), idname,
   tsemantics, ttree, tinterface, ttype, ttreename,
 )
import NLP.GenI.Btypes (GeniVal(GConst, GVar, GAnon), AvPair, Ptype(..),
               Ttree(TT, params, pidname, pfamily, pinterface, ptype, tree, psemantics, ptrace),
               GNode(..), GType(..), Flist,
               isConst,
               Pred, showSem,
               TestCase(..),
               )
\end{code}
}

\begin{code}
class HsShowable a where
  hsShow :: a -> String
  hsShow x = hsShows x ""
  hsShows :: a -> ShowS

hsParens, hsBrackets :: ShowS -> ShowS
hsParens fn   = showChar '(' . fn . showChar ')'
hsBrackets fn = showChar '[' . fn . showChar ']'

unwordsByS :: ShowS -> [ShowS] -> ShowS
unwordsByS _   [] = id
unwordsByS sep ss = foldr1 (\s r -> s . sep . r) ss

hsList, hsLongList :: [ShowS] -> ShowS
hsList ss     = hsBrackets $ unwordsByS (showChar ',') ss
hsLongList ss = hsBrackets $ unwordsByS (showString "\n\n,")  ss

hsConstructor :: String -> [ShowS] -> ShowS
hsConstructor c ss =
  hsParens $ showString c
           . showChar ' '
           . unwordsByS (showChar ' ') ss

instance HsShowable String where hsShows = shows
instance HsShowable Bool where hsShows = shows
instance HsShowable Int  where hsShows = shows
instance HsShowable Integer where hsShows = shows

instance HsShowable Ptype where hsShows = shows
instance HsShowable GType where hsShows = shows

-- | :-( I wish I could make do this with a default, overridable instance instead
--   basically, i would like to use hsList everywhere unless there is a specific
--   instance declaration, like one for String
instance HsShowable a => HsShowable [a] where
 hsShows xs = hsList (map hsShows xs)

instance (HsShowable a, HsShowable b) => HsShowable (a,b) where
 hsShows (a,b) = hsParens $ (hsShows a) . (showChar ',') . (hsShows b)

instance (HsShowable a, HsShowable b, HsShowable c) => HsShowable (a,b,c) where
 hsShows (a,b,c) = hsParens $ (hsShows a) . (showChar ',') . (hsShows b) . (showChar ',')  . (hsShows c)

instance (HsShowable a) => HsShowable (Tree a) where
 hsShows (Node a k) = hsConstructor "Node" [hsShows a, hsShows k]

-- | Note that you'll need to @import qualified Data.Map@
instance (HsShowable a, HsShowable b) => HsShowable (Data.Map.Map a b) where
 hsShows m | Data.Map.null m = showString "Data.Map.empty"
 hsShows m = hsParens $ (showString "Data.Map.fromList ")
                      . (hsShows (Data.Map.toList m))

instance HsShowable a => HsShowable (Maybe a) where
 hsShows Nothing  = showString "Nothing"
 hsShows (Just x) = hsConstructor "Just" [hsShows x]

instance HsShowable GeniVal where
 hsShows (GConst xs) = hsConstructor "GConst" [hsShows xs]
 hsShows (GVar xs)   = hsConstructor "GVar" [hsShows xs]
 hsShows GAnon       = showString "GAnon"

instance HsShowable GNode where
 hsShows (GN a b c d e f g h) =
   hsConstructor "GN"
    [ hsShows a, hsShows b, hsShows c, hsShows d
    , hsShows e, hsShows f, hsShows g, hsShows h]

instance HsShowable TagElem where
 hsShows (TE a b c d e f g h i j) =
  hsConstructor "TE"
   [ hsShows a, hsShows b, hsShows c, hsShows d
   , hsShows e, hsShows f, hsShows g, hsShows h
   , hsShows i, hsShows j]

instance HsShowable f => HsShowable (Ttree f) where
 hsShows (TT a b c d e f g h) = hsConstructor "TT"
   [ hsShows a, hsShows b, hsShows c, hsShows d
   , hsShows e, hsShows f, hsShows g, hsShows h]
\end{code}
