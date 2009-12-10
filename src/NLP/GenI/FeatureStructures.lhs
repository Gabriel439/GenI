% GenI surface realiser
% Copyright (C) 2005-2009 Carlos Areces and Eric Kow
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

\chapter{Feature structures}

\ignore{
\begin{code}
{-# OPTIONS_GHC -fno-warn-orphans #-}
module NLP.GenI.FeatureStructures where

import Data.Function (on)
import Data.Generics (Data)
import Data.Generics.PlateDirect
import Data.List (sortBy)
import Data.Typeable (Typeable)

import NLP.GenI.GeniVal
\end{code}
}

% ----------------------------------------------------------------------
\section{Core types}
% ----------------------------------------------------------------------

A feature structure is a list of attribute-value pairs.

\begin{code}
type Flist   = [AvPair]
data AvPair  = AvPair { avAtt :: String
                      , avVal ::  GeniVal }
  deriving (Ord, Eq, Data, Typeable)
\end{code}

% ----------------------------------------------------------------------
\section{Basic functions}
% ----------------------------------------------------------------------

\begin{code}
-- | Sort an Flist according with its attributes
sortFlist :: Flist -> Flist
sortFlist = sortBy (compare `on` avAtt)
\end{code}

\subsection{Traversal}

\begin{code}
instance Biplate AvPair GeniVal where
  biplate (AvPair a v) = plate AvPair |- a |* v

instance DescendGeniVal AvPair where
  descendGeniVal s (AvPair a v) = {-# SCC "descendGeniVal" #-} AvPair a (descendGeniVal s v)

instance DescendGeniVal a => DescendGeniVal (String, a) where
  descendGeniVal s (n,v) = {-# SCC "descendGeniVal" #-} (n,descendGeniVal s v)

instance DescendGeniVal ([String], Flist) where
  descendGeniVal s (a,v) = {-# SCC "descendGeniVal" #-} (a, descendGeniVal s v)

instance Collectable AvPair where
  collect (AvPair _ b) = collect b
\end{code}

\subsection{Pretty printing}

\begin{code}
showFlist :: Flist -> String
showFlist f = "[" ++ showPairs f ++ "]"

showPairs :: Flist -> String
showPairs = unwords . map showAv

showAv :: AvPair -> String
showAv (AvPair y z) = y ++ ":" ++ show z

instance Show AvPair where
  show = showAv
\end{code}

% --------------------------------------------------------------------
\section{Feature structure unification}
\label{sec:fs_unification}
% --------------------------------------------------------------------

Feature structure unification takes two feature lists as input.  If it
fails, it returns Nothing.  Otherwise, it returns a tuple with:

\begin{enumerate}
\item a unified feature structure list
\item a list of variable replacements that will need to be propagated
      across other feature structures with the same variables
\end{enumerate}

Unification fails if, at any point during the unification process, the
two lists have different constant values for the same attribute.
For example, unification fails on the following inputs because they have
different values for the \textit{number} attribute:

\begin{quotation}
\fs{\it cat:np\\ \it number:3\\}
\fs{\it cat:np\\ \it number:2\\}
\end{quotation}

Note that the following input should also fail as a result on the
coreference on \textit{?X}.

\begin{quotation}
\fs{\it cat:np\\ \it one: 1\\  \it two:2\\}
\fs{\it cat:np\\ \it one: ?X\\ \it two:?X\\}
\end{quotation}

On the other hand, any other pair of feature lists should unify
succesfully, even those that do not share the same attributes.
Below are some examples of successful unifications:

\begin{quotation}
\fs{\it cat:np\\ \it one: 1\\  \it two:2\\}
\fs{\it cat:np\\ \it one: ?X\\ \it two:?Y\\}
$\rightarrow$
\fs{\it cat:np\\ \it one: 1\\ \it two:2\\},
\end{quotation}

\begin{quotation}
\fs{\it cat:np\\ \it number:3\\}
\fs{\it cat:np\\ \it case:nom\\}
$\rightarrow$
\fs{\it cat:np\\ \it case:nom\\ \it number:3\\},
\end{quotation}

\begin{code}
-- | 'unifyFeat' performs feature structure unification, under the
--   these assumptions about the input:
--
--    * Features are ordered
--
--    * The Flists do not share variables (renaming has already
--      been done.
--
--   The features are allowed to have different sets of attributes,
--   beacuse we use 'alignFeat' to realign them.
unifyFeat :: Monad m => Flist -> Flist -> m (Flist, Subst)
unifyFeat f1 f2 =
  {-# SCC "unification" #-}
  let (att, val1, val2) = unzip3 $ alignFeat f1 f2
  in att `seq`
     do (res, subst) <- unify val1 val2
        return (zipWith AvPair att res, subst)

-- | 'alignFeat' is a pre-procesing step used to ensure that feature structures
--   have the same set of keys.  If a key is missing in one, we copy it to the
--   other with an anonymous value.
--
--   The two feature structures must be sorted for this to work
alignFeat :: Flist -> Flist -> [(String,GeniVal,GeniVal)]
alignFeat f1 f2 = alignFeatH f1 f2 []

alignFeatH :: Flist -> Flist -> [(String,GeniVal,GeniVal)] -> [(String,GeniVal,GeniVal)]
alignFeatH [] [] acc = reverse acc
alignFeatH [] (AvPair f v :x) acc = alignFeatH [] x ((f,GAnon,v) : acc)
alignFeatH x [] acc = alignFeatH [] x acc
alignFeatH fs1@(AvPair f1 v1:l1) fs2@(AvPair f2 v2:l2) acc =
   case compare f1 f2 of
     EQ -> alignFeatH l1 l2  ((f1, v1, v2) : acc)
     LT -> alignFeatH l1 fs2 ((f1, v1, GAnon) : acc)
     GT -> alignFeatH fs1 l2 ((f2, GAnon, v2) : acc)
\end{code}
