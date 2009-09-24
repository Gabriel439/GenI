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

\chapter{Morphology}
\label{cha:Morphology}

This module handles mostly everything to do with morphology in Geni.
There are two basic tasks: morphological input and output.  
GenI farms out morphology to whatever third party program you
specify in the configuration file.

\begin{code}
module NLP.GenI.Morphology where
\end{code}

\ignore{
\begin{code}
import Data.Maybe (isNothing, isJust)
import Data.List (intersperse)
import Data.Tree
import qualified Data.Map as Map
import System.IO
import System.Process

import NLP.GenI.Btypes
import NLP.GenI.General
import NLP.GenI.Tags
\end{code}
}

\begin{code}
type MorphFn = Pred -> Maybe Flist
\end{code}

\section{Input}

Morphological input means attaching morphological features on trees.  The
user specifies morphological input through the input semantics.  Our job
is to identify morphological predicates like \semexpr{plural(x)} and 
apply features like \fs{\it num:pl} on the relevant trees.

\begin{code}
-- | Converts information from a morphological information file into GenI's
--   internal format.
readMorph :: [(String,[AvPair])] -> MorphFn
readMorph minfo pred_ = Map.lookup key fm
  where fm = Map.fromList minfo
        key = show $ snd3 pred_

-- | Filters away from an input semantics any literals whose realisation is
--   strictly morphological.  The first argument tells us helps identify the
--   morphological literals -- it associates literals with morphological stuff;
--   if it returns 'Nothing', then it is non-morphological
stripMorphSem :: MorphFn -> Sem -> Sem
stripMorphSem morphfn tsem = 
  [ l | l <- tsem, (isNothing.morphfn) l ]

-- | 'attachMorph' @morphfn sem cands@ does the bulk of the morphological
--   input processing.  We use @morphfn@ to determine which literals in
--   @sem@ contain morphological information and what information they contain.
--   Then we attach this morphological information to the relevant trees in
--   @cand@.  A tree is considered relevant w.r.t to a morphological
--   literal if its semantics contains at least one literal whose first index
--   is the same as the first index of the morphological literal.
attachMorph :: MorphFn -> Sem -> [TagElem] -> [TagElem]
attachMorph morphfn sem cands = 
  let -- relevance of a tree wrt to an index
      relTree i = not.null.relfilt.tsemantics
        where relfilt = filter (relLit i)  
      relLit i l = if null args then False else (head args == i)
        where args = thd3 l
      -- perform the attachment for a tree if it is relevant
      attachHelper :: GeniVal -> Flist -> TagElem -> TagElem  
      attachHelper i mfs t = 
        if relTree i t then attachMorphHelper mfs t else t 
      -- perform all attachments for a literal
      attach :: Pred -> [TagElem] -> [TagElem]
      attach l cs = 
        case morphfn l of 
          Nothing  -> cs
          Just mfs -> map (attachHelper i mfs) cs
        where i = if null args then GAnon else head args
              args = thd3 l 
  in foldr attach cands sem 

-- | Actually unify the morphological features into the anchor node
--
--   FIXME: we'll need to make sure this still works as promised 
--   when we implement co-anchors.
attachMorphHelper :: Flist -> TagElem -> TagElem
attachMorphHelper mfs te = 
  let -- unification with anchor
      tt     = ttree te 
      anchor = head $ filterTree fn tt
               where fn a = (ganchor a && gtype a == Lex)
  in case unifyFeat mfs (gup anchor) of
     Nothing -> error ("Morphological unification failure on " ++ idname te)
     Just (unf,subst) ->
      let -- perform replacements
          te2 = replace subst te 
          tt2 = ttree te2
          -- replace the anchor with the unification results
          newgdown = replace subst (gdown anchor) 
          newa = anchor { gup = unf, gdown = newgdown }
      in te2 { ttree = setMorphAnchor newa tt2 }

setMorphAnchor :: GNode -> Tree GNode -> Tree GNode
setMorphAnchor n t =
  let filt (Node a _) = (gtype a == Lex && ganchor a)
      fn (Node _ l)   = Node n l
  in (head.fst) $ listRepNode fn filt [t]
\end{code}

\section{Output}

Output (\jargon{morphological generation}) refers to the actual process
of converting lemmas and morphological information into inflected forms.
We do this by calling some third party software specified by the user.

The morphological software must accept on stdin a newline delimited list
of lemmas and features, with \verb$----$ (four hyphens) as an intersentence
delimiter:

\begin{verbatim}
le       [num:sg gen:f]
fille    [num:sg]
detester [num:sg tense:past]
le       [num:pl gen:m]
garcon   [num:pl]
----     []
ce       []
etre     []
le       [num:pl]
garcon   [num:pl]
que      []
le       [num:sg gen:f]
fille    [num:sg] 
detester [num:sg tense:past]
\end{verbatim}

It must return inflected forms on stdout, \emph{sentences} delimited by
newlines. Note also that we expect exactly one result for every input.
Notice that the morphological generator can choose to delete
spaces or do other orthographical tricks in between words:

\begin{verbatim}
la fille detestait les garcons
c'est les garcons que la fille detestait
\end{verbatim}

If your morphological software does not do this, you could wrap it
with a simple shell or Perl script.

\begin{code}
-- | Extracts the lemmas from a list of uninflected sentences.  This is used
--   when the morphological generator is unavailable, doesn't work, etc.
sansMorph :: [(String,Flist)] -> [String]
sansMorph = singleton . unwords . (map fst)

-- | Converts a list of uninflected sentences into inflected ones by calling
---  the third party software.
-- FIXME: this doesn't actually support lists-of-results per input
-- will need to work it out
inflectSentencesUsingCmd :: String -> [[UninflectedDisjunction]] -> IO [[String]]
inflectSentencesUsingCmd morphcmd sentences =
  do -- add intersential delimiters
     let delim    = [("----",[])]
         morphlst = concat (intersperse delim sentences)
     -- format the stuff as input to the inflector
     let fn (lem,fs) = lem ++ " " ++ showFlist fs
         order = unlines $ map fn morphlst 
     -- run the inflector
     (toP, fromP, _, pid) <- runInteractiveCommand morphcmd
     hPutStrLn toP order
     hClose toP
     -- read the inflector output back as a list of strings
     (map (singleton . trim) . lines) `fmap` hGetContents fromP
  `catch` \e -> do ePutStrLn "Error calling morphological generator"
                   ePutStrLn $ show e
                   return $ map sansMorph sentences

singleton :: a -> [a]
singleton x = [x]
\end{code}
